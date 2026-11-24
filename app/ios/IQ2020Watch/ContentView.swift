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
    .onReceive(tick) { _ in if phase == .active { store.refresh() } }
  }

  private func fmt(_ v: Double?, _ s: SpaSnapshot) -> String {
    guard let v else { return "—" }
    return s.step < 1 ? String(format: "%.1f", v) : String(format: "%.0f", v)
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
            Text("\(fmt(pendingTarget ?? s.target, s))\(s.unit)").font(.title3.weight(.semibold))
            Text(pendingTarget != nil ? "Setting…" : "Set to").font(.caption2).foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
          Button { nudge(s, 1) } label: { Image(systemName: "plus") }
            .buttonStyle(.bordered).buttonBorderShape(.circle).frame(width: 44)
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

        if let salt = s.salt {
          HStack(spacing: 4) {
            Image(systemName: "drop.fill").foregroundStyle(zoneColor(s.saltZone))
            Text("Salt \(Int(salt.rounded()))")
            if let zone = s.saltZone { Text(zone).fontWeight(.semibold).foregroundStyle(zoneColor(zone)) }
          }
          .font(.footnote)
          .padding(.top, 2)
        }

        if let error = store.error {
          Text(error).font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
        }
      }
    }
  }
}
