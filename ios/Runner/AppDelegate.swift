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
    GMSServices.provideAPIKey("AIzaSyBZQ9l8a60_qH7fWQZJA0n1X3fhDZrnrnw")

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}