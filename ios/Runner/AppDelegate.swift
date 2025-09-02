import UIKit
import Flutter
import GoogleMaps // Important d'importer GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // INSEREZ VOTRE CLÉ API GOOGLE MAPS ICI
    GMSServices.provideAPIKey("AIzaSyA-506MjOYcDfPPNgMwWXO2UeVAiVnV6j0")

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}