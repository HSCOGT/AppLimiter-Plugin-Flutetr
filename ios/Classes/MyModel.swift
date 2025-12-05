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

    /// Sets web domain restrictions by shielding the web domains and the parent browser (Safari).
    ///
    /// - Parameters:
    ///   - domains: An array of string representations of web domains (e.g., "youtube.com").
    ///   - browserBundleID: The bundle identifier of the browser to shield (defaults to Safari).
    func setWebDomainRestrictions(
        domains: [String], 
        browserBundleID: String = "com.apple.mobilesafari"
    ) {
        print("setWebDomainRestrictions:", domains)

        // The ManagedSettings store applies the restrictions.
        let store = ManagedSettingsStore()

        // 1. Convert strings to WebDomainToken using the correct initializer
        let webTokens = Set(
            domains.compactMap { domain -> WebDomainToken? in
                guard !domain.isEmpty else { return nil }
                
                // The correct initializer is WebDomainToken(webDomain: String)
                return WebDomainToken(webDomain: domain) 
            }
        )

        // 2. Handle empty list: remove all restrictions
        if webTokens.isEmpty {
            print("Removing all web domain and browser shields.")
            store.shield.webDomains = nil
            // Optionally unshield the browser if no domains are left
            store.shield.applications = nil 
            return
        }

        // 3. Apply the parent application shield (e.g., Safari)
        // NOTE: The bundle ID MUST be one selected by the user in FamilyActivitySelection 
        // for this restriction to be effective.
        let applicationToken = ApplicationToken(bundleIdentifier: browserBundleID)
        store.shield.applications = [applicationToken]

        // 4. Apply the domain shields
        store.shield.webDomains = webTokens
        
        print("Successfully set web domain shields for \(webTokens.count) domains on \(browserBundleID).")
    }
}
