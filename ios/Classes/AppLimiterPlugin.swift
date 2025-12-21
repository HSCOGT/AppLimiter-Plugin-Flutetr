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
    /// Property to hold the Flutter result callback for app selection
    private var appSelectionResult: FlutterResult?

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
        let args = call.arguments as? [String: Any]
        let applyLocally = args?["applyLocally"] as? Bool ?? true // Default to true

        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)

        case "handleAppSelection":
            if #available(iOS 16.0, *) {
                handleAppSelection(method: "selectAppsToDiscourage", applyLocally: applyLocally, result: result)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "iOS 16+ required", details: nil))
            }

        case "getBlockedAppCount":
            if #available(iOS 16.0, *) {
                let count = MyModel.shared.getBlockedAppCount()
                result(count)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "iOS 16+ required", details: nil))
            }

        
        case "requestPermission":
            if #available(iOS 16.0, *) {
                requestPermission(result: result)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "iOS 16+ required", details: nil))
            }

        case "requestChildDeviceAuthorization":
            if #available(iOS 16.0, *) {
                requestChildDeviceAuthorization(result: result)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "iOS 16+ required", details: nil))
            }

        case "isAutomaticWebFilterEnabled":
            if #available(iOS 16.0, *) {
                let isEnabled = MyModel.shared.isAutomaticWebFilterEnabled()
                result(isEnabled)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "iOS 16+ required", details: nil))
            }

        case "setAutomaticWebFilter":
            if #available(iOS 16.0, *) {
                MyModel.shared.setAutomaticWebFilter()
                result(true)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "iOS 16+ required", details: nil))
            }

        case "disableAutomaticWebFilter":
            if #available(iOS 16.0, *) {
                MyModel.shared.disableAutomaticWebFilter()
                result(true)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "iOS 16+ required", details: nil))
            }

        case "applyRemoteSettings":
            if #available(iOS 16.0, *) {
                guard let jsonString = args?["jsonString"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "jsonString is required", details: nil))
                    return
                }
                // Call the model to apply the settings
                MyModel.shared.applyEncodedSelection(jsonString: jsonString)
                result(true)
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "iOS 16+ required for remote sync", details: nil))
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @available(iOS 16.0, *)
    private func handleAppSelection(method: String, applyLocally: Bool, result: @escaping FlutterResult) {
        // Store the result callback
        self.appSelectionResult = result

        let status = AuthorizationCenter.shared.authorizationStatus

        if status == .approved {
            DispatchQueue.main.async {
                self.presentContentView(method: method, applyLocally: applyLocally)
            }
        } else {
            Task {
                do {
                    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                    let newStatus = AuthorizationCenter.shared.authorizationStatus
                    if newStatus == .approved {
                        await MainActor.run {
                            self.presentContentView(method: method, applyLocally: applyLocally)
                        }
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

    @available(iOS 16.0, *)
    private func requestChildDeviceAuthorization(result: @escaping FlutterResult) {
        let status = AuthorizationCenter.shared.authorizationStatus

        if status == .approved {
            result(true)
            return
        }

        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .child)
                let newStatus = AuthorizationCenter.shared.authorizationStatus
                if newStatus == .approved {
                    result(true)
                } else {
                    result(FlutterError(code: "PERMISSION_DENIED", message: "User denied Family Controls permission", details: nil))
                }
            } catch {
                result(FlutterError(code: "AUTH_ERROR", message: "Family Controls authorization failed", details: error.localizedDescription))
            }
        }
    }

    @MainActor
    private func presentContentView(method: String, applyLocally: Bool) {
        if #available(iOS 13.0, *) {
            guard let rootVC = UIApplication.shared.delegate?.window??.rootViewController else {
                print("Root view controller not found")
                // Clean up the stored result if we fail to present
                self.appSelectionResult?(FlutterError(code: "PRESENT_ERROR", message: "Root view controller not found", details: nil))
                self.appSelectionResult = nil
                return
            }

            globalMethodCall = method
            let vc: UIViewController

            // Pass the completion handler into the SwiftUI view
            let contentView = ContentView(
                applyLocally: applyLocally,
                onDismiss: { [weak self] encodedSelection in
                    if let selectionData = encodedSelection {
                        // Return the JSON string to Flutter for syncing
                        self?.appSelectionResult?(selectionData)
                    } else {
                        self?.appSelectionResult?(nil)
                    }
                    self?.appSelectionResult = nil
                }
            )

            // Using SwiftUI in iOS 15+ devices
            vc = UIHostingController(rootView: contentView.environmentObject(MyModel.shared))
            rootVC.present(vc, animated: true, completion: nil)
        } else {
            // If the device is older than iOS 13, handle the fallback or error
            print("This feature requires iOS 13 or later")
        }
    }
}
