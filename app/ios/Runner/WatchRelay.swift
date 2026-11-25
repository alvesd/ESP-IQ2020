import Flutter
import UIKit
import WatchConnectivity

/// iPhone end of the Apple Watch link. watchOS can't open the TCP socket the ESPHome API needs,
/// so the watch app sends small requests ({"op": "snapshot" | "setTarget" | "toggle", ...})
/// over WatchConnectivity. They are answered by `lib/watch/watch_relay.dart`, which runs in its
/// own headless Flutter engine so it works while the phone app is closed or in the background.
final class WatchRelay: NSObject, WCSessionDelegate {
  static let shared = WatchRelay()

  private var engine: FlutterEngine?
  private var channel: FlutterMethodChannel?

  /// Call from didFinishLaunching: messages that wake the app are only delivered once the
  /// session is activated.
  func activate() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  private func ensureEngine() -> FlutterMethodChannel {
    if let channel { return channel }
    let engine = FlutterEngine(name: "watch_relay", project: nil, allowHeadlessExecution: true)
    engine.run(withEntrypoint: "watchRelayMain", libraryURI: "package:iq2020_mobile/watch/watch_relay.dart")
    GeneratedPluginRegistrant.register(with: engine)
    let channel = FlutterMethodChannel(name: "iq2020/watch", binaryMessenger: engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "push", let snapshot = call.arguments {
        // Latest state for an open watch app; only the newest context is kept.
        try? WCSession.default.updateApplicationContext(["snapshot": WatchRelay.plist(snapshot)])
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    self.engine = engine
    self.channel = channel
    return channel
  }

  /// Forwards one watch request to Dart. The first request after launch can arrive before the
  /// Dart handler is registered, so "not implemented" is retried for a few seconds.
  private func forward(_ message: [String: Any], attempt: Int = 0, reply: @escaping ([String: Any]) -> Void) {
    ensureEngine().invokeMethod("request", arguments: message) { result in
      if (result as? NSObject) === FlutterMethodNotImplemented, attempt < 40 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          self.forward(message, attempt: attempt + 1, reply: reply)
        }
        return
      }
      if let error = result as? FlutterError {
        reply(["error": error.message ?? error.code])
      } else if let map = result as? [String: Any] {
        reply(WatchRelay.plist(map) as? [String: Any] ?? [:])
      } else {
        reply(["error": "iPhone relay is not ready"])
      }
    }
  }

  /// WatchConnectivity only carries property-list values; drop nils (NSNull) from Dart maps.
  static func plist(_ value: Any) -> Any {
    switch value {
    case let map as [String: Any]:
      return map.compactMapValues { $0 is NSNull ? nil : plist($0) }
    case let list as [Any]:
      return list.filter { !($0 is NSNull) }.map(plist)
    default:
      return value
    }
  }

  // MARK: WCSessionDelegate

  func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    DispatchQueue.main.async {
      // A woken app gets a short background window; ask for the time a connect needs.
      var task = UIBackgroundTaskIdentifier.invalid
      task = UIApplication.shared.beginBackgroundTask(withName: "watch-relay") {
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
      }
      var replied = false
      func finish(_ response: [String: Any]) {
        guard !replied else { return }
        replied = true
        replyHandler(response)
        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
      }
      // Never leave the watch spinning if the relay engine can't start or the spa hangs.
      DispatchQueue.main.asyncAfter(deadline: .now() + 20) { finish(["error": "iPhone relay timed out"]) }
      self.forward(message, reply: finish)
    }
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
  func sessionDidBecomeInactive(_ session: WCSession) {}
  func sessionDidDeactivate(_ session: WCSession) { session.activate() } // e.g. after switching watches
}
