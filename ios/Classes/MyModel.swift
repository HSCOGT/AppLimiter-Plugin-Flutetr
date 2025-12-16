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

    func isAutomaticWebFilterEnabled() -> Bool {
        // ManagedSettingsStore is instantiated here for accessing the current value.
        let store = ManagedSettingsStore()

        // If blockedByFilter is not nil, the filter is enabled
        return store.webContent.blockedByFilter != nil
    }

    func setAutomaticWebFilter() {
        print("Applying automatic web filter (FilterPolicy.auto)")

        // The ManagedSettings store
        let store = ManagedSettingsStore()

        // The filter policy to apply
        let filterPolicy: WebContentSettings.FilterPolicy = .auto()
        store.webContent.blockedByFilter = filterPolicy
    }

    func disableAutomaticWebFilter() {
        print("Removing automatic web filter")

        // The ManagedSettings store
        let store = ManagedSettingsStore()

        // Setting the property to nil removes the restriction
        store.webContent.blockedByFilter = nil
    }
}
