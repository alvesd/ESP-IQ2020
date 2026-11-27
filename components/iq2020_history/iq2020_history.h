#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

#include "esphome/components/sensor/sensor.h"
#include "esphome/components/text_sensor/text_sensor.h"
#include "esphome/components/time/real_time_clock.h"
#include "esphome/core/component.h"
#include "esphome/core/preferences.h"

namespace esphome {
namespace iq2020_history {

/// Fixed-size, zero-heap-allocation 3-tier metrics history persisted to ESP32 NVS:
///   Tier 1: 14 days at configurable bucket_hours (6 = 56 slots, 12 = 28 slots, 24 = 14 slots)
///   Tier 2: 31 local civil-day buckets (daily totals & averages)
///   Tier 3: 24 local calendar-month buckets (2-year annual rollups)
class IQ2020History : public PollingComponent {
 public:
  static constexpr size_t kMaxSlots = 56;
  static constexpr size_t kDailySlots = 31;
  static constexpr size_t kMonthlySlots = 24;
  static constexpr int16_t kMissing = INT16_MIN;
  static constexpr uint16_t kMissingU16 = 0xFFFF;
  static constexpr uint32_t kMagic = 0x49514832UL;  // 'IQH2'
  static constexpr uint16_t kVersion = 2;

  struct HistoryBlob {
    uint32_t magic;
    uint16_t version;
    uint8_t bucket_hours;
    uint8_t last_month;
    uint8_t last_day;
    uint8_t reserved;
    int16_t last_year;
    uint32_t last_bucket_slot;
    int32_t last_day_slot;
    int32_t last_month_slot;

    // Reboot-safe accumulators for finalized days within the current calendar month.
    uint32_t month_completed_energy_x100;
    uint32_t month_completed_heater_x10;
    uint32_t day_heater_start_sec;
    int32_t month_temp_sum_x10;
    int32_t month_power_sum;
    int32_t month_salt_sum;
    uint16_t month_temp_days;
    uint16_t month_power_days;
    uint16_t month_salt_days;
    uint16_t month_energy_days;
    uint16_t month_heater_days;
    uint16_t reserved2;

    // Tier 1: up to 14d at bucket_hours
    int16_t water_temp_x10[kMaxSlots];
    int16_t power_w[kMaxSlots];
    int16_t salt_level[kMaxSlots];
    int16_t free_heap_kb[kMaxSlots];

    // Tier 2: 31 local civil-day slots
    int16_t daily_energy_x100[kDailySlots];
    int16_t daily_water_temp_x10[kDailySlots];
    int16_t daily_power_w[kDailySlots];
    int16_t daily_salt_level[kDailySlots];
    int16_t daily_heater_hours_x10[kDailySlots];

    // Tier 3: 24 local calendar-month slots (2 years)
    uint16_t monthly_energy_x10[kMonthlySlots];
    int16_t monthly_water_temp_x10[kMonthlySlots];
    int16_t monthly_power_w[kMonthlySlots];
    int16_t monthly_salt_level[kMonthlySlots];
    int16_t monthly_heater_hours_x10[kMonthlySlots];
  };

  void set_time(time::RealTimeClock *time) { this->time_ = time; }
  void set_bucket_hours(uint8_t hours) {
    if (hours != 6 && hours != 12 && hours != 24) hours = 6;
    this->bucket_hours_ = hours;
    this->slot_count_ = (14 * 24) / hours;
  }

  void set_water_temp_source(sensor::Sensor *s) { this->water_temp_src_ = s; }
  void add_power_source(sensor::Sensor *s) { this->power_srcs_.push_back(s); }
  void add_energy_source(sensor::Sensor *s) { this->energy_srcs_.push_back(s); }
  void set_salt_source(sensor::Sensor *s) { this->salt_src_ = s; }
  void set_free_heap_source(sensor::Sensor *s) { this->free_heap_src_ = s; }
  void set_heater_runtime_source(sensor::Sensor *s) { this->heater_runtime_src_ = s; }

  void set_water_temp_history(text_sensor::TextSensor *ts) { this->water_temp_out_ = ts; }
  void set_water_temp_daily_history(text_sensor::TextSensor *ts) { this->water_temp_daily_out_ = ts; }
  void set_water_temp_monthly_history(text_sensor::TextSensor *ts) { this->water_temp_monthly_out_ = ts; }
  void set_power_history(text_sensor::TextSensor *ts) { this->power_out_ = ts; }
  void set_power_daily_history(text_sensor::TextSensor *ts) { this->power_daily_out_ = ts; }
  void set_power_monthly_history(text_sensor::TextSensor *ts) { this->power_monthly_out_ = ts; }
  void set_energy_history(text_sensor::TextSensor *ts) { this->energy_out_ = ts; }
  void set_energy_monthly_history(text_sensor::TextSensor *ts) { this->energy_monthly_out_ = ts; }
  void set_salt_history(text_sensor::TextSensor *ts) { this->salt_out_ = ts; }
  void set_salt_daily_history(text_sensor::TextSensor *ts) { this->salt_daily_out_ = ts; }
  void set_salt_monthly_history(text_sensor::TextSensor *ts) { this->salt_monthly_out_ = ts; }
  void set_heater_daily_history(text_sensor::TextSensor *ts) { this->heater_daily_out_ = ts; }
  void set_heater_monthly_history(text_sensor::TextSensor *ts) { this->heater_monthly_out_ = ts; }
  void set_free_heap_history(text_sensor::TextSensor *ts) { this->free_heap_out_ = ts; }

  float get_setup_priority() const override { return setup_priority::LATE; }

  void setup() override {
    this->pref_ = global_preferences->make_preference<HistoryBlob>(kMagic);
    if (!this->pref_.load(&this->blob_) || this->blob_.magic != kMagic || this->blob_.version != kVersion ||
        this->blob_.bucket_hours != this->bucket_hours_) {
      this->reset_blob_();
    } else {
      this->seed_accumulators_from_blob_();
    }
    this->publish_all_();
  }

  void update() override {
    bool rolled_over = false;
    if (this->time_ != nullptr) {
      auto now_t = this->time_->now();
      if (now_t.is_valid()) {
        const uint32_t cur_bucket =
            static_cast<uint32_t>(now_t.timestamp / (static_cast<time_t>(this->bucket_hours_) * 3600));
        if (this->blob_.last_bucket_slot == 0) {
          this->blob_.last_bucket_slot = cur_bucket;
        } else if (cur_bucket > this->blob_.last_bucket_slot) {
          const uint32_t delta = std::min<uint32_t>(cur_bucket - this->blob_.last_bucket_slot, this->slot_count_);
          shift_left_(this->blob_.water_temp_x10, kMaxSlots, delta);
          shift_left_(this->blob_.power_w, kMaxSlots, delta);
          shift_left_(this->blob_.salt_level, kMaxSlots, delta);
          shift_left_(this->blob_.free_heap_kb, kMaxSlots, delta);
          this->reset_bucket_accumulators_();
          this->blob_.last_bucket_slot = cur_bucket;
          rolled_over = true;
        }

        const int32_t cur_day = days_from_civil_(now_t.year, now_t.month, now_t.day_of_month);
        if (this->blob_.last_day_slot == 0) {
          this->blob_.last_day_slot = cur_day;
        } else if (cur_day > this->blob_.last_day_slot) {
          this->finalize_current_day_into_month_();
          this->update_current_month_slots_();
          const size_t delta =
              static_cast<size_t>(std::min<int32_t>(cur_day - this->blob_.last_day_slot, kDailySlots));
          shift_left_(this->blob_.daily_energy_x100, kDailySlots, delta);
          shift_left_(this->blob_.daily_water_temp_x10, kDailySlots, delta);
          shift_left_(this->blob_.daily_power_w, kDailySlots, delta);
          shift_left_(this->blob_.daily_salt_level, kDailySlots, delta);
          shift_left_(this->blob_.daily_heater_hours_x10, kDailySlots, delta);
          this->reset_day_accumulators_();
          this->blob_.day_heater_start_sec = 0xFFFFFFFFUL;
          this->blob_.last_day_slot = cur_day;
          rolled_over = true;
        }

        const int32_t cur_month = static_cast<int32_t>(now_t.year) * 12 + static_cast<int32_t>(now_t.month) - 1;
        if (this->blob_.last_month_slot == 0) {
          this->blob_.last_month_slot = cur_month;
        } else if (cur_month > this->blob_.last_month_slot) {
          const size_t delta =
              static_cast<size_t>(std::min<int32_t>(cur_month - this->blob_.last_month_slot, kMonthlySlots));
          shift_left_u16_(this->blob_.monthly_energy_x10, kMonthlySlots, delta);
          shift_left_(this->blob_.monthly_water_temp_x10, kMonthlySlots, delta);
          shift_left_(this->blob_.monthly_power_w, kMonthlySlots, delta);
          shift_left_(this->blob_.monthly_salt_level, kMonthlySlots, delta);
          shift_left_(this->blob_.monthly_heater_hours_x10, kMonthlySlots, delta);
          this->reset_month_completed_();
          this->blob_.last_month_slot = cur_month;
          rolled_over = true;
        }

        this->blob_.last_year = static_cast<int16_t>(now_t.year);
        this->blob_.last_month = static_cast<uint8_t>(now_t.month);
        this->blob_.last_day = static_cast<uint8_t>(now_t.day_of_month);
      }
    }

    bool got_first_sample = false;

    if (this->water_temp_src_ != nullptr && this->water_temp_src_->has_state() &&
        !std::isnan(this->water_temp_src_->state)) {
      const float wt = this->water_temp_src_->state;
      this->water_sum_ += wt;
      this->water_cnt_++;
      if (this->blob_.water_temp_x10[kMaxSlots - 1] == kMissing) got_first_sample = true;
      this->blob_.water_temp_x10[kMaxSlots - 1] =
          clamp_i16_(std::lround((this->water_sum_ / this->water_cnt_) * 10.0));

      this->day_water_sum_ += wt;
      this->day_water_cnt_++;
      if (this->blob_.daily_water_temp_x10[kDailySlots - 1] == kMissing) got_first_sample = true;
      this->blob_.daily_water_temp_x10[kDailySlots - 1] =
          clamp_i16_(std::lround((this->day_water_sum_ / this->day_water_cnt_) * 10.0));
    }

    if (!this->power_srcs_.empty()) {
      double p_sum = 0.0;
      bool any_power = false;
      for (auto *s : this->power_srcs_) {
        if (s != nullptr && s->has_state() && !std::isnan(s->state)) {
          p_sum += s->state;
          any_power = true;
        }
      }
      if (any_power) {
        this->power_sum_ += p_sum;
        this->power_cnt_++;
        if (this->blob_.power_w[kMaxSlots - 1] == kMissing) got_first_sample = true;
        this->blob_.power_w[kMaxSlots - 1] = clamp_i16_(std::lround(this->power_sum_ / this->power_cnt_));

        this->day_power_sum_ += p_sum;
        this->day_power_cnt_++;
        if (this->blob_.daily_power_w[kDailySlots - 1] == kMissing) got_first_sample = true;
        this->blob_.daily_power_w[kDailySlots - 1] =
            clamp_i16_(std::lround(this->day_power_sum_ / this->day_power_cnt_));
      }
    }

    if (this->salt_src_ != nullptr && this->salt_src_->has_state() && !std::isnan(this->salt_src_->state)) {
      const float st = this->salt_src_->state;
      this->salt_sum_ += st;
      this->salt_cnt_++;
      if (this->blob_.salt_level[kMaxSlots - 1] == kMissing) got_first_sample = true;
      this->blob_.salt_level[kMaxSlots - 1] = clamp_i16_(std::lround(this->salt_sum_ / this->salt_cnt_));

      this->day_salt_sum_ += st;
      this->day_salt_cnt_++;
      if (this->blob_.daily_salt_level[kDailySlots - 1] == kMissing) got_first_sample = true;
      this->blob_.daily_salt_level[kDailySlots - 1] =
          clamp_i16_(std::lround(this->day_salt_sum_ / this->day_salt_cnt_));
    }

    if (this->free_heap_src_ != nullptr && this->free_heap_src_->has_state() &&
        !std::isnan(this->free_heap_src_->state)) {
      this->heap_sum_kb_ += (this->free_heap_src_->state / 1024.0);
      this->heap_cnt_++;
      if (this->blob_.free_heap_kb[kMaxSlots - 1] == kMissing) got_first_sample = true;
      this->blob_.free_heap_kb[kMaxSlots - 1] = clamp_i16_(std::lround(this->heap_sum_kb_ / this->heap_cnt_));
    }

    if (!this->energy_srcs_.empty()) {
      float e_sum = 0.0f;
      bool any_energy = false;
      for (auto *s : this->energy_srcs_) {
        if (s != nullptr && s->has_state() && !std::isnan(s->state)) {
          e_sum += s->state;
          any_energy = true;
        }
      }
      if (any_energy) {
        if (e_sum > this->today_energy_max_kwh_) this->today_energy_max_kwh_ = e_sum;
        if (this->blob_.daily_energy_x100[kDailySlots - 1] == kMissing) got_first_sample = true;
        this->blob_.daily_energy_x100[kDailySlots - 1] =
            clamp_i16_(std::lround(this->today_energy_max_kwh_ * 100.0f));
      }
    }

    if (this->heater_runtime_src_ != nullptr && this->heater_runtime_src_->has_state() &&
        !std::isnan(this->heater_runtime_src_->state) && this->heater_runtime_src_->state >= 0.0f) {
      const uint32_t cur_sec = static_cast<uint32_t>(std::llround(this->heater_runtime_src_->state));
      if (this->blob_.day_heater_start_sec == 0xFFFFFFFFUL || cur_sec < this->blob_.day_heater_start_sec) {
        this->blob_.day_heater_start_sec = cur_sec;
      }
      double hrs = static_cast<double>(cur_sec - this->blob_.day_heater_start_sec) / 3600.0;
      hrs = std::min(24.0, std::max(0.0, hrs));
      if (this->blob_.daily_heater_hours_x10[kDailySlots - 1] == kMissing) got_first_sample = true;
      this->blob_.daily_heater_hours_x10[kDailySlots - 1] = clamp_i16_(std::lround(hrs * 10.0));
    }

    this->update_current_month_slots_();

    if (rolled_over) {
      this->save_now();
    }

    this->sample_ticks_++;
    if (rolled_over || got_first_sample || (this->sample_ticks_ % 5 == 0)) {
      this->publish_all_();
    }
  }

  void save_now() {
    this->pref_.save(&this->blob_);
    global_preferences->sync();
  }

  void on_shutdown() override { this->save_now(); }

 protected:
  void reset_blob_() {
    std::memset(&this->blob_, 0, sizeof(this->blob_));
    this->blob_.magic = kMagic;
    this->blob_.version = kVersion;
    this->blob_.bucket_hours = this->bucket_hours_;
    this->blob_.day_heater_start_sec = 0xFFFFFFFFUL;
    std::fill_n(this->blob_.water_temp_x10, kMaxSlots, kMissing);
    std::fill_n(this->blob_.power_w, kMaxSlots, kMissing);
    std::fill_n(this->blob_.salt_level, kMaxSlots, kMissing);
    std::fill_n(this->blob_.free_heap_kb, kMaxSlots, kMissing);

    std::fill_n(this->blob_.daily_energy_x100, kDailySlots, kMissing);
    std::fill_n(this->blob_.daily_water_temp_x10, kDailySlots, kMissing);
    std::fill_n(this->blob_.daily_power_w, kDailySlots, kMissing);
    std::fill_n(this->blob_.daily_salt_level, kDailySlots, kMissing);
    std::fill_n(this->blob_.daily_heater_hours_x10, kDailySlots, kMissing);

    std::fill_n(this->blob_.monthly_energy_x10, kMonthlySlots, kMissingU16);
    std::fill_n(this->blob_.monthly_water_temp_x10, kMonthlySlots, kMissing);
    std::fill_n(this->blob_.monthly_power_w, kMonthlySlots, kMissing);
    std::fill_n(this->blob_.monthly_salt_level, kMonthlySlots, kMissing);
    std::fill_n(this->blob_.monthly_heater_hours_x10, kMonthlySlots, kMissing);

    this->reset_bucket_accumulators_();
    this->reset_day_accumulators_();
    this->reset_month_completed_();
  }

  void seed_accumulators_from_blob_() {
    this->reset_bucket_accumulators_();
    this->reset_day_accumulators_();
    if (this->blob_.water_temp_x10[kMaxSlots - 1] != kMissing) {
      this->water_sum_ = this->blob_.water_temp_x10[kMaxSlots - 1] * 0.1;
      this->water_cnt_ = 1;
    }
    if (this->blob_.power_w[kMaxSlots - 1] != kMissing) {
      this->power_sum_ = this->blob_.power_w[kMaxSlots - 1];
      this->power_cnt_ = 1;
    }
    if (this->blob_.salt_level[kMaxSlots - 1] != kMissing) {
      this->salt_sum_ = this->blob_.salt_level[kMaxSlots - 1];
      this->salt_cnt_ = 1;
    }
    if (this->blob_.free_heap_kb[kMaxSlots - 1] != kMissing) {
      this->heap_sum_kb_ = this->blob_.free_heap_kb[kMaxSlots - 1];
      this->heap_cnt_ = 1;
    }

    if (this->blob_.daily_energy_x100[kDailySlots - 1] != kMissing) {
      this->today_energy_max_kwh_ = this->blob_.daily_energy_x100[kDailySlots - 1] * 0.01f;
    }
    if (this->blob_.daily_water_temp_x10[kDailySlots - 1] != kMissing) {
      this->day_water_sum_ = this->blob_.daily_water_temp_x10[kDailySlots - 1] * 0.1;
      this->day_water_cnt_ = 1;
    }
    if (this->blob_.daily_power_w[kDailySlots - 1] != kMissing) {
      this->day_power_sum_ = this->blob_.daily_power_w[kDailySlots - 1];
      this->day_power_cnt_ = 1;
    }
    if (this->blob_.daily_salt_level[kDailySlots - 1] != kMissing) {
      this->day_salt_sum_ = this->blob_.daily_salt_level[kDailySlots - 1];
      this->day_salt_cnt_ = 1;
    }
  }

  void reset_bucket_accumulators_() {
    this->water_sum_ = 0.0;
    this->water_cnt_ = 0;
    this->power_sum_ = 0.0;
    this->power_cnt_ = 0;
    this->salt_sum_ = 0.0;
    this->salt_cnt_ = 0;
    this->heap_sum_kb_ = 0.0;
    this->heap_cnt_ = 0;
  }

  void reset_day_accumulators_() {
    this->today_energy_max_kwh_ = 0.0f;
    this->day_water_sum_ = 0.0;
    this->day_water_cnt_ = 0;
    this->day_power_sum_ = 0.0;
    this->day_power_cnt_ = 0;
    this->day_salt_sum_ = 0.0;
    this->day_salt_cnt_ = 0;
  }

  void reset_month_completed_() {
    this->blob_.month_completed_energy_x100 = 0;
    this->blob_.month_completed_heater_x10 = 0;
    this->blob_.month_temp_sum_x10 = 0;
    this->blob_.month_power_sum = 0;
    this->blob_.month_salt_sum = 0;
    this->blob_.month_temp_days = 0;
    this->blob_.month_power_days = 0;
    this->blob_.month_salt_days = 0;
    this->blob_.month_energy_days = 0;
    this->blob_.month_heater_days = 0;
  }

  void finalize_current_day_into_month_() {
    const int16_t e = this->blob_.daily_energy_x100[kDailySlots - 1];
    if (e != kMissing && e >= 0) {
      this->blob_.month_completed_energy_x100 += static_cast<uint32_t>(e);
      this->blob_.month_energy_days++;
    }
    const int16_t h = this->blob_.daily_heater_hours_x10[kDailySlots - 1];
    if (h != kMissing && h >= 0) {
      this->blob_.month_completed_heater_x10 += static_cast<uint32_t>(h);
      this->blob_.month_heater_days++;
    }
    const int16_t wt = this->blob_.daily_water_temp_x10[kDailySlots - 1];
    if (wt != kMissing) {
      this->blob_.month_temp_sum_x10 += wt;
      this->blob_.month_temp_days++;
    }
    const int16_t pw = this->blob_.daily_power_w[kDailySlots - 1];
    if (pw != kMissing) {
      this->blob_.month_power_sum += pw;
      this->blob_.month_power_days++;
    }
    const int16_t sl = this->blob_.daily_salt_level[kDailySlots - 1];
    if (sl != kMissing) {
      this->blob_.month_salt_sum += sl;
      this->blob_.month_salt_days++;
    }
  }

  void update_current_month_slots_() {
    const int16_t today_e = this->blob_.daily_energy_x100[kDailySlots - 1];
    if (today_e != kMissing || this->blob_.month_energy_days > 0) {
      const uint32_t sum_x100 =
          this->blob_.month_completed_energy_x100 + ((today_e != kMissing && today_e > 0) ? static_cast<uint32_t>(today_e) : 0U);
      const uint32_t sum_x10 = (sum_x100 + 5U) / 10U;
      this->blob_.monthly_energy_x10[kMonthlySlots - 1] =
          static_cast<uint16_t>(std::min<uint32_t>(sum_x10, static_cast<uint32_t>(kMissingU16 - 1U)));
    }

    const int16_t today_h = this->blob_.daily_heater_hours_x10[kDailySlots - 1];
    if (today_h != kMissing || this->blob_.month_heater_days > 0) {
      const uint32_t sum_h =
          this->blob_.month_completed_heater_x10 + ((today_h != kMissing && today_h > 0) ? static_cast<uint32_t>(today_h) : 0U);
      this->blob_.monthly_heater_hours_x10[kMonthlySlots - 1] = clamp_i16_(static_cast<long>(sum_h));
    }

    const int16_t today_t = this->blob_.daily_water_temp_x10[kDailySlots - 1];
    const uint32_t t_days = static_cast<uint32_t>(this->blob_.month_temp_days) + (today_t != kMissing ? 1U : 0U);
    if (t_days > 0) {
      const int32_t t_sum = this->blob_.month_temp_sum_x10 + (today_t != kMissing ? today_t : 0);
      this->blob_.monthly_water_temp_x10[kMonthlySlots - 1] =
          clamp_i16_(std::lround(static_cast<double>(t_sum) / static_cast<double>(t_days)));
    }

    const int16_t today_p = this->blob_.daily_power_w[kDailySlots - 1];
    const uint32_t p_days = static_cast<uint32_t>(this->blob_.month_power_days) + (today_p != kMissing ? 1U : 0U);
    if (p_days > 0) {
      const int32_t p_sum = this->blob_.month_power_sum + (today_p != kMissing ? today_p : 0);
      this->blob_.monthly_power_w[kMonthlySlots - 1] =
          clamp_i16_(std::lround(static_cast<double>(p_sum) / static_cast<double>(p_days)));
    }

    const int16_t today_s = this->blob_.daily_salt_level[kDailySlots - 1];
    const uint32_t s_days = static_cast<uint32_t>(this->blob_.month_salt_days) + (today_s != kMissing ? 1U : 0U);
    if (s_days > 0) {
      const int32_t s_sum = this->blob_.month_salt_sum + (today_s != kMissing ? today_s : 0);
      this->blob_.monthly_salt_level[kMonthlySlots - 1] =
          clamp_i16_(std::lround(static_cast<double>(s_sum) / static_cast<double>(s_days)));
    }
  }

  static void shift_left_(int16_t *arr, size_t len, size_t delta) {
    if (delta == 0) return;
    if (delta >= len) {
      std::fill_n(arr, len, kMissing);
      return;
    }
    std::memmove(arr, arr + delta, (len - delta) * sizeof(int16_t));
    std::fill_n(arr + (len - delta), delta, kMissing);
  }

  static void shift_left_u16_(uint16_t *arr, size_t len, size_t delta) {
    if (delta == 0) return;
    if (delta >= len) {
      std::fill_n(arr, len, kMissingU16);
      return;
    }
    std::memmove(arr, arr + delta, (len - delta) * sizeof(uint16_t));
    std::fill_n(arr + (len - delta), delta, kMissingU16);
  }

  static int16_t clamp_i16_(long v) {
    if (v <= static_cast<long>(kMissing)) return static_cast<int16_t>(kMissing + 1);
    if (v > INT16_MAX) return INT16_MAX;
    return static_cast<int16_t>(v);
  }

  // Howard Hinnant's civil-to-days algorithm (returns days since 1970-01-01).
  static int32_t days_from_civil_(int y, unsigned m, unsigned d) {
    y -= (m <= 2);
    const int era = (y >= 0 ? y : y - 399) / 400;
    const unsigned yoe = static_cast<unsigned>(y - era * 400);
    const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return static_cast<int32_t>(era * 146097 + static_cast<int>(doe) - 719468);
  }

  template<typename T>
  static void publish_series_impl_(text_sensor::TextSensor *out, const char *prefix, const T *arr, size_t start,
                                   size_t count, T missing_sentinel, int decimals, double scale) {
    if (out == nullptr) return;
    size_t first = start;
    const size_t end = start + count;
    while (first < end && arr[first] == missing_sentinel) first++;
    if (first >= end) return;

    char buf[384];
    int pos = std::snprintf(buf, sizeof(buf), "%s", prefix);
    if (pos < 0 || static_cast<size_t>(pos) >= sizeof(buf)) return;

    for (size_t i = first; i < end; i++) {
      if (i > first) {
        if (static_cast<size_t>(pos + 1) >= sizeof(buf)) break;
        buf[pos++] = ',';
        buf[pos] = '\0';
      }
      if (arr[i] == missing_sentinel) continue;

      char val[16];
      int vlen = 0;
      if (decimals == 0) {
        vlen = std::snprintf(val, sizeof(val), "%d", static_cast<int>(arr[i]));
      } else if (decimals == 1) {
        vlen = std::snprintf(val, sizeof(val), "%.1f", static_cast<double>(arr[i]) * scale);
      } else {
        vlen = std::snprintf(val, sizeof(val), "%.2f", static_cast<double>(arr[i]) * scale);
      }
      if (vlen <= 0 || static_cast<size_t>(pos + vlen) >= sizeof(buf)) break;
      std::memcpy(buf + pos, val, static_cast<size_t>(vlen));
      pos += vlen;
      buf[pos] = '\0';
    }

    if (!out->has_state() || out->state != buf) {
      out->publish_state(buf);
    }
  }

  static void publish_series_(text_sensor::TextSensor *out, const char *prefix, const int16_t *arr, size_t start,
                              size_t count, int decimals, double scale) {
    publish_series_impl_<int16_t>(out, prefix, arr, start, count, kMissing, decimals, scale);
  }

  static void publish_series_u16_(text_sensor::TextSensor *out, const char *prefix, const uint16_t *arr, size_t start,
                                  size_t count, int decimals, double scale) {
    publish_series_impl_<uint16_t>(out, prefix, arr, start, count, kMissingU16, decimals, scale);
  }

  void publish_all_() {
    char prefix_6h[12];
    std::snprintf(prefix_6h, sizeof(prefix_6h), "%uh:", static_cast<unsigned>(this->bucket_hours_));

    char prefix_1d[24];
    char prefix_1mo[20];
    if (this->blob_.last_year > 0 && this->blob_.last_month >= 1 && this->blob_.last_day >= 1) {
      std::snprintf(prefix_1d, sizeof(prefix_1d), "1d@%04d-%02u-%02u:", static_cast<int>(this->blob_.last_year),
                    static_cast<unsigned>(this->blob_.last_month), static_cast<unsigned>(this->blob_.last_day));
      std::snprintf(prefix_1mo, sizeof(prefix_1mo), "1mo@%04d-%02u:", static_cast<int>(this->blob_.last_year),
                    static_cast<unsigned>(this->blob_.last_month));
    } else {
      std::snprintf(prefix_1d, sizeof(prefix_1d), "1d:");
      std::snprintf(prefix_1mo, sizeof(prefix_1mo), "1mo:");
    }

    const size_t start = kMaxSlots - this->slot_count_;

    // Tier 1 (14d @ bucket_hours)
    publish_series_(this->water_temp_out_, prefix_6h, this->blob_.water_temp_x10, start, this->slot_count_, 1, 0.1);
    publish_series_(this->power_out_, prefix_6h, this->blob_.power_w, start, this->slot_count_, 0, 1.0);
    publish_series_(this->salt_out_, prefix_6h, this->blob_.salt_level, start, this->slot_count_, 0, 1.0);
    publish_series_(this->free_heap_out_, prefix_6h, this->blob_.free_heap_kb, start, this->slot_count_, 0, 1.0);

    // Tier 2 (31d @ 1d)
    publish_series_(this->water_temp_daily_out_, prefix_1d, this->blob_.daily_water_temp_x10, 0, kDailySlots, 1, 0.1);
    publish_series_(this->power_daily_out_, prefix_1d, this->blob_.daily_power_w, 0, kDailySlots, 0, 1.0);
    publish_series_(this->energy_out_, prefix_1d, this->blob_.daily_energy_x100, 0, kDailySlots, 2, 0.01);
    publish_series_(this->salt_daily_out_, prefix_1d, this->blob_.daily_salt_level, 0, kDailySlots, 0, 1.0);
    publish_series_(this->heater_daily_out_, prefix_1d, this->blob_.daily_heater_hours_x10, 0, kDailySlots, 1, 0.1);

    // Tier 3 (24mo @ 1mo)
    publish_series_(this->water_temp_monthly_out_, prefix_1mo, this->blob_.monthly_water_temp_x10, 0, kMonthlySlots, 1,
                    0.1);
    publish_series_(this->power_monthly_out_, prefix_1mo, this->blob_.monthly_power_w, 0, kMonthlySlots, 0, 1.0);
    publish_series_u16_(this->energy_monthly_out_, prefix_1mo, this->blob_.monthly_energy_x10, 0, kMonthlySlots, 1,
                        0.1);
    publish_series_(this->salt_monthly_out_, prefix_1mo, this->blob_.monthly_salt_level, 0, kMonthlySlots, 0, 1.0);
    publish_series_(this->heater_monthly_out_, prefix_1mo, this->blob_.monthly_heater_hours_x10, 0, kMonthlySlots, 1,
                    0.1);
  }

  time::RealTimeClock *time_{ nullptr };
  uint8_t bucket_hours_{ 6 };
  size_t slot_count_{ kMaxSlots };

  sensor::Sensor *water_temp_src_{ nullptr };
  std::vector<sensor::Sensor *> power_srcs_;
  std::vector<sensor::Sensor *> energy_srcs_;
  sensor::Sensor *salt_src_{ nullptr };
  sensor::Sensor *free_heap_src_{ nullptr };
  sensor::Sensor *heater_runtime_src_{ nullptr };

  text_sensor::TextSensor *water_temp_out_{ nullptr };
  text_sensor::TextSensor *water_temp_daily_out_{ nullptr };
  text_sensor::TextSensor *water_temp_monthly_out_{ nullptr };
  text_sensor::TextSensor *power_out_{ nullptr };
  text_sensor::TextSensor *power_daily_out_{ nullptr };
  text_sensor::TextSensor *power_monthly_out_{ nullptr };
  text_sensor::TextSensor *energy_out_{ nullptr };
  text_sensor::TextSensor *energy_monthly_out_{ nullptr };
  text_sensor::TextSensor *salt_out_{ nullptr };
  text_sensor::TextSensor *salt_daily_out_{ nullptr };
  text_sensor::TextSensor *salt_monthly_out_{ nullptr };
  text_sensor::TextSensor *heater_daily_out_{ nullptr };
  text_sensor::TextSensor *heater_monthly_out_{ nullptr };
  text_sensor::TextSensor *free_heap_out_{ nullptr };

  ESPPreferenceObject pref_;
  HistoryBlob blob_{};

  double water_sum_{ 0.0 };
  uint32_t water_cnt_{ 0 };
  double power_sum_{ 0.0 };
  uint32_t power_cnt_{ 0 };
  double salt_sum_{ 0.0 };
  uint32_t salt_cnt_{ 0 };
  double heap_sum_kb_{ 0.0 };
  uint32_t heap_cnt_{ 0 };

  double day_water_sum_{ 0.0 };
  uint32_t day_water_cnt_{ 0 };
  double day_power_sum_{ 0.0 };
  uint32_t day_power_cnt_{ 0 };
  double day_salt_sum_{ 0.0 };
  uint32_t day_salt_cnt_{ 0 };
  float today_energy_max_kwh_{ 0.0f };
  uint32_t sample_ticks_{ 0 };
};

}  // namespace iq2020_history
}  // namespace esphome
