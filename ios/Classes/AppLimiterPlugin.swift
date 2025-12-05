import Flutter
import UIKit
import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

/// Global variable to store the current method being called
/// Used for communication between different UI components
var globalMethodCall = ""

/// AppLimiterPlugin: Main plugin class that handles the communication between Flutter and iOS
/// Implements FlutterPlugin protocol to handle method channel calls
/// This plugin provides functionality for:
/// - Getting platform version
/// - Blocking/unblocking apps using Screen Time API
/// - Handling permissions for Screen Time functionality
public class AppLimiterPlugin: NSObject, FlutterPlugin {
    /// Registers the plugin with the Flutter engine
    /// Sets up the method channel for communication
    /// - Parameter registrar: The plugin registrar used to set up the channel
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "app_limiter", binaryMessenger: registrar.messenger())
        let instance = AppLimiterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    /// Handles method calls from Flutter
    /// Supported methods:
    /// - getPlatformVersion: Returns the current iOS version
    /// - blockApp: Initiates the app blocking process (iOS 16+ only)
    /// - requestPermission: Requests Screen Time permissions (iOS 16+ only)
    /// - Parameter call: The method call from Flutter
    /// - Parameter result: The callback to send the result back to Flutter
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)

        case "blockApp":
            if #available(iOS 16.0, *) {
                handleAppSelection(method: "selectAppsToDiscourage", result: result)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "iOS 16+ required", details: nil))
            }
        
        case "requestPermission":
        if #available(iOS 16.0, *) {
            requestPermission(result: result)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "iOS 16+ required", details: nil))
            }

        case "blockWebsites":
            if #available(iOS 16.0, *) {
                if let domains = call.arguments as? [String] {
                    MyModel.shared.setWebDomainRestrictions(domains: domains)
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected list of domains", details: nil))
                }
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "iOS 16+ required", details: nil))
            }

        case "unblockWebsites":
            if #available(iOS 16.0, *) {
                MyModel.shared.setWebDomainRestrictions(domains: [])
                result(nil)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "iOS 16+ required", details: nil))
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @available(iOS 16.0, *)
    private func handleAppSelection(method: String, result: @escaping FlutterResult) {
        let status = AuthorizationCenter.shared.authorizationStatus

        if status == .approved {
            presentContentView(method: method)
            result(nil)
        } else {
            Task {
                do {
                    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                    let newStatus = AuthorizationCenter.shared.authorizationStatus
                    if newStatus == .approved {
                        presentContentView(method: method)
                        result(nil)
                    } else {
                        result(FlutterError(code: "PERMISSION_DENIED", message: "User denied permission", details: nil))
                    }
                } catch {
                    result(FlutterError(code: "AUTH_ERROR", message: "Failed to request authorization", details: error.localizedDescription))
                }
            }
        }
    }

    // New method to request permission separately
    @available(iOS 16.0, *)
    private func requestPermission(result: @escaping FlutterResult) {
        let status = AuthorizationCenter.shared.authorizationStatus

        if status == .approved {
            result(true) // Permission already granted
        } else {
            Task {
                do {
                    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                    let newStatus = AuthorizationCenter.shared.authorizationStatus
                    if newStatus == .approved {
                        result(true) // Permission granted
                    } else {
                        result(FlutterError(code: "PERMISSION_DENIED", message: "User denied permission", details: nil))
                    }
                } catch {
                    result(FlutterError(code: "AUTH_ERROR", message: "Failed to request authorization", details: error.localizedDescription))
                }
            }
        }
    }

    private func presentContentView(method: String) {
        if #available(iOS 13.0, *) {
            guard let rootVC = UIApplication.shared.delegate?.window??.rootViewController else {
                print("Root view controller not found")
                return
            }

            globalMethodCall = method
            let vc: UIViewController

            if #available(iOS 15.0, *) {
                // Using SwiftUI in iOS 15+ devices
                vc = UIHostingController(
                    rootView: ContentView()
                        .environmentObject(MyModel.shared)
                        .environmentObject(ManagedSettingsStore())
                )
            } else {
                // Fallback for earlier versions (UI only, no SwiftUI)
                vc = UIViewController()
                // Fallback code to present non-SwiftUI view if needed.
            }
            rootVC.present(vc, animated: true, completion: nil)
        } else {
            // If the device is older than iOS 13, handle the fallback or error
            print("This feature requires iOS 13 or later")
        }
    }
}
