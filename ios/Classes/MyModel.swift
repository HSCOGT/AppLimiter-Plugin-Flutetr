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

    func setWebDomainRestrictions(domains: [String]) {
        print("setWebDomainRestrictions:", domains)

        // The ManagedSettings store
        let store = ManagedSettingsStore()

        // If empty list, remove restrictions completely
        if domains.isEmpty {
            store.shield.webDomains = nil
            return
        }

        // Convert strings → WebDomainToken
        let tokens = Set(
            domains.compactMap { domain -> WebDomainToken? in
                guard !domain.isEmpty else { return nil }
                return WebDomainToken(domain: domain)
            }
        )

        if tokens.isEmpty {
            print("No valid domains to block")
            store.shield.webDomains = nil
            return
        }

        // Apply domain shields
        store.shield.webDomains = tokens
    }
}
