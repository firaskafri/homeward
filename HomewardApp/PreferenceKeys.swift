import Foundation

enum HomewardPreferenceKeys {
    static let onboardingStep = "onboardingStep"
    static let showNextTransitionTime = "showNextTransitionTime"
    static let legacyShowRemainingTime = "showRemainingTime"

    static func migrate() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: showNextTransitionTime) == nil,
              let legacyValue = defaults.object(
                  forKey: legacyShowRemainingTime
              ) as? Bool else {
            return
        }
        defaults.set(legacyValue, forKey: showNextTransitionTime)
        defaults.removeObject(forKey: legacyShowRemainingTime)
    }
}
