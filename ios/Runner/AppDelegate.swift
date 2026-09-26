import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Build 14 iOS-only hardening.
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    UNUserNotificationCenter.current().delegate = self

    let launched = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    // Explicit APNs registration for iPhone/iPad.
    application.registerForRemoteNotifications()

    return launched
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Explicitly associate the APNs token with Firebase Messaging.
    Messaging.messaging().apnsToken = deviceToken
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("Hala Talab Partners APNs registration failed: \(error)")
    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error
    )
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
