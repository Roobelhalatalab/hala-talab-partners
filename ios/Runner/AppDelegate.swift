import Flutter
import UIKit
import UserNotifications
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let iosPushChannelName = "com.halatalab.partners/ios_push"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Keep Flutter/Firebase's normal lifecycle. Firebase is initialized from Dart.
    // The permission/APNs registration call is invoked only AFTER Dart finishes
    // Firebase.initializeApp(), so the APNs token cannot race Firebase startup.
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let iosPushChannel = FlutterMethodChannel(
      name: Self.iosPushChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    iosPushChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "requestPermissionAndRegister" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.requestPermissionAndRegister(result: result)
    }
  }

  private func requestPermissionAndRegister(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound]
    ) { granted, error in
      if let error = error {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "ios-notification-permission",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
        return
      }

      DispatchQueue.main.async {
        if granted {
          UIApplication.shared.registerForRemoteNotifications()
        }
        result(granted)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Firebase has already been initialized from Dart before registration is
    // requested. Forward the APNs token explicitly and still preserve Flutter's
    // normal AppDelegate callback chain.
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
}
