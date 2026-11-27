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

/// Fixed-size, zero-heap-allocation 14-day metrics history persisted to ESP32 NVS.
/// Supports configurable bucket_hours (6 = 56 slots, 12 = 28 slots, 24 = 14 slots)
/// plus 14 local civil-day buckets for daily energy totals.
class IQ2020History : public PollingComponent {
 public:
  static constexpr size_t kMaxSlots = 56;
  static constexpr size_t kDailySlots = 14;
  static constexpr int16_t kMissing = INT16_MIN;
  static constexpr uint32_t kMagic = 0x49514831UL;  // 'IQH1'
  static constexpr uint16_t kVersion = 1;

  struct HistoryBlob {
    uint32_t magic;
    uint16_t version;
    uint8_t bucket_hours;
    uint8_t reserved;
    uint32_t last_bucket_slot;
    int32_t last_day_slot;
    int16_t water_temp_x10[kMaxSlots];
    int16_t power_w[kMaxSlots];
    int16_t salt_level[kMaxSlots];
    int16_t free_heap_kb[kMaxSlots];
    int16_t daily_energy_x100[kDailySlots];
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

  void set_water_temp_history(text_sensor::TextSensor *ts) { this->water_temp_out_ = ts; }
  void set_power_history(text_sensor::TextSensor *ts) { this->power_out_ = ts; }
  void set_energy_history(text_sensor::TextSensor *ts) { this->energy_out_ = ts; }
  void set_salt_history(text_sensor::TextSensor *ts) { this->salt_out_ = ts; }
  void set_free_heap_history(text_sensor::TextSensor *ts) { this->free_heap_out_ = ts; }

  float get_setup_priority() const override { return setup_priority::LATE; }

  void setup() override {
    this->pref_ = global_preferences->make_preference<HistoryBlob>(kMagic);
    if (!this->pref_.load(&this->blob_) || this->blob_.magic != kMagic || this->blob_.version != kVersion ||
        this->blob_.bucket_hours != this->bucket_hours_) {
      this->reset_blob_();
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
          const size_t delta =
              static_cast<size_t>(std::min<int32_t>(cur_day - this->blob_.last_day_slot, kDailySlots));
          shift_left_(this->blob_.daily_energy_x100, kDailySlots, delta);
          this->today_energy_max_kwh_ = 0.0f;
          this->blob_.last_day_slot = cur_day;
          rolled_over = true;
        }
      }
    }

    bool got_first_sample = false;

    if (this->water_temp_src_ != nullptr && this->water_temp_src_->has_state() &&
        !std::isnan(this->water_temp_src_->state)) {
      this->water_sum_ += this->water_temp_src_->state;
      this->water_cnt_++;
      if (this->blob_.water_temp_x10[kMaxSlots - 1] == kMissing) got_first_sample = true;
      this->blob_.water_temp_x10[kMaxSlots - 1] =
          clamp_i16_(std::lround((this->water_sum_ / this->water_cnt_) * 10.0));
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
      }
    }

    if (this->salt_src_ != nullptr && this->salt_src_->has_state() && !std::isnan(this->salt_src_->state)) {
      this->salt_sum_ += this->salt_src_->state;
      this->salt_cnt_++;
      if (this->blob_.salt_level[kMaxSlots - 1] == kMissing) got_first_sample = true;
      this->blob_.salt_level[kMaxSlots - 1] = clamp_i16_(std::lround(this->salt_sum_ / this->salt_cnt_));
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
    std::fill_n(this->blob_.water_temp_x10, kMaxSlots, kMissing);
    std::fill_n(this->blob_.power_w, kMaxSlots, kMissing);
    std::fill_n(this->blob_.salt_level, kMaxSlots, kMissing);
    std::fill_n(this->blob_.free_heap_kb, kMaxSlots, kMissing);
    std::fill_n(this->blob_.daily_energy_x100, kDailySlots, kMissing);
    this->reset_bucket_accumulators_();
    this->today_energy_max_kwh_ = 0.0f;
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

  static void shift_left_(int16_t *arr, size_t len, size_t delta) {
    if (delta == 0) return;
    if (delta >= len) {
      std::fill_n(arr, len, kMissing);
      return;
    }
    std::memmove(arr, arr + delta, (len - delta) * sizeof(int16_t));
    std::fill_n(arr + (len - delta), delta, kMissing);
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

  static void publish_series_(text_sensor::TextSensor *out, const char *prefix, const int16_t *arr, size_t start,
                              size_t count, int decimals, float scale) {
    if (out == nullptr) return;
    size_t first = start;
    const size_t end = start + count;
    while (first < end && arr[first] == kMissing) first++;
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
      if (arr[i] == kMissing) continue;

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

  void publish_all_() {
    char prefix[12];
    std::snprintf(prefix, sizeof(prefix), "%uh:", static_cast<unsigned>(this->bucket_hours_));
    const size_t start = kMaxSlots - this->slot_count_;
    publish_series_(this->water_temp_out_, prefix, this->blob_.water_temp_x10, start, this->slot_count_, 1, 0.1f);
    publish_series_(this->power_out_, prefix, this->blob_.power_w, start, this->slot_count_, 0, 1.0f);
    publish_series_(this->energy_out_, "1d:", this->blob_.daily_energy_x100, 0, kDailySlots, 2, 0.01f);
    publish_series_(this->salt_out_, prefix, this->blob_.salt_level, start, this->slot_count_, 0, 1.0f);
    publish_series_(this->free_heap_out_, prefix, this->blob_.free_heap_kb, start, this->slot_count_, 0, 1.0f);
  }

  time::RealTimeClock *time_{ nullptr };
  uint8_t bucket_hours_{ 6 };
  size_t slot_count_{ kMaxSlots };

  sensor::Sensor *water_temp_src_{ nullptr };
  std::vector<sensor::Sensor *> power_srcs_;
  std::vector<sensor::Sensor *> energy_srcs_;
  sensor::Sensor *salt_src_{ nullptr };
  sensor::Sensor *free_heap_src_{ nullptr };

  text_sensor::TextSensor *water_temp_out_{ nullptr };
  text_sensor::TextSensor *power_out_{ nullptr };
  text_sensor::TextSensor *energy_out_{ nullptr };
  text_sensor::TextSensor *salt_out_{ nullptr };
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
  float today_energy_max_kwh_{ 0.0f };
  uint32_t sample_ticks_{ 0 };
};

}  // namespace iq2020_history
}  // namespace esphome
