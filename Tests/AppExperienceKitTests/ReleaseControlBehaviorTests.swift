import Foundation
import Testing

@testable import AppExperienceKit

struct ReleaseControlBehaviorTests {

    @Test
    func releaseControlKeysUseExistingPlanningPocKeyAndFutureSubfeatureKey() {
        #expect(ReleaseControlKey.planning.rawValue == "planning")
        #expect(ReleaseControlKey.planningEditor.rawValue == "planning_editor")
        #expect(ReleaseControlKey.feedbackFeature.rawValue == "feedback_feature")
        #expect(ReleaseControlKey.cashflowCalendarYearFeature.rawValue == "cashflow_calendar_year_feature")
        #expect(ReleaseControlKey.authenticationFeature.rawValue == "authentication_feature")
        #expect(ReleaseControlKey.planning.usesFutureFeatureSuffix == false)
        #expect(ReleaseControlKey.planningEditor.usesFutureFeatureSuffix == false)
        #expect(ReleaseControlKey.feedbackFeature.usesFutureFeatureSuffix)
        #expect(ReleaseControlKey.cashflowCalendarYearFeature.usesFutureFeatureSuffix)
        #expect(ReleaseControlKey.authenticationFeature.usesFutureFeatureSuffix)
    }

    @Test
    func releaseControlDescriptorsRepresentPackageAndHostKeys() {
        let descriptor = ReleaseControlDescriptor(
            key: "cashflow_reports_feature",
            displayName: "Cashflow Reports"
        )

        #expect(descriptor.id == "cashflow_reports_feature")
        #expect(descriptor.key == "cashflow_reports_feature")
        #expect(descriptor.displayName == "Cashflow Reports")
        #expect(ReleaseControlKey.feedbackFeature.descriptor.key == "feedback_feature")
        #expect(ReleaseControlKey.feedbackFeature.descriptor.displayName == "Feedback")
        #expect(ReleaseControlDescriptor.packageDefaults.map(\.key) == ReleaseControlKey.allCases.map(\.rawValue))
    }

    @Test
    func descriptorPreferenceStoreUsesReleaseControlStorageNamespace() throws {
        let suiteName = "ReleaseControlDescriptorPreferenceStore-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = ReleaseControlPreferenceStore(defaults: defaults)
        let descriptor = ReleaseControlDescriptor(
            key: "cashflow_reports_feature",
            displayName: "Cashflow Reports"
        )

        #expect(store.preference(for: descriptor) == .systemDefault)

        store.setPreference(.optIn, for: descriptor, notifiesObservers: false)

        #expect(store.preference(for: descriptor) == .optIn)
        #expect(defaults.string(forKey: "releaseControl.preference.cashflow_reports_feature") == "opt_in")
        #expect(store.attributes(for: descriptor) == ["release_control_preference": "opt_in"])
    }

    @Test
    func descriptorStateLoaderBuildsHostDefinedFeaturePreviewStates() async throws {
        let suiteName = "ReleaseControlDescriptorStateLoader-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let preferenceStore = ReleaseControlPreferenceStore(defaults: defaults)
        let descriptor = ReleaseControlDescriptor(
            key: "cashflow_reports_feature",
            displayName: "Cashflow Reports"
        )
        let client = ReleaseControlDescriptorStateRecordingClient(
            status: ReleaseControlStatus(
                provider: .optimizely,
                connectionState: .connected,
                environmentKey: "development",
                userId: "anonymous-install",
                datafileURL: URL(string: "https://cdn.optimizely.com/datafiles/test.json")
            ),
            decisions: [
                descriptor.key: ReleaseControlDescriptorDecision(
                    descriptor: descriptor,
                    isEnabled: true,
                    variationKey: "opt_in_available"
                )
            ]
        )
        let loader = ReleaseControlDescriptorStateLoader(
            releaseControls: [descriptor],
            preferenceStore: preferenceStore
        )

        let availableStates = await loader.load(using: client)
        #expect(availableStates.count == 1)
        #expect(availableStates[0].descriptor == descriptor)
        #expect(availableStates[0].displayName == "Cashflow Reports")
        #expect(availableStates[0].stateLabel == "Available")
        #expect(!availableStates[0].preferenceToggleValue)

        preferenceStore.setPreference(.optIn, for: descriptor, notifiesObservers: false)

        let enabledStates = await loader.load(using: client)
        #expect(enabledStates.count == 1)
        #expect(enabledStates[0].stateLabel == "Enabled")
        #expect(enabledStates[0].preferenceToggleValue)
    }

    @Test
    func descriptorStateLoaderHidesDisabledHostKeysUntilLocallyChanged() async throws {
        let suiteName = "ReleaseControlDescriptorStateLoaderHidden-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let preferenceStore = ReleaseControlPreferenceStore(defaults: defaults)
        let descriptor = ReleaseControlDescriptor(
            key: "cashflow_reports_feature",
            displayName: "Cashflow Reports"
        )
        let client = ReleaseControlDescriptorStateRecordingClient(
            status: ReleaseControlStatus(
                provider: .optimizely,
                connectionState: .connected,
                environmentKey: "development",
                userId: "anonymous-install"
            ),
            decisions: [
                descriptor.key: .disabled(descriptor, reason: "Audience excluded")
            ]
        )
        let loader = ReleaseControlDescriptorStateLoader(
            releaseControls: [descriptor],
            preferenceStore: preferenceStore
        )

        let hiddenStates = await loader.load(using: client)
        #expect(hiddenStates.isEmpty)

        preferenceStore.setPreference(.optOut, for: descriptor, notifiesObservers: false)

        let locallyChangedStates = await loader.load(using: client)
        #expect(locallyChangedStates.count == 1)
        #expect(locallyChangedStates[0].stateLabel == "Off")
    }

    @Test
    func customReleaseControlEventsCarryHostKeysAndAggregateProperties() {
        let descriptor = ReleaseControlDescriptor(
            key: "cashflow_reports_feature",
            displayName: "Cashflow Reports"
        )
        let event = ReleaseControlCustomEvent(
            releaseControl: descriptor,
            key: "cashflow_report_selected",
            eventProperties: [
                "report_kind": "summary",
                "variation_key": "opt_in_available"
            ]
        )

        #expect(event.releaseControl == descriptor)
        #expect(event.key == "cashflow_report_selected")
        #expect(event.eventProperties == [
            "report_kind": "summary",
            "variation_key": "opt_in_available"
        ])
        #expect(event.eventTags["$opt_event_properties"] as? [String: String] == event.eventProperties)
    }

    @Test
    @MainActor
    func settingsAndFeaturePreviewViewsAcceptHostReleaseControls() {
        let descriptor = ReleaseControlDescriptor(
            key: "cashflow_reports_feature",
            displayName: "Cashflow Reports"
        )
        let settings = AppSettingsView(featurePreviewReleaseControls: ReleaseControlDescriptor.packageDefaults + [descriptor])
        let featurePreviews = ReleaseControlFlagStatesView(releaseControls: [descriptor])

        #expect(String(describing: type(of: settings)) == "AppSettingsView")
        #expect(String(describing: type(of: featurePreviews)) == "ReleaseControlFlagStatesView")
    }

    @Test
    func feedbackReleaseControlDecisionControlsNavigationAndAIAssist() {
        let enabled = ReleaseControlDecision(
            key: .feedbackFeature,
            isEnabled: true,
            variables: ["ai_assist_enabled": "true"]
        )
        let disabled = ReleaseControlDecision.disabled(.feedbackFeature)

        #expect(enabled.showsFeedbackSettings)
        #expect(enabled.showsFeedbackNavigation)
        #expect(enabled.allowsFeedbackAIAssist)
        #expect(!disabled.showsFeedbackSettings)
        #expect(!disabled.showsFeedbackNavigation)
        #expect(!disabled.allowsFeedbackAIAssist)
    }

    @Test
    func feedbackAIAssistVariableNormalizesBooleanOptimizelyValues() {
        #expect(ReleaseControlBoolVariable.normalizedString(stringValue: nil, boolValue: true) == "true")
        #expect(ReleaseControlBoolVariable.normalizedString(stringValue: nil, boolValue: false) == "false")
        #expect(ReleaseControlBoolVariable.normalizedString(stringValue: "true", boolValue: nil) == "true")

        let enabled = ReleaseControlDecision(
            key: .feedbackFeature,
            isEnabled: true,
            variables: [
                "ai_assist_enabled": ReleaseControlBoolVariable.normalizedString(
                    stringValue: nil,
                    boolValue: true
                ) ?? ""
            ]
        )

        #expect(enabled.allowsFeedbackAIAssist)
    }

    @Test
    func releaseControlFlagMetadataUsesGlobalDefaultsAndVariables() {
        for key in ReleaseControlKey.allCases {
            let missingVariables = ReleaseControlDecision(key: key, isEnabled: true)

            #expect(missingVariables.flagType == .onDemand)
            #expect(missingVariables.flagControlType == .optIn)
        }

        let appLaunch = ReleaseControlDecision(
            key: .authenticationFeature,
            isEnabled: true,
            variables: ["flag_type": "app_launch"]
        )
        let extensionLaunch = ReleaseControlDecision(
            key: .feedbackFeature,
            isEnabled: true,
            variables: ["flag_type": "extension_launch"]
        )
        let onDemand = ReleaseControlDecision(
            key: .planning,
            isEnabled: true,
            variables: ["flag_type": "on_demand"]
        )
        let optOutControlled = ReleaseControlDecision(
            key: .planning,
            isEnabled: true,
            variables: ["flag_control_type": "opt_out"]
        )

        #expect(appLaunch.flagType == .appLaunch)
        #expect(extensionLaunch.flagType == .extensionLaunch)
        #expect(onDemand.flagType == .onDemand)
        #expect(optOutControlled.flagControlType == .optOut)
    }

    @Test
    func flagControlTypeDefinesHowLocalPreferenceAppliesToDecision() {
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
    func cashflowCalendarYearDecisionControlsScheduling() {
        let enabled = ReleaseControlDecision(
            key: .cashflowCalendarYearFeature,
            isEnabled: true
        )
        let disabled = ReleaseControlDecision.disabled(.cashflowCalendarYearFeature)
        let otherEnabled = ReleaseControlDecision(key: .planning, isEnabled: true)

        #expect(enabled.showsCashflowCalendarYearScheduling)
        #expect(!disabled.showsCashflowCalendarYearScheduling)
        #expect(!otherEnabled.showsCashflowCalendarYearScheduling)
    }

    @Test
    func authenticationDecisionRequiresRemoteEnablementAndLocalOptIn() {
        let enabled = ReleaseControlDecision(
            key: .authenticationFeature,
            isEnabled: true,
            variationKey: "opt_in_available",
            variables: [
                "app_lock_available": "true",
                "github_linking_available": "true",
                "app_lock_mode": "launch_only"
            ]
        )
        let disabled = ReleaseControlDecision.disabled(.authenticationFeature)
        let otherEnabled = ReleaseControlDecision(key: .feedbackFeature, isEnabled: true)

        #expect(enabled.showsAuthenticationPreview)
        #expect(!enabled.isAuthenticationActive(preference: .systemDefault))
        #expect(enabled.isAuthenticationActive(preference: .optIn))
        #expect(!enabled.isAuthenticationActive(preference: .optOut))
        #expect(!disabled.isAuthenticationActive(preference: .optIn))
        #expect(!otherEnabled.isAuthenticationActive(preference: .optIn))
        #expect(enabled.isAuthenticationAppLockAvailable(preference: .optIn))
        #expect(enabled.isAuthenticationGitHubLinkingAvailable(preference: .optIn))
        #expect(enabled.authenticationAppLockMode == .launchOnly)
    }

    @Test
    func authenticationDecisionDefaultsCapabilitiesOffWhenVariablesAreMissing() {
        let enabled = ReleaseControlDecision(
            key: .authenticationFeature,
            isEnabled: true
        )

        #expect(enabled.showsAuthenticationPreview)
        #expect(!enabled.isAuthenticationAppLockAvailable(preference: .optIn))
        #expect(!enabled.isAuthenticationGitHubLinkingAvailable(preference: .optIn))
        #expect(enabled.authenticationAppLockMode == .launchOnly)
    }

    @Test
    func planningEditorDecisionControlsAreasOfFocusEditor() {
        let enabled = ReleaseControlDecision(
            key: .planningEditor,
            isEnabled: true,
            variationKey: "areas_of_focus_v1"
        )
        let disabled = ReleaseControlDecision.disabled(.planningEditor)
        let otherEnabled = ReleaseControlDecision(key: .planning, isEnabled: true)

        #expect(enabled.showsPlanningEditor)
        #expect(!disabled.showsPlanningEditor)
        #expect(!otherEnabled.showsPlanningEditor)
    }

    @Test
    func localOptOutDisablesDecisionWithoutLettingOptInBypassOptimizely() {
        let enabled = ReleaseControlDecision(
            key: .planning,
            isEnabled: true,
            variationKey: "variant_a"
        )
        let disabled = ReleaseControlDecision.disabled(.planning, reason: "Audience excluded")

        let optedOut = enabled.applying(.optOut)
        let optedInButExcluded = disabled.applying(.optIn)

        #expect(!optedOut.isEnabled)
        #expect(optedOut.variationKey == "variant_a")
        #expect(optedOut.reason == "Local preference is off")
        #expect(!optedInButExcluded.isEnabled)
        #expect(optedInButExcluded.reason == "Audience excluded")
    }

    @Test
    func cashflowCalendarYearEventsUseAggregateOnlyTags() {
        let opened = ReleaseControlEvent.cashflowCalendarYearFeatureOpened(variationKey: "variant_a")
        let saved = ReleaseControlEvent.cashflowCalendarYearScheduleSaved(variationKey: nil)

        #expect(opened.key == "cashflow_calendar_year_feature_opened")
        #expect(opened.releaseControlKey == .cashflowCalendarYearFeature)
        #expect(opened.eventProperties == ["variation_key": "variant_a"])
        #expect(saved.key == "cashflow_calendar_year_schedule_saved")
        #expect(saved.releaseControlKey == .cashflowCalendarYearFeature)
        #expect(saved.eventProperties.isEmpty)
    }

    @Test
    func authenticationEventsUseRegisteredKeysAndSafeProperties() {
        let optedIn = ReleaseControlEvent.authenticationFeatureOptedIn(
            launchSource: "feature_previews",
            previousPreference: "default",
            variationKey: "opt_in_available"
        )
        let optedOut = ReleaseControlEvent.authenticationFeatureOptedOut(
            launchSource: "feature_previews",
            previousPreference: "opt_in",
            variationKey: nil
        )
        let appLockEnabled = ReleaseControlEvent.authenticationAppLockEnabled(
            launchSource: "settings",
            lockMode: "launch_only",
            variationKey: "opt_in_available"
        )
        let appUnlockFailed = ReleaseControlEvent.authenticationAppUnlockFailed(
            result: "canceled",
            lockMode: "launch_only",
            variationKey: "opt_in_available"
        )
        let githubLinked = ReleaseControlEvent.authenticationGitHubLinked(
            launchSource: "settings",
            variationKey: "opt_in_available"
        )
        let credentialUsed = ReleaseControlEvent.authenticationGitHubCredentialUsed(
            launchSource: "feedback",
            destination: "github",
            variationKey: "opt_in_available"
        )

        #expect(optedIn.key == "authentication_feature_opted_in")
        #expect(optedIn.releaseControlKey == .authenticationFeature)
        #expect(optedIn.eventProperties == [
            "launch_source": "feature_previews",
            "previous_preference": "default",
            "variation_key": "opt_in_available"
        ])
        #expect(optedOut.key == "authentication_feature_opted_out")
        #expect(optedOut.eventProperties == [
            "launch_source": "feature_previews",
            "previous_preference": "opt_in"
        ])
        #expect(appLockEnabled.key == "authentication_app_lock_enabled")
        #expect(appLockEnabled.eventProperties == [
            "launch_source": "settings",
            "lock_mode": "launch_only",
            "variation_key": "opt_in_available"
        ])
        #expect(appUnlockFailed.key == "authentication_app_unlock_failed")
        #expect(appUnlockFailed.eventProperties == [
            "lock_mode": "launch_only",
            "result": "canceled",
            "variation_key": "opt_in_available"
        ])
        #expect(githubLinked.key == "authentication_github_linked")
        #expect(githubLinked.eventProperties == [
            "launch_source": "settings",
            "variation_key": "opt_in_available"
        ])
        #expect(credentialUsed.key == "authentication_github_credential_used")
        #expect(credentialUsed.eventProperties == [
            "destination": "github",
            "launch_source": "feedback",
            "variation_key": "opt_in_available"
        ])
        #expect(!credentialUsed.eventProperties.keys.contains("github_login"))
        #expect(!credentialUsed.eventProperties.keys.contains("github_id"))
        #expect(!credentialUsed.eventProperties.keys.contains("token"))
    }

    @Test
    func planningEditorOpenedEventUsesAggregateOnlyTags() {
        let opened = ReleaseControlEvent.planningEditorOpened(variationKey: "areas_of_focus_v1")

        #expect(opened.key == "planning_editor_opened")
        #expect(opened.releaseControlKey == .planningEditor)
        #expect(opened.eventProperties == ["variation_key": "areas_of_focus_v1"])
        #expect(opened.eventTags["$opt_event_properties"] as? [String: String] == opened.eventProperties)
    }

    @Test
    func feedbackEventsUseRegisteredOptimizelyKeysAndCustomProperties() throws {
        let opened = ReleaseControlEvent.feedbackFeatureOpened(
            launchSource: "cashflow_summary",
            variationKey: "variant_a"
        )
        let started = ReleaseControlEvent.feedbackFormStarted(
            category: "bug",
            source: "manual",
            launchSource: "cashflow_summary",
            variationKey: "variant_a"
        )
        let aiAssistOpened = ReleaseControlEvent.feedbackAIAssistOpened(
            category: "ai_feedback",
            source: "manual",
            launchSource: "cashflow_summary",
            variationKey: "variant_a"
        )
        let aiAssist = ReleaseControlEvent.feedbackAIAssistUsed(
            category: "ai_feedback",
            source: "ai_assisted",
            aiResult: "ai_assisted",
            launchSource: "cashflow_summary",
            variationKey: "variant_a"
        )
        let aiAssistCanceled = ReleaseControlEvent.feedbackAIAssistCanceled(
            category: "ai_feedback",
            source: "manual",
            launchSource: "cashflow_summary",
            variationKey: "variant_a"
        )
        let submitted = ReleaseControlEvent.feedbackSubmitted(
            category: "feature_request",
            source: "manual",
            destination: "github",
            launchSource: "settings",
            variationKey: "variant_a"
        )
        let abandoned = ReleaseControlEvent.feedbackFormAbandoned(
            category: "general",
            source: "manual",
            launchSource: "overview",
            variationKey: nil
        )

        #expect(opened.key == "feedback_feature_opened")
        #expect(opened.eventProperties == [
            "launch_source": "cashflow_summary",
            "variation_key": "variant_a"
        ])
        #expect(started.key == "feedback_form_started")
        #expect(started.eventProperties == [
            "category": "bug",
            "launch_source": "cashflow_summary",
            "source": "manual",
            "variation_key": "variant_a"
        ])
        #expect(aiAssistOpened.key == "feedback_ai_assist_opened")
        #expect(aiAssistOpened.eventProperties == [
            "category": "ai_feedback",
            "launch_source": "cashflow_summary",
            "source": "manual",
            "variation_key": "variant_a"
        ])
        #expect(aiAssist.key == "feedback_ai_assist_used")
        #expect(aiAssist.eventProperties == [
            "ai_result": "ai_assisted",
            "category": "ai_feedback",
            "launch_source": "cashflow_summary",
            "source": "ai_assisted",
            "variation_key": "variant_a"
        ])
        #expect(aiAssistCanceled.key == "feedback_ai_assist_canceled")
        #expect(aiAssistCanceled.eventProperties == [
            "category": "ai_feedback",
            "launch_source": "cashflow_summary",
            "source": "manual",
            "variation_key": "variant_a"
        ])
        #expect(submitted.key == "feedback_submitted")
        #expect(submitted.eventProperties == [
            "category": "feature_request",
            "destination": "github",
            "launch_source": "settings",
            "source": "manual",
            "variation_key": "variant_a"
        ])
        #expect(abandoned.key == "feedback_form_abandoned")
        #expect(abandoned.eventProperties == [
            "category": "general",
            "launch_source": "overview",
            "source": "manual"
        ])

        let startedTags = started.eventTags
        let properties = try #require(startedTags["$opt_event_properties"] as? [String: String])
        #expect(properties == started.eventProperties)
    }

    @Test
    func releaseControlEventsMapToTheirFeatureKeys() {
        #expect(ReleaseControlEvent.planningFeatureOpened(variationKey: nil).releaseControlKey == .planning)
        #expect(ReleaseControlEvent.planningEditorOpened(variationKey: nil).releaseControlKey == .planningEditor)
        #expect(ReleaseControlEvent.feedbackFeatureOpened(launchSource: "overview", variationKey: nil).releaseControlKey == .feedbackFeature)
        #expect(ReleaseControlEvent.feedbackSubmitted(
            category: "general",
            source: "manual",
            destination: "local",
            launchSource: "overview",
            variationKey: nil
        ).releaseControlKey == .feedbackFeature)
        #expect(ReleaseControlEvent.authenticationFeatureOptedIn(
            launchSource: "feature_previews",
            previousPreference: "default",
            variationKey: nil
        ).releaseControlKey == .authenticationFeature)
    }

    @Test
    func releaseControlKeysHaveStableDisplayNames() {
        #expect(ReleaseControlKey.planning.displayName == "Planning")
        #expect(ReleaseControlKey.planningEditor.displayName == "Planning Editor")
        #expect(ReleaseControlKey.cashflowCalendarYearFeature.displayName == "Calendar-Year Cashflow")
        #expect(ReleaseControlKey.authenticationFeature.displayName == "Authentication")
    }

    @Test
    func preferenceStorePersistsTypedPreferencesAndBuildsGenericOptimizelyAttribute() throws {
        let defaults = try Self.defaults()
        let store = ReleaseControlPreferenceStore(defaults: defaults)

        #expect(store.preference(for: .planning) == .systemDefault)

        store.setPreference(.optIn, for: .planning)
        store.setPreference(.optOut, for: .feedbackFeature)

        #expect(store.preference(for: .planning) == .optIn)
        #expect(store.preference(for: .feedbackFeature) == .optOut)
        #expect(store.attributes(for: .planning) == ["release_control_preference": "opt_in"])
        #expect(store.attributes(for: .feedbackFeature) == ["release_control_preference": "opt_out"])
    }

    @Test
    func preferenceStoreCanDeferPreferenceNotificationUntilReleaseRefreshCompletes() throws {
        let defaults = try Self.defaults()
        let store = ReleaseControlPreferenceStore(defaults: defaults)
        let recorder = ReleaseControlPreferenceNotificationRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: ReleaseControlPreferenceStore.preferenceDidChangeNotification,
            object: store,
            queue: nil
        ) { notification in
            recorder.record(notification)
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        store.setPreference(.optIn, for: .feedbackFeature, notifiesObservers: false)

        #expect(store.preference(for: .feedbackFeature) == .optIn)
        #expect(recorder.keys.isEmpty)

        store.postPreferenceDidChange(for: .feedbackFeature)

        #expect(recorder.keys == ["feedback_feature"])
    }

    @Test
    func configurationAddsFeaturePreviewPreferenceToDecisionAttributes() throws {
        let defaults = try Self.defaults()
        let store = ReleaseControlPreferenceStore(defaults: defaults)
        store.setPreference(.optIn, for: .planning)
        store.setPreference(.optOut, for: .planningEditor)
        let bundle = try Self.bundle(
            environmentKey: "development",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )

        let configuration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: defaults
        )

        let planningAttributes = configuration.decisionAttributes(
            for: .planning,
            preferenceStore: store
        )
        let editorAttributes = configuration.decisionAttributes(
            for: .planningEditor,
            preferenceStore: store
        )

        #expect(configuration.attributes["release_control_preference"] == nil)
        #expect(planningAttributes["release_control_preference"] == "opt_in")
        #expect(editorAttributes["release_control_preference"] == "opt_out")
    }

    @Test
    func everyActiveReleaseControlAddsItsFeaturePreviewPreferenceToDecisionAttributes() throws {
        let defaults = try Self.defaults()
        let store = ReleaseControlPreferenceStore(defaults: defaults)
        let bundle = try Self.bundle(
            environmentKey: "development",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )
        let configuration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: defaults
        )

        for key in ReleaseControlKey.allCases {
            store.setPreference(.optIn, for: key)

            let optInAttributes = configuration.decisionAttributes(
                for: key,
                preferenceStore: store
            )

            #expect(optInAttributes[ReleaseControlPreferenceStore.attributeKey] == "opt_in")

            store.setPreference(.optOut, for: key)

            let optOutAttributes = configuration.decisionAttributes(
                for: key,
                preferenceStore: store
            )

            #expect(optOutAttributes[ReleaseControlPreferenceStore.attributeKey] == "opt_out")
        }
    }

    @Test
    func localOptOutDisablesEveryActiveReleaseControlDecision() {
        for key in ReleaseControlKey.allCases {
            let enabled = ReleaseControlDecision(
                key: key,
                isEnabled: true,
                variationKey: "variant_a",
                variables: ["placeholder_title": "Preview"],
                diagnostics: ["release_control_flag_key": key.rawValue]
            )

            let optedOut = enabled.applying(.optOut)

            #expect(!optedOut.isEnabled)
            #expect(optedOut.key == key)
            #expect(optedOut.variationKey == "variant_a")
            #expect(optedOut.variables["placeholder_title"] == "Preview")
            #expect(optedOut.diagnostics["release_control_flag_key"] == key.rawValue)
            #expect(optedOut.reason == "Local preference is off")
        }
    }

    @Test
    func flagStateLoaderBuildsEnabledAndDisabledStatesFromFakeClient() async {
        let client = ReleaseControlFlagStateRecordingClient(
            status: ReleaseControlStatus(
                provider: .optimizely,
                connectionState: .connected,
                environmentKey: "development",
                userId: "planning-poc-user-a",
                datafileURL: URL(string: "https://cdn.optimizely.com/datafiles/test.json")
            ),
            decisions: [
                .planning: ReleaseControlDecision(
                    key: .planning,
                    isEnabled: true,
                    variationKey: "variant_a"
                ),
                .planningEditor: ReleaseControlDecision.disabled(.planningEditor, reason: "Audience excluded")
            ]
        )
        let loader = ReleaseControlFlagStateLoader(keys: [.planning, .planningEditor])

        let states = await loader.load(using: client)

        #expect(states.count == 1)
        #expect(states[0].key == .planning)
        #expect(states[0].displayName == "Planning")
        #expect(states[0].stateLabel == "Available")
        #expect(states[0].preference == .systemDefault)
        #expect(!states[0].preferenceToggleValue)
        #expect(states[0].providerConnectionLabel == "Connected")
        #expect(states[0].variationLabel == "variant_a")
        #expect(states[0].fallbackReason == nil)
    }

    @Test
    func flagStateDetailsIncludeStandardVariablesAndDefaults() {
        let missingVariables = ReleaseControlFlagState(
            key: .feedbackFeature,
            decision: ReleaseControlDecision(key: .feedbackFeature, isEnabled: true),
            providerStatus: ReleaseControlStatus(
                provider: .optimizely,
                connectionState: .connected
            )
        )

        #expect(missingVariables.variableDetails.map(\.key) == ["flag_type", "flag_control_type"])
        #expect(missingVariables.variableDetails.map(\.value) == ["on_demand", "opt_in"])
        #expect(missingVariables.variableDetails.allSatisfy { $0.source == .systemDefault })

        let configuredVariables = ReleaseControlFlagState(
            key: .feedbackFeature,
            decision: ReleaseControlDecision(
                key: .feedbackFeature,
                isEnabled: true,
                variables: [
                    "flag_type": "extension_launch",
                    "flag_control_type": "opt_out",
                    "ai_assist_enabled": "true"
                ]
            ),
            providerStatus: ReleaseControlStatus(
                provider: .optimizely,
                connectionState: .connected
            )
        )

        #expect(configuredVariables.variableDetails.map(\.key) == [
            "flag_type",
            "flag_control_type",
            "ai_assist_enabled"
        ])
        #expect(configuredVariables.variableDetails.map(\.value) == [
            "extension_launch",
            "opt_out",
            "true"
        ])
        #expect(configuredVariables.variableDetails.map(\.source) == [
            .optimizely,
            .optimizely,
            .optimizely
        ])
    }

    @Test
    func flagStateLoaderHidesDisabledDecisionsWithoutLocalPreference() async {
        let client = ReleaseControlFlagStateRecordingClient(
            status: ReleaseControlStatus(
                provider: .optimizely,
                connectionState: .connected,
                environmentKey: "development",
                userId: "planning-poc-user-a",
                datafileURL: URL(string: "https://cdn.optimizely.com/datafiles/test.json")
            ),
            decisions: [
                .planning: ReleaseControlDecision(
                    key: .planning,
                    isEnabled: false
                )
            ]
        )
        let loader = ReleaseControlFlagStateLoader(keys: [.planning])

        let states = await loader.load(using: client)

        #expect(states.isEmpty)
    }

    @Test
    func flagStateLoaderShowsAuthenticationAsAvailableUntilLocalOptIn() async throws {
        let defaults = try Self.defaults()
        let preferenceStore = ReleaseControlPreferenceStore(defaults: defaults)
        let client = ReleaseControlFlagStateRecordingClient(
            status: ReleaseControlStatus(
                provider: .optimizely,
                connectionState: .connected,
                environmentKey: "development",
                userId: "anonymous-install",
                datafileURL: URL(string: "https://cdn.optimizely.com/datafiles/test.json")
            ),
            decisions: [
                .authenticationFeature: ReleaseControlDecision(
                    key: .authenticationFeature,
                    isEnabled: true,
                    variationKey: "opt_in_available"
                )
            ]
        )
        let loader = ReleaseControlFlagStateLoader(
            keys: [.authenticationFeature],
            preferenceStore: preferenceStore
        )

        let availableStates = await loader.load(using: client)
        #expect(availableStates.count == 1)
        #expect(availableStates[0].key == .authenticationFeature)
        #expect(availableStates[0].stateLabel == "Available")
        #expect(!availableStates[0].preferenceToggleValue)

        preferenceStore.setPreference(.optIn, for: .authenticationFeature)

        let enabledStates = await loader.load(using: client)
        #expect(enabledStates.count == 1)
        #expect(enabledStates[0].stateLabel == "Enabled")
        #expect(enabledStates[0].preferenceToggleValue)
    }

    @Test
    func flagStateLoaderShowsOptInControlledFlagsAsAvailableUntilLocalOptIn() async throws {
        let defaults = try Self.defaults()
        let preferenceStore = ReleaseControlPreferenceStore(defaults: defaults)
        let client = ReleaseControlFlagStateRecordingClient(
            status: ReleaseControlStatus(
                provider: .optimizely,
                connectionState: .connected,
                environmentKey: "development",
                userId: "anonymous-install",
                datafileURL: URL(string: "https://cdn.optimizely.com/datafiles/test.json")
            ),
            decisions: [
                .planning: ReleaseControlDecision(
                    key: .planning,
                    isEnabled: true,
                    variationKey: "available"
                )
            ]
        )
        let loader = ReleaseControlFlagStateLoader(
            keys: [.planning],
            preferenceStore: preferenceStore
        )

        let availableStates = await loader.load(using: client)
        #expect(availableStates.count == 1)
        #expect(availableStates[0].stateLabel == "Available")
        #expect(!availableStates[0].preferenceToggleValue)

        preferenceStore.setPreference(.optIn, for: .planning)

        let enabledStates = await loader.load(using: client)
        #expect(enabledStates.count == 1)
        #expect(enabledStates[0].stateLabel == "Enabled")
        #expect(enabledStates[0].preferenceToggleValue)
    }

    @Test
    func flagStateLoaderKeepsLocallyOptedOutFeaturesVisible() async throws {
        let defaults = try Self.defaults()
        let preferenceStore = ReleaseControlPreferenceStore(defaults: defaults)
        preferenceStore.setPreference(.optOut, for: .planning)
        let client = ReleaseControlFlagStateRecordingClient(
            status: ReleaseControlStatus(
                provider: .optimizely,
                connectionState: .connected,
                environmentKey: "development",
                userId: "planning-poc-user-a",
                datafileURL: URL(string: "https://cdn.optimizely.com/datafiles/test.json")
            ),
            decisions: [
                .planning: ReleaseControlDecision(
                    key: .planning,
                    isEnabled: true
                )
            ]
        )
        let loader = ReleaseControlFlagStateLoader(keys: [.planning], preferenceStore: preferenceStore)

        let states = await loader.load(using: client)

        #expect(states.count == 1)
        #expect(states[0].key == .planning)
        #expect(states[0].preference == .optOut)
        #expect(states[0].stateLabel == "Off")
        #expect(!states[0].preferenceToggleValue)
    }

    @Test
    func noopClientHidesUnavailableFlagStatesWithoutPreference() async {
        let client = NoopReleaseControlClient(reason: "Optimizely SDK key is not configured")
        let loader = ReleaseControlFlagStateLoader(keys: [.planning])

        let states = await loader.load(using: client)

        #expect(states.isEmpty)
    }

    @Test
    func flagStateLoaderHidesDisabledOfflineDecisionsWithoutPreference() async {
        let client = ReleaseControlFlagStateRecordingClient(
            status: ReleaseControlStatus(
                provider: .optimizely,
                connectionState: .offline,
                environmentKey: "production",
                userId: "anonymous-install",
                datafileURL: URL(string: "https://cdn.optimizely.com/datafiles/test.json"),
                reason: "Network unavailable"
            ),
            decisions: [
                .planning: ReleaseControlDecision.disabled(.planning, reason: "Optimizely decision disabled")
            ]
        )
        let loader = ReleaseControlFlagStateLoader(keys: [.planning])

        let states = await loader.load(using: client)

        #expect(states.isEmpty)
    }

    @Test
    func flagStateLoaderRefreshesProviderBeforeLoadingStates() async {
        let client = ReleaseControlFlagStateRecordingClient(
            status: ReleaseControlStatus(
                provider: .optimizely,
                connectionState: .connected,
                environmentKey: "development",
                userId: "planning-poc-user-a",
                datafileURL: URL(string: "https://cdn.optimizely.com/datafiles/test.json")
            ),
            decisions: [
                .planning: ReleaseControlDecision(
                    key: .planning,
                    isEnabled: true,
                    variationKey: "variant_a"
                )
            ]
        )
        let loader = ReleaseControlFlagStateLoader(keys: [.planning])

        let states = await loader.refresh(using: client)

        #expect(await client.refreshCount == 1)
        #expect(states.count == 1)
        #expect(states[0].stateLabel == "Available")
        #expect(states[0].variationLabel == "variant_a")
    }

    @Test
    func launchReadinessRefreshesProviderBeforeFeatureDecisionsResolve() async throws {
        let defaults = try Self.defaults()
        let client = ReleaseControlLaunchReadinessRecordingClient()
        let readiness = ReleaseControlLaunchReadiness()

        let beforeLaunch = await client.decision(for: .feedbackFeature)
        #expect(!beforeLaunch.showsFeedbackNavigation)

        let status = await readiness.prepare(using: client, settingsDefaults: defaults)
        let afterLaunch = await client.decision(for: .feedbackFeature)

        #expect(await client.refreshCount == 1)
        #expect(status.connectionState == .connected)
        #expect(afterLaunch.showsFeedbackNavigation)
        #expect(defaults.string(forKey: ReleaseControlSettingsKey.connectionState) == "Connected")
    }

    @Test
    @MainActor
    func launchReadinessPostsNotificationAfterProviderRefresh() async throws {
        let client = ReleaseControlLaunchReadinessRecordingClient()
        let readiness = ReleaseControlLaunchReadiness()
        let notificationCenter = NotificationCenter()
        let recorder = ReleaseControlNotificationRecorder()
        let observer = notificationCenter.addObserver(
            forName: ReleaseControlLaunchReadiness.didPrepareNotification,
            object: nil,
            queue: nil
        ) { _ in
            recorder.record()
        }

        _ = await readiness.prepare(
            using: client,
            settingsDefaults: try Self.defaults(),
            notificationCenter: notificationCenter
        )

        notificationCenter.removeObserver(observer)
        #expect(recorder.count == 1)
    }

    @Test
    func noopClientFallsBackToDisabledDecision() async {
        let client = NoopReleaseControlClient(reason: "Missing SDK key")

        let decision = await client.decision(for: .planning)
        let status = await client.status()

        #expect(decision.key == .planning)
        #expect(decision.isEnabled == false)
        #expect(decision.variationKey == nil)
        #expect(decision.reason == "Missing SDK key")
        #expect(status.provider == .none)
        #expect(status.connectionState == .unavailable)
        #expect(status.shouldShowInSettings == false)
    }

    @Test
    func optimizelyConfigurationBuildsInitialStatus() throws {
        let defaults = try Self.defaults()
        defaults.set("planning-poc-user-a", forKey: "OptimizelyUserID")
        let bundle = try Self.bundle(
            environmentKey: "development",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )
        let configuration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: defaults
        )

        let status = ReleaseControlStatus.optimizely(
            configuration: configuration,
            connectionState: .connecting
        )

        #expect(status.provider == .optimizely)
        #expect(status.providerDisplayName == "Optimizely")
        #expect(status.environmentDisplayName == "development")
        #expect(status.connectionDisplayName == "Connecting")
        #expect(status.userId == "planning-poc-user-a")
        #expect(status.userDisplayName == "planning-poc-user-a")
        #expect(status.datafileURL?.absoluteString == "https://cdn.optimizely.com/datafiles/N3fUggU4dsTjNh2ZYobf9.json")
        #expect(status.datafileDisplayName == "Configured")
        #expect(status.shouldShowInSettings)
    }

    @Test
    func optimizelyStatusPublishesNonSensitiveSettingsSnapshot() throws {
        let defaults = try Self.defaults()
        let status = ReleaseControlStatus(
            provider: .optimizely,
            connectionState: .connected,
            environmentKey: "development",
            userId: "planning-poc-user-a",
            datafileURL: URL(string: "https://cdn.optimizely.com/datafiles/N3fUggU4dsTjNh2ZYobf9.json")
        )

        status.publishSettingsSnapshot(to: defaults)

        #expect(defaults.string(forKey: ReleaseControlSettingsKey.provider) == "Optimizely")
        #expect(defaults.string(forKey: ReleaseControlSettingsKey.connectionState) == "Connected")
        #expect(defaults.string(forKey: ReleaseControlSettingsKey.environment) == "development")
        #expect(defaults.string(forKey: ReleaseControlSettingsKey.userId) == "planning-poc-user-a")
        #expect(defaults.string(forKey: ReleaseControlSettingsKey.datafileURL) == "Configured")
    }

    @Test
    func noopStatusPublishesSettingsSnapshotAsUnavailable() throws {
        let defaults = try Self.defaults()
        let status = ReleaseControlStatus.none(reason: "Optimizely SDK key is not configured")

        status.publishSettingsSnapshot(to: defaults)

        #expect(defaults.string(forKey: ReleaseControlSettingsKey.provider) == "None")
        #expect(defaults.string(forKey: ReleaseControlSettingsKey.connectionState) == "Unavailable")
        #expect(defaults.string(forKey: ReleaseControlSettingsKey.environment) == "Not configured")
        #expect(defaults.string(forKey: ReleaseControlSettingsKey.userId) == "Not configured")
        #expect(defaults.string(forKey: ReleaseControlSettingsKey.datafileURL) == "Not configured")
        #expect(status.userDisplayName == "Not configured")
        #expect(status.datafileDisplayName == "Not configured")
    }

    @Test
    func fakeClientCanRecordPocConversionEventsWithoutLiveOptimizely() async {
        let client = RecordingReleaseControlClient(
            decision: ReleaseControlDecision(
                key: .planning,
                isEnabled: true,
                variationKey: "variant_a",
                variables: ["placeholder_title": "Planning is warming up"],
                reason: nil
            )
        )

        let decision = await client.decision(for: .planning)
        await client.track(.planningFeatureOpened(variationKey: decision.variationKey))

        let trackedEvents = await client.trackedEvents

        #expect(decision.isEnabled)
        #expect(decision.stringValue(for: "placeholder_title") == "Planning is warming up")
        #expect(trackedEvents == [.planningFeatureOpened(variationKey: "variant_a")])
    }

    @Test
    func configurationUsesDevelopmentSDKKeyForDevelopmentEnvironment() throws {
        let bundle = try Self.bundle(
            environmentKey: "development",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )

        let configuration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: try Self.defaults()
        )

        #expect(configuration.sdkKey == "N3fUggU4dsTjNh2ZYobf9")
        #expect(configuration.environmentKey == "development")
        #expect(configuration.datafileURL?.absoluteString == "https://cdn.optimizely.com/datafiles/N3fUggU4dsTjNh2ZYobf9.json")
    }

    @Test
    func emptyBuildSettingValuesFallBackToDevelopmentEnvironment() throws {
        let bundle = try Self.bundle(
            sdkKey: "",
            environmentKey: "",
            userId: "",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )

        let configuration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: try Self.defaults()
        )

        #expect(configuration.sdkKey == "N3fUggU4dsTjNh2ZYobf9")
        #expect(configuration.environmentKey == "development")
        #expect(configuration.datafileURL?.absoluteString == "https://cdn.optimizely.com/datafiles/N3fUggU4dsTjNh2ZYobf9.json")
    }

    @Test
    func configurationUsesProductionSDKKeyForProductionEnvironment() throws {
        let bundle = try Self.bundle(
            environmentKey: "production",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )

        let configuration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: try Self.defaults()
        )

        #expect(configuration.sdkKey == "5ymi5jyxrLyMPFwCHjn28")
        #expect(configuration.environmentKey == "production")
        #expect(configuration.datafileURL?.absoluteString == "https://cdn.optimizely.com/datafiles/5ymi5jyxrLyMPFwCHjn28.json")
    }

    @Test
    func testFlightSharedVariablesResolveProductionSDKAndDatafile() throws {
        let bundle = try Self.bundle(
            sdkKey: "5ymi5jyxrLyMPFwCHjn28",
            environmentKey: "production",
            userId: "",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )

        let configuration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: try Self.defaults()
        )

        #expect(configuration.sdkKey == "5ymi5jyxrLyMPFwCHjn28")
        #expect(configuration.environmentKey == "production")
        #expect(configuration.datafileURL?.absoluteString == "https://cdn.optimizely.com/datafiles/5ymi5jyxrLyMPFwCHjn28.json")
        #expect(configuration.attributes["release_control_environment"] == "production")
        #expect(configuration.attributes["release_control_identity_source"] == "anonymous_installation")
    }

    @Test
    func explicitSDKKeyOverridesEnvironmentSelection() throws {
        let defaults = try Self.defaults()
        defaults.set("local-override-key", forKey: "OptimizelySDKKey")
        let bundle = try Self.bundle(
            environmentKey: "production",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )

        let configuration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: defaults
        )

        #expect(configuration.sdkKey == "local-override-key")
        #expect(configuration.environmentKey == "production")
        #expect(configuration.datafileURL?.absoluteString == "https://cdn.optimizely.com/datafiles/local-override-key.json")
    }

    @Test
    func configurationUsesExplicitUserIDForOptimizelyTargeting() throws {
        let defaults = try Self.defaults()
        defaults.set("planning-poc-user-a", forKey: "OptimizelyUserID")
        let bundle = try Self.bundle(
            environmentKey: "development",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )

        let configuration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: defaults
        )

        #expect(configuration.userId == "planning-poc-user-a")
    }

    @Test
    func explicitUserIDAddsNonSensitiveOptimizelyTargetingAttributes() throws {
        let defaults = try Self.defaults()
        defaults.set("planning-poc-user-a", forKey: "OptimizelyUserID")
        let bundle = try Self.bundle(
            environmentKey: "development",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )

        let configuration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: defaults
        )

        #expect(configuration.attributes["release_control_user_id"] == "planning-poc-user-a")
        #expect(configuration.attributes["release_control_identity_source"] == "explicit_override")
        #expect(configuration.attributes["release_control_environment"] == "development")
        #expect(configuration.attributes["auth_state"] == "test_override")
    }

    @Test
    func anonymousOptimizelyUserIDIsStableForTheSameInstallation() throws {
        let defaults = try Self.defaults()
        let bundle = try Self.bundle(
            environmentKey: "development",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )

        let firstConfiguration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: defaults
        )
        let secondConfiguration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: defaults
        )

        #expect(firstConfiguration.userId == secondConfiguration.userId)
    }

    @Test
    func anonymousUserIDAddsNonSensitiveOptimizelyTargetingAttributes() throws {
        let defaults = try Self.defaults()
        let bundle = try Self.bundle(
            environmentKey: "development",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )

        let configuration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: defaults
        )

        #expect(configuration.attributes["release_control_user_id"] == configuration.userId)
        #expect(configuration.attributes["release_control_identity_source"] == "anonymous_installation")
        #expect(configuration.attributes["release_control_environment"] == "development")
        #expect(configuration.attributes["auth_state"] == "anonymous")
    }

    @Test
    func githubLinkedIdentityAddsOnlySafeAuthStateAttribute() throws {
        let defaults = try Self.defaults()
        let bundle = try Self.bundle(
            environmentKey: "development",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )
        let identityStore = AppIdentityStore(defaults: defaults)
        identityStore.linkGitHubUser(id: 8752215, login: "daveboster", linkedAt: Date(timeIntervalSince1970: 100))

        let configuration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: defaults,
            identityStore: identityStore
        )

        #expect(configuration.attributes["auth_state"] == "github_linked")
        #expect(configuration.attributes["github_login"] == nil)
        #expect(configuration.attributes["github_id"] == nil)
    }

    @Test
    func configurationBuildsNonSensitiveDecisionDiagnostics() throws {
        let defaults = try Self.defaults()
        defaults.set("planning-poc-user-a", forKey: "OptimizelyUserID")
        let bundle = try Self.bundle(
            environmentKey: "development",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )
        let configuration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: defaults
        )

        let diagnostics = configuration.decisionDiagnostics(
            for: .planning,
            variationKey: "variant_a"
        )

        #expect(diagnostics["release_control_flag_key"] == "planning")
        #expect(diagnostics["release_control_variation_key"] == "variant_a")
        #expect(diagnostics["release_control_user_id"] == "planning-poc-user-a")
        #expect(diagnostics["release_control_identity_source"] == "explicit_override")
        #expect(diagnostics["release_control_environment"] == "development")
    }

    @Test
    func releaseControlDecisionCarriesDiagnosticsForLocalValidation() {
        let decision = ReleaseControlDecision(
            key: .planning,
            isEnabled: true,
            variationKey: "variant_a",
            variables: [:],
            diagnostics: [
                "release_control_flag_key": "planning",
                "release_control_user_id": "planning-poc-user-a"
            ],
            reason: nil
        )

        #expect(decision.diagnosticValue(for: "release_control_flag_key") == "planning")
        #expect(decision.diagnosticValue(for: "release_control_user_id") == "planning-poc-user-a")
    }

    @Test
    func anonymousOptimizelyUserIDDiffersAcrossInstallations() throws {
        let bundle = try Self.bundle(
            environmentKey: "development",
            developmentSDKKey: "N3fUggU4dsTjNh2ZYobf9",
            productionSDKKey: "5ymi5jyxrLyMPFwCHjn28"
        )

        let firstConfiguration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: try Self.defaults()
        )
        let secondConfiguration = ReleaseControlConfiguration.mainBundle(
            bundle: bundle,
            defaults: try Self.defaults()
        )

        #expect(firstConfiguration.userId != secondConfiguration.userId)
    }

    @Test
    func planningNavigationFollowsPlanningReleaseControlDecision() {
        let enabledDecision = ReleaseControlDecision(
            key: .planning,
            isEnabled: true,
            variationKey: nil,
            variables: [:],
            reason: nil
        )
        let disabledDecision = ReleaseControlDecision.disabled(.planning)

        #expect(enabledDecision.showsPlanningNavigation)
        #expect(disabledDecision.showsPlanningNavigation == false)
    }

    private static func defaults() throws -> UserDefaults {
        let suiteName = "ReleaseControlTests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suiteName))
    }

    private static func bundle(
        sdkKey: String? = nil,
        environmentKey: String,
        userId: String? = nil,
        developmentSDKKey: String,
        productionSDKKey: String
    ) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleaseControlTests-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        var info: [String: String] = [
            "CFBundleIdentifier": "dev.boster.expanse.release-control-tests",
            "OptimizelyEnvironmentKey": environmentKey,
            "OptimizelyDevelopmentSDKKey": developmentSDKKey,
            "OptimizelyProductionSDKKey": productionSDKKey
        ]
        if let sdkKey {
            info["OptimizelySDKKey"] = sdkKey
        }
        if let userId {
            info["OptimizelyUserID"] = userId
        }
        let infoURL = bundleURL.appendingPathComponent("Info.plist")
        #expect((info as NSDictionary).write(to: infoURL, atomically: true))

        return try #require(Bundle(url: bundleURL))
    }
}

private actor RecordingReleaseControlClient: ReleaseControlClient {
    private let storedDecision: ReleaseControlDecision
    private var events: [ReleaseControlEvent] = []

    init(decision: ReleaseControlDecision) {
        self.storedDecision = decision
    }

    func status() async -> ReleaseControlStatus {
        .none()
    }

    var trackedEvents: [ReleaseControlEvent] {
        events
    }

    func decision(for key: ReleaseControlKey) async -> ReleaseControlDecision {
        ReleaseControlDecision(
            key: key,
            isEnabled: storedDecision.isEnabled,
            variationKey: storedDecision.variationKey,
            variables: storedDecision.variables,
            reason: storedDecision.reason
        )
    }

    func track(_ event: ReleaseControlEvent) async {
        events.append(event)
    }
}

private actor ReleaseControlFlagStateRecordingClient: ReleaseControlClient {
    private let storedStatus: ReleaseControlStatus
    private let decisions: [ReleaseControlKey: ReleaseControlDecision]
    private var storedRefreshCount = 0

    init(
        status: ReleaseControlStatus,
        decisions: [ReleaseControlKey: ReleaseControlDecision]
    ) {
        self.storedStatus = status
        self.decisions = decisions
    }

    func status() async -> ReleaseControlStatus {
        storedStatus
    }

    var refreshCount: Int {
        storedRefreshCount
    }

    func refresh() async {
        storedRefreshCount += 1
    }

    func decision(for key: ReleaseControlKey) async -> ReleaseControlDecision {
        decisions[key] ?? .disabled(key, reason: "No fake decision configured")
    }

    func track(_ event: ReleaseControlEvent) async {
    }
}

private actor ReleaseControlDescriptorStateRecordingClient: ReleaseControlDescriptorClient {
    private let storedStatus: ReleaseControlStatus
    private let decisions: [String: ReleaseControlDescriptorDecision]
    private var storedRefreshCount = 0

    init(
        status: ReleaseControlStatus,
        decisions: [String: ReleaseControlDescriptorDecision]
    ) {
        self.storedStatus = status
        self.decisions = decisions
    }

    func status() async -> ReleaseControlStatus {
        storedStatus
    }

    var refreshCount: Int {
        storedRefreshCount
    }

    func refresh() async {
        storedRefreshCount += 1
    }

    func decision(for descriptor: ReleaseControlDescriptor) async -> ReleaseControlDescriptorDecision {
        decisions[descriptor.key] ?? .disabled(descriptor, reason: "No fake decision configured")
    }

    func track(_ event: ReleaseControlCustomEvent) async {
    }
}

private actor ReleaseControlLaunchReadinessRecordingClient: ReleaseControlClient {
    private var storedRefreshCount = 0

    var refreshCount: Int {
        storedRefreshCount
    }

    func status() async -> ReleaseControlStatus {
        ReleaseControlStatus(
            provider: .optimizely,
            connectionState: storedRefreshCount > 0 ? .connected : .connecting,
            environmentKey: "development",
            userId: "anonymous-install",
            datafileURL: URL(string: "https://cdn.optimizely.com/datafiles/test.json")
        )
    }

    func refresh() async {
        storedRefreshCount += 1
    }

    func decision(for key: ReleaseControlKey) async -> ReleaseControlDecision {
        if storedRefreshCount > 0 {
            return ReleaseControlDecision(key: key, isEnabled: true)
        }

        return .disabled(key, reason: "Provider has not started")
    }

    func track(_ event: ReleaseControlEvent) async {
    }
}

private final class ReleaseControlNotificationRecorder: @unchecked Sendable {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

private final class ReleaseControlPreferenceNotificationRecorder: @unchecked Sendable {
    private(set) var keys: [String] = []

    func record(_ notification: Notification) {
        guard let key = notification.userInfo?[ReleaseControlPreferenceStore.preferenceDidChangeReleaseControlKey] as? String else {
            return
        }

        keys.append(key)
    }
}
