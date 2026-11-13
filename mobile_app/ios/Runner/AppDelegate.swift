import Flutter
import AppTrackingTransparency
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let trackingChannel = FlutterMethodChannel(
      name: "com.jobfriends.mobile/app_tracking_transparency",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    trackingChannel.setMethodCallHandler { call, result in
      guard call.method == "requestAuthorization" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard #available(iOS 14.5, *) else {
        result(0)
        return
      }

      DispatchQueue.main.async {
        ATTrackingManager.requestTrackingAuthorization { status in
          result(status.rawValue)
        }
      }
    }
  }
}
