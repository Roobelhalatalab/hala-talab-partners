import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Keep Flutter/Firebase's normal lifecycle. Do not manually configure
    // Firebase or replace FlutterAppDelegate's notification delegate.
    let launched = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    // Build 16 iOS-only fallback:
    // Ask iOS itself for notification authorization independently of Firebase
    // startup. If authorization already has a decision, iOS returns it without
    // showing a second prompt. If allowed, explicitly register with APNs.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
      UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .badge, .sound]
      ) { granted, error in
        if let error = error {
          print("Hala Talab Partners notification permission error: \(error)")
        }
        if granted {
          DispatchQueue.main.async {
            application.registerForRemoteNotifications()
          }
        }
      }
    }

    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
