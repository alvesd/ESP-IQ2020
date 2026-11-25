import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// NativeTabsPlugin on iOS 18+ (typed as AnyObject so the property exists on older iOS).
  private var nativeTabs: AnyObject?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WatchRelay.shared.activate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if #available(iOS 18.0, *), let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeTabsPlugin") {
      nativeTabs = NativeTabsPlugin(registrar: registrar)
    }
  }
}
