import Foundation
import WatchConnectivity

/// What the watch shows; mirrors `SpaSnapshot.toMap()` in lib/watch/spa_snapshot.dart.
struct SpaSnapshot: Equatable {
  struct Toggle: Equatable, Identifiable {
    let key: Int
    let name: String
    let kind: String // "fan" or "light"
    let on: Bool
    var id: Int { key }
  }

  let name: String
  let online: Bool
  let unit: String
  let hasThermostat: Bool
  let current: Double?
  let target: Double?
  let min: Double
  let max: Double
  let step: Double
  let heatUpTemp: Double
  let vacationTemp: Double
  let heater: String
  let toggles: [Toggle]
  let salt: Double?
  let saltZone: String?
  let saltPower: Int?
  let saltBoost: Bool
  let readyEtaSeconds: Int?
  let readyEtaCalibrated: Bool
  let heatingRate: Double?
  let tempHistory: [Double]
  let saltHistory: [Double]
  let dailyEnergyHistory: [Double]
  let monthlyEnergyHistory: [Double]
  let monthlyEnergyEndMonth: String?

  init?(_ m: [String: Any]) {
    guard let name = m["name"] as? String else { return nil }
    func num(_ k: String) -> Double? { (m[k] as? NSNumber)?.doubleValue }
    self.name = name
    online = m["online"] as? Bool ?? false
    unit = m["unit"] as? String ?? "°F"
    hasThermostat = m["climateKey"] != nil
    current = num("current")
    target = num("target")
    min = num("min") ?? 79
    max = num("max") ?? 104
    step = num("step") ?? 1
    heatUpTemp = num("heatUpTemp") ?? (unit == "°F" ? 102 : 39)
    vacationTemp = num("vacationTemp") ?? (unit == "°F" ? 85 : 29.5)
    heater = m["heater"] as? String ?? "off"
    toggles = (m["toggles"] as? [[String: Any]] ?? []).compactMap { t in
      guard let key = (t["key"] as? NSNumber)?.intValue, let name = t["name"] as? String else { return nil }
      return Toggle(key: key, name: name, kind: t["kind"] as? String ?? "light", on: t["on"] as? Bool ?? false)
    }
    salt = num("salt")
    saltZone = m["saltZone"] as? String
    saltPower = (m["saltPower"] as? NSNumber)?.intValue
    saltBoost = m["saltBoost"] as? Bool ?? false
    readyEtaSeconds = (m["readyEtaSeconds"] as? NSNumber)?.intValue
    readyEtaCalibrated = m["readyEtaCalibrated"] as? Bool ?? false
    heatingRate = num("heatingRate")
    tempHistory = (m["tempHistory"] as? [NSNumber] ?? []).map { $0.doubleValue }
    saltHistory = (m["saltHistory"] as? [NSNumber] ?? []).map { $0.doubleValue }
    dailyEnergyHistory = (m["dailyEnergyHistory"] as? [NSNumber] ?? []).map { $0.doubleValue }
    monthlyEnergyHistory = (m["monthlyEnergyHistory"] as? [NSNumber] ?? []).map { $0.doubleValue }
    monthlyEnergyEndMonth = m["monthlyEnergyEndMonth"] as? String
  }

  /// Target moved by `steps`, snapped to the step and clamped to the range.
  func nudged(from value: Double?, steps: Int) -> Double {
    let base = value ?? target ?? current ?? min
    let next = ((base + Double(steps) * step) / step).rounded() * step
    return Swift.min(Swift.max(next, min), max)
  }
}

/// Talks to the iPhone, which holds the encrypted ESPHome connection (WatchRelay.swift).
@MainActor
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
  @Published var snapshot: SpaSnapshot?
  @Published var error: String?
  @Published var loading = false

  override init() {
    super.init()
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }

  func refresh() { send(["op": "snapshot"]) }

  func setTarget(_ value: Double) { send(["op": "setTarget", "value": value]) }

  func toggle(_ t: SpaSnapshot.Toggle) {
    send(["op": "toggle", "key": t.key, "kind": t.kind, "on": !t.on])
  }

  private func send(_ message: [String: Any]) {
    let session = WCSession.default
    guard session.activationState == .activated else {
      error = "Connecting to iPhone…"
      return
    }
    loading = true
    session.sendMessage(message, replyHandler: { reply in
      Task { @MainActor in self.apply(reply) }
    }, errorHandler: { err in
      Task { @MainActor in
        self.loading = false
        self.error = (err as NSError).code == WCError.notReachable.rawValue
          ? "iPhone not reachable. Keep it nearby."
          : err.localizedDescription
      }
    })
  }

  private func apply(_ reply: [String: Any]) {
    loading = false
    if let message = reply["error"] as? String {
      error = message
    } else if let m = reply["snapshot"] as? [String: Any], let s = SpaSnapshot(m) {
      snapshot = s
      error = nil
    }
  }

  // MARK: WCSessionDelegate

  nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
    Task { @MainActor in
      if state == .activated { self.refresh() }
      if let context = session.receivedApplicationContext["snapshot"] as? [String: Any], self.snapshot == nil {
        self.snapshot = SpaSnapshot(context)
      }
    }
  }

  /// The iPhone often becomes reachable just after launch; ask again then.
  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    guard session.isReachable else { return }
    Task { @MainActor in self.refresh() }
  }

  /// Pushed by the iPhone while its relay connection is open.
  nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    guard let m = context["snapshot"] as? [String: Any], let s = SpaSnapshot(m) else { return }
    Task { @MainActor in
      self.snapshot = s
      self.error = nil
    }
  }
}
