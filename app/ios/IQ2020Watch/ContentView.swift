import SwiftUI

@main
struct IQ2020WatchApp: App {
  @StateObject private var store = WatchStore()

  var body: some Scene {
    WindowGroup {
      ContentView().environmentObject(store)
    }
  }
}

private let aqua = Color(red: 0.31, green: 0.89, blue: 0.92)
private let amber = Color(red: 1.0, green: 0.72, blue: 0.42)

struct ContentView: View {
  @EnvironmentObject var store: WatchStore
  @Environment(\.scenePhase) private var phase
  @State private var pendingTarget: Double?
  @State private var sendTask: Task<Void, Never>?
  @State private var etaSessionTarget: Double?
  @State private var etaSamples: [(time: Date, temp: Double)] = []
  @State private var now = Date()

  // While the app is on screen, refresh now and then; the iPhone also pushes changes.
  private let tick = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

  var body: some View {
    Group {
      if let s = store.snapshot {
        spa(s)
      } else if let error = store.error {
        VStack(spacing: 8) {
          Image(systemName: "iphone.slash").font(.title2).foregroundStyle(.secondary)
          Text(error).font(.footnote).multilineTextAlignment(.center)
          Button("Retry") { store.refresh() }
        }
      } else {
        ProgressView("Connecting…")
      }
    }
    .onChange(of: phase) { _, p in if p == .active { store.refresh() } }
    .onChange(of: store.snapshot) { _, s in updateEtaSamples(s) }
    .onReceive(tick) { date in
      now = date
      if phase == .active { store.refresh() }
    }
  }

  private func fmt(_ v: Double?, _ s: SpaSnapshot) -> String {
    guard let v else { return "—" }
    return s.step < 1 ? String(format: "%.1f", v) : String(format: "%.0f", v)
  }

  private func fmtTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }

  private func presetTol(_ s: SpaSnapshot) -> Double {
    s.unit == "°F" ? 0.45 : 0.2
  }

  private func updateEtaSamples(_ s: SpaSnapshot?) {
    guard let s, let current = s.current else { return }
    let displayedTarget = pendingTarget ?? s.target
    let active = displayedTarget != nil && abs(displayedTarget! - s.heatUpTemp) < presetTol(s) && current < s.heatUpTemp - 0.05
    guard active else {
      etaSessionTarget = nil
      etaSamples.removeAll()
      return
    }
    let timestamp = Date()
    if etaSamples.isEmpty || etaSessionTarget == nil || abs(etaSessionTarget! - s.heatUpTemp) > 0.25 {
      etaSessionTarget = s.heatUpTemp
      etaSamples = [(timestamp, current)]
      return
    }
    let threshold = s.unit == "°F" ? 0.5 : 0.25
    if let last = etaSamples.last {
      if current < last.temp - threshold {
        etaSamples = [(timestamp, current)]
      } else if current >= last.temp + threshold {
        etaSamples.append((timestamp, current))
      }
    }
  }

  private func etaInfo(_ s: SpaSnapshot) -> (readyAt: Date?, calibrated: Bool) {
    guard let current = s.current, current < s.heatUpTemp - 0.05 else { return (nil, false) }
    if pendingTarget == nil, let sec = s.readyEtaSeconds, sec > 0 {
      return (now.addingTimeInterval(Double(sec)), s.readyEtaCalibrated)
    }
    let defaultRate = s.unit == "°F" ? 5.0 : 5.0 * 5.0 / 9.0
    let minRate = s.unit == "°F" ? 1.0 : 1.0 * 5.0 / 9.0
    let maxRate = s.unit == "°F" ? 15.0 : 15.0 * 5.0 / 9.0
    let rate: Double
    let calibrated: Bool
    if etaSamples.count < 2 {
      rate = defaultRate
      calibrated = false
    } else if etaSamples.count == 2 {
      let dt = max(1.0 / 60.0, etaSamples[1].time.timeIntervalSince(etaSamples[0].time) / 3600.0)
      let obs = Swift.min(Swift.max((etaSamples[1].temp - etaSamples[0].temp) / dt, minRate), maxRate)
      rate = 0.5 * obs + 0.5 * defaultRate
      calibrated = true
    } else {
      let firstCross = etaSamples[1]
      let latest = etaSamples.last!
      let dt = max(1.0 / 60.0, latest.time.timeIntervalSince(firstCross.time) / 3600.0)
      rate = Swift.min(Swift.max((latest.temp - firstCross.temp) / dt, minRate), maxRate)
      calibrated = true
    }
    let seconds = ((s.heatUpTemp - current) / rate) * 3600.0
    return (now.addingTimeInterval(seconds), calibrated)
  }

  private func heater(_ s: SpaSnapshot) -> (String, Color) {
    switch s.heater {
    case "heating": return ("Heating", Color(red: 1, green: 0.54, blue: 0.3))
    case "cooling": return ("Cooling", Color(red: 0.31, green: 0.76, blue: 0.97))
    case "idle": return ("Holding", aqua)
    default: return ("Heater off", .secondary)
    }
  }

  private func zoneColor(_ zone: String?) -> Color {
    switch zone {
    case "Good": return Color(red: 0.19, green: 0.64, blue: 0.42)
    case "Low", "High": return Color(red: 0.96, green: 0.72, blue: 0.24)
    default: return Color(red: 0.9, green: 0.28, blue: 0.3)
    }
  }

  private func setPresetTarget(_ value: Double, isHeatUp: Bool, current: Double?) {
    sendTask?.cancel()
    pendingTarget = value
    if isHeatUp, let current {
      etaSessionTarget = value
      etaSamples = [(Date(), current)]
    } else {
      etaSessionTarget = nil
      etaSamples.removeAll()
    }
    store.setTarget(value)
    sendTask = Task {
      try? await Task.sleep(for: .seconds(3))
      if !Task.isCancelled { pendingTarget = nil }
    }
  }

  /// One target command after the taps stop, like the phone app and the spa remote.
  private func nudge(_ s: SpaSnapshot, _ steps: Int) {
    let next = s.nudged(from: pendingTarget, steps: steps)
    pendingTarget = next
    sendTask?.cancel()
    sendTask = Task {
      try? await Task.sleep(for: .milliseconds(700))
      guard !Task.isCancelled else { return }
      store.setTarget(next)
      try? await Task.sleep(for: .seconds(3))
      if !Task.isCancelled { pendingTarget = nil }
    }
  }

  @ViewBuilder
  private func spa(_ s: SpaSnapshot) -> some View {
    let (heaterText, heaterColor) = heater(s)
    let canControl = s.online && s.hasThermostat
    let effectiveTarget = pendingTarget ?? s.target
    let heatUpActive = effectiveTarget != nil && abs(effectiveTarget! - s.heatUpTemp) < presetTol(s)
    let heatUpReached = heatUpActive && (s.current ?? -999) >= s.heatUpTemp - 0.05
    let vacationActive = effectiveTarget != nil && abs(effectiveTarget! - s.vacationTemp) < presetTol(s)
    let eta = heatUpActive && !heatUpReached ? etaInfo(s) : (readyAt: nil, calibrated: false)

    ScrollView {
      VStack(spacing: 6) {
        HStack(spacing: 4) {
          Circle().fill(s.online ? .green : .gray).frame(width: 6, height: 6)
          Text(s.name).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
          if store.loading { ProgressView().scaleEffect(0.5).frame(width: 12, height: 12) }
        }
        Text("\(fmt(s.current, s))\(s.unit)")
          .font(.system(size: 40, weight: .light, design: .rounded))
        Text(heaterText).font(.footnote).foregroundStyle(heaterColor)

        HStack {
          Button { nudge(s, -1) } label: { Image(systemName: "minus") }
            .buttonStyle(.bordered).buttonBorderShape(.circle).frame(width: 44)
            .disabled(!canControl)
          Spacer(minLength: 0)
          VStack(spacing: 0) {
            Text("\(fmt(effectiveTarget, s))\(s.unit)").font(.title3.weight(.semibold))
            Text(pendingTarget != nil ? "Setting…" : "Set to").font(.caption2).foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
          Button { nudge(s, 1) } label: { Image(systemName: "plus") }
            .buttonStyle(.bordered).buttonBorderShape(.circle).frame(width: 44)
            .disabled(!canControl)
        }

        HStack(spacing: 6) {
          Button { setPresetTarget(s.heatUpTemp, isHeatUp: true, current: s.current) } label: {
            HStack(spacing: 4) {
              Image(systemName: heatUpReached ? "checkmark.circle.fill" : "flame.fill")
                .font(.caption2)
                .foregroundStyle(heatUpReached ? .green : (heatUpActive ? .orange : .white))
              VStack(alignment: .leading, spacing: 0) {
                Text(heatUpReached ? "Ready" : (heatUpActive ? (eta.calibrated ? "Ready by" : "Est. Ready") : "Heat Up"))
                  .font(.caption2.weight(.semibold))
                  .lineLimit(1)
                Text(heatUpReached
                     ? "At \(fmt(s.heatUpTemp, s))\(s.unit)"
                     : (eta.readyAt != nil ? fmtTime(eta.readyAt!) : "\(fmt(s.heatUpTemp, s))\(s.unit)"))
                  .font(.system(size: 10))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.bordered)
          .tint(heatUpActive ? (heatUpReached ? .green : .orange) : nil)
          .disabled(!canControl)

          Button { setPresetTarget(s.vacationTemp, isHeatUp: false, current: s.current) } label: {
            HStack(spacing: 4) {
              Image(systemName: "airplane")
                .font(.caption2)
                .foregroundStyle(vacationActive ? aqua : .white)
              VStack(alignment: .leading, spacing: 0) {
                Text("Vacation")
                  .font(.caption2.weight(.semibold))
                  .lineLimit(1)
                Text(vacationActive ? "On · \(fmt(s.vacationTemp, s))\(s.unit)" : "\(fmt(s.vacationTemp, s))\(s.unit)")
                  .font(.system(size: 10))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.bordered)
          .tint(vacationActive ? aqua : nil)
          .disabled(!canControl)
        }

        ForEach(s.toggles) { t in
          let accent = t.kind == "fan" ? aqua : amber
          Button { store.toggle(t) } label: {
            HStack {
              Image(systemName: t.kind == "fan" ? "wind" : "lightbulb").foregroundStyle(t.on ? accent : .secondary)
              Text(t.name).lineLimit(1)
              Spacer()
              Text(t.on ? "On" : "Off").font(.footnote).foregroundStyle(t.on ? accent : .secondary)
            }
          }
          .tint(t.on ? accent : nil)
          .disabled(!s.online)
        }

        if s.salt != nil || s.saltPower != nil || s.saltBoost {
          VStack(spacing: 3) {
            if s.salt != nil || s.saltPower != nil {
              HStack(spacing: 4) {
                if let salt = s.salt {
                  Image(systemName: "drop.fill").foregroundStyle(zoneColor(s.saltZone))
                  Text("Salt \(Int(salt.rounded()))")
                  if let zone = s.saltZone { Text(zone).fontWeight(.semibold).foregroundStyle(zoneColor(zone)) }
                }
                if s.salt != nil && s.saltPower != nil {
                  Text("·").foregroundStyle(.secondary)
                }
                if let power = s.saltPower {
                  Text("Pwr \(power)").foregroundStyle(.secondary)
                }
              }
              .font(.footnote)
            }
            if s.saltBoost {
              HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                Text("Boost On")
              }
              .font(.caption2.weight(.semibold))
              .foregroundStyle(aqua)
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(aqua.opacity(0.18), in: Capsule())
            }
          }
          .padding(.top, 2)
        }

        if let error = store.error {
          Text(error).font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
        }
      }
    }
  }
}
