import Foundation
import FamilyControls
import ManagedSettings

@available(iOS 15.0, *)
private let _MyModel = MyModel()

@available(iOS 15.0, *)
class MyModel: ObservableObject {
    let store = ManagedSettingsStore()

    @Published var selectionToDiscourage: FamilyActivitySelection
    @Published var selectionToEncourage: FamilyActivitySelection

    init() {
        selectionToDiscourage = FamilyActivitySelection()
        selectionToEncourage = FamilyActivitySelection()
    }

    class var shared: MyModel {
        return _MyModel
    }

    func setShieldRestrictions() {
        print("setShieldRestrictions")
        let applications = MyModel.shared.selectionToDiscourage

        if applications.applicationTokens.isEmpty {
            print("empty applicationTokens")
        }
        if applications.categoryTokens.isEmpty {
            print("empty categoryTokens")
        }

        store.shield.applications = applications.applicationTokens.isEmpty ? nil : applications.applicationTokens
        store.shield.applicationCategories = applications.categoryTokens.isEmpty
            ? nil
            : ShieldSettings.ActivityCategoryPolicy.specific(applications.categoryTokens)
    }

    func getBlockedAppCount() -> Int {
        // Use the actual shielded apps that are currently applied
        if let blockedApps = store.shield.applications {
            return blockedApps.count
        }

        // Fallback: use selection model (what user selected)
        return selectionToDiscourage.applicationTokens.count
    }

    /// Method to handle Automatic Web Filtering
    func setAutomaticWebFilter(enabled: Bool) {
        print("Setting automatic web filter to: \(enabled)")
        
        // .auto() is the system-level adult content filter
        if enabled {
            store.webContent.blockedByFilter = .auto()
        } else {
            store.webContent.blockedByFilter = nil
        }
    }
    
    // Helper to check if automatic web filter is enabled
    func isAutomaticWebFilterEnabled() -> Bool {
        return store.webContent.blockedByFilter != nil
    }

    // Helper to convert selection to JSON for Flutter
    func getEncodedSelection() -> String? {
        if #available(iOS 16.0, *) {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(selectionToDiscourage)
                return String(data: data, encoding: .utf8)
            } catch {
                print("Failed to encode selection: \(error)")
                return nil
            }
        }
        return nil
    }

    /// Decodes a JSON string from the Parent and applies it to this Child device
    func applyEncodedSelection(jsonString: String) {
        if #available(iOS 16.0, *) {
            guard let data = jsonString.data(using: .utf8) else { 
                print("Error: Could not convert string to data")
                return 
            }
            
            do {
                let decoder = JSONDecoder()
                let decodedSelection = try decoder.decode(FamilyActivitySelection.self, from: data)
                
                // 1. Update the local model so the UI stays in sync
                DispatchQueue.main.async {
                    self.selectionToDiscourage = decodedSelection
                    
                    // 2. Apply to the actual system shield
                    self.setShieldRestrictions()
                    print("Successfully applied remote restrictions")
                }
            } catch {
                print("Failed to decode selection: \(error.localizedDescription)")
            }
        }
    }
}
