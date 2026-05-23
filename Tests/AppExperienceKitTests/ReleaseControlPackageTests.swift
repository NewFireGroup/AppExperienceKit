import Foundation
import Testing

@testable import AppExperienceKit

struct ReleaseControlPackageTests {
    @Test
    func featurePreviewDecisionStateUsesOptInDefaults() {
        let decision = ReleaseControlDecision(
            key: .feedbackFeature,
            isEnabled: true,
            variationKey: "feedback_assist",
            variables: ["ai_assist_enabled": "true"]
        )
        let state = ReleaseControlFlagState(
            key: .feedbackFeature,
            decision: decision,
            providerStatus: .optimizely(
                configuration: ReleaseControlConfiguration(
                    sdkKey: "sdk",
                    environmentKey: "development",
                    datafileURL: nil,
                    userId: "tester"
                ),
                connectionState: .connected
            ),
            preference: .systemDefault
        )

        #expect(state.displayName == "Feedback")
        #expect(state.stateLabel == "Available")
        #expect(state.providerConnectionLabel == "Connected")
        #expect(state.variationLabel == "feedback_assist")
        #expect(state.isVisibleInFeaturePreviews)
        let flagTypeDetail = state.variableDetails.first { $0.key == "flag_type" }
        let aiAssistDetail = state.variableDetails.first { $0.key == "ai_assist_enabled" }

        #expect(flagTypeDetail?.value == ReleaseControlFlagType.onDemand.rawValue)
        #expect(flagTypeDetail?.source == .systemDefault)
        #expect(aiAssistDetail?.value == "true")
        #expect(aiAssistDetail?.source == .optimizely)
    }

    @Test
    func featurePreviewDecisionHonorsLocalPreferences() {
        let optInControlled = ReleaseControlDecision(
            key: .planning,
            isEnabled: true,
            variables: ["flag_control_type": "opt_in"]
        )
        let optOutControlled = ReleaseControlDecision(
            key: .planning,
            isEnabled: true,
            variables: ["flag_control_type": "opt_out"]
        )

        #expect(!optInControlled.applying(.systemDefault).isEnabled)
        #expect(optInControlled.applying(.optIn).isEnabled)
        #expect(!optInControlled.applying(.optOut).isEnabled)
        #expect(optOutControlled.applying(.systemDefault).isEnabled)
        #expect(optOutControlled.applying(.optIn).isEnabled)
        #expect(!optOutControlled.applying(.optOut).isEnabled)
    }

    @Test
    func unavailableProviderHidesPreviewStateAsUnavailable() {
        let state = ReleaseControlFlagState(
            key: .cashflowCalendarYearFeature,
            decision: ReleaseControlDecision.disabled(
                .cashflowCalendarYearFeature,
                reason: "Audience excluded"
            ),
            providerStatus: .none(reason: "Optimizely is not configured")
        )

        #expect(state.stateLabel == "Unavailable")
        #expect(state.providerConnectionLabel == "Unavailable")
        #expect(state.fallbackReason == "Audience excluded")
        #expect(!state.isVisibleInFeaturePreviews)
    }
}
