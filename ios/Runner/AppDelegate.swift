import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let pushChannelName = "com.halatalab.partners/push_native"
  private var pushChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Keep Flutter/Firebase's standard lifecycle and method swizzling.
    // Firebase is initialized from Dart.
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // The only native responsibility we keep is the Apple-required call to
    // register with APNs *after* Dart has obtained notification permission.
    // Permission itself is requested from firebase_messaging in Dart.
    let channel = FlutterMethodChannel(
      name: Self.pushChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    pushChannel = channel

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "registerForRemoteNotifications":
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
          result(true)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
