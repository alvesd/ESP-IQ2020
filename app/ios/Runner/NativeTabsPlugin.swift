import Flutter
import UIKit

/// Hosts the Flutter UI inside a native `UITabBarController` so the spa screen's tabs use the
/// system tab bar. On iPhone Duo the system places these tabs in its own bar along the
/// trailing edge; elsewhere they appear wherever iOS puts tab bars (bottom bar, sidebar).
///
/// Channel `iq2020/native_tabs`:
///   Flutter -> iOS  `setTabs` {tabs: [{id, title, symbol}], selected: id}  show/refresh tabs
///                   `select`  id                                          change selection
///                   `hide`                                                hide the tab bar
///   iOS -> Flutter  `selected` id                                         user picked a tab
///
/// There is one FlutterViewController. Every tab gets an empty container, and the Flutter view
/// moves into whichever container is selected. Requires iOS 18 (UITab); on older versions the
/// plugin isn't registered and Flutter draws its own navigation.
@available(iOS 18.0, *)
final class NativeTabsPlugin: NSObject, UITabBarControllerDelegate {
  private let channel: FlutterMethodChannel
  private weak var registrar: FlutterPluginRegistrar?
  private var tabBarController: UITabBarController?
  private weak var flutterViewController: UIViewController?
  private var containers: [String: UIViewController] = [:]
  private var tabIDs: [String] = []

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(name: "iq2020/native_tabs", binaryMessenger: registrar.messenger())
    self.registrar = registrar
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result) ?? result(FlutterMethodNotImplemented)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setTabs":
      guard let args = call.arguments as? [String: Any],
            let specs = args["tabs"] as? [[String: String]] else {
        result(FlutterError(code: "bad_args", message: "setTabs needs tabs", details: nil))
        return
      }
      result(setTabs(specs, selected: args["selected"] as? String))
    case "select":
      if let id = call.arguments as? String { select(id) }
      result(nil)
    case "hide":
      tabBarController?.setTabBarHidden(true, animated: true)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Returns false when the Flutter view isn't in a window yet; Flutter then keeps its own bar.
  private func setTabs(_ specs: [[String: String]], selected: String?) -> Bool {
    guard let tbc = ensureTabBarController() else { return false }
    let ids = specs.compactMap { $0["id"] }
    if ids != tabIDs {
      tabIDs = ids
      // Fresh containers every time: a view controller already owned by a previous UITab
      // can't be handed to a new one (UIKit asserts).
      containers = [:]
      tbc.tabs = specs.compactMap { spec in
        guard let id = spec["id"] else { return nil }
        let container = UIViewController()
        containers[id] = container
        return UITab(title: spec["title"] ?? id,
                     image: Self.image(named: spec["symbol"] ?? "circle"),
                     identifier: id) { _ in container }
      }
    }
    tbc.setTabBarHidden(false, animated: true)
    select(selected ?? ids.first ?? "")
    // On the first swap the selected container isn't in the window yet, so the appearance
    // notice in embedFlutter is skipped. Send it once layout has put the container on screen.
    DispatchQueue.main.async { [weak self] in self?.resumeFlutterIfVisible() }
    return true
  }

  private func resumeFlutterIfVisible() {
    guard let flutter = flutterViewController, flutter.view.window != nil else { return }
    flutter.beginAppearanceTransition(true, animated: false)
    flutter.endAppearanceTransition()
  }

  /// SF Symbol if one exists, otherwise a template image from Assets.xcassets (e.g. the custom
  /// "saltshaker" icon, since SF Symbols has no salt shaker).
  private static func image(named name: String) -> UIImage? {
    UIImage(systemName: name) ?? UIImage(named: name)?.withRenderingMode(.alwaysTemplate)
  }

  private func select(_ id: String) {
    guard let tbc = tabBarController, let tab = tbc.tabs.first(where: { $0.identifier == id }) else { return }
    if tbc.selectedTab !== tab { tbc.selectedTab = tab }
    embedFlutter(in: tab.viewController)
  }

  /// Swaps the window's root from the bare FlutterViewController to a tab bar controller the
  /// first time tabs are requested. Uses the registrar's own view controller and its window,
  /// never global app/scene state.
  private func ensureTabBarController() -> UITabBarController? {
    if let tbc = tabBarController { return tbc }
    guard let flutter = registrar?.viewController, let window = flutter.view.window else { return nil }
    flutterViewController = flutter
    let tbc = UITabBarController()
    tbc.delegate = self
    // Let the system choose: the Duo's native bar, a bottom tab bar, or a sidebar.
    if #available(iOS 27.0, *) {
      tbc.sidebar.preferredPlacement = .automatic
    }
    tabBarController = tbc
    window.rootViewController = tbc
    return tbc
  }

  private func embedFlutter(in container: UIViewController?) {
    guard let container, let flutter = flutterViewController, flutter.parent !== container else { return }
    flutter.willMove(toParent: nil)
    flutter.view.removeFromSuperview()
    flutter.removeFromParent()
    container.addChild(flutter)
    flutter.view.frame = container.view.bounds
    flutter.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.view.addSubview(flutter.view)
    flutter.didMove(toParent: container)
    // Moving the view (and swapping the window's root) sends Flutter "disappeared", which pauses
    // rendering and app lifecycle. Tell it it's visible again so frames and the app resume.
    if container.view.window != nil {
      flutter.beginAppearanceTransition(true, animated: false)
      flutter.endAppearanceTransition()
    }
  }

  // MARK: UITabBarControllerDelegate

  func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
    embedFlutter(in: selectedTab.viewController)
    channel.invokeMethod("selected", arguments: selectedTab.identifier)
  }
}
