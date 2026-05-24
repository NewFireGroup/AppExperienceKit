# AppExperienceKit

`AppExperienceKit` is a reusable Swift package for app-experience surfaces that
can be shared across Xcode app projects.

## Package-Owned Responsibilities

- Release history models and Version History UI.
- Feature Previews models, release-control client protocols, and release-control
  status UI.
- Feedback models, draft storage, issue rendering, feedback UI, GitHub client
  protocols, and local feedback history UI.
- Optional authentication models, local-authentication gate UI, and app-lock
  launch coordination.
- Generic host copy through `AppExperienceHostConfiguration`.

Package code must stay reusable. Do not add host-specific app names, GitHub
repository defaults, navigation state, release JSON files, Info.plist values,
Xcode build settings, signing settings, or target configuration to the package.

## Host-Owned Responsibilities

Host apps own app-specific wiring:

- Product display name and app-lock copy through an
  `AppExperienceHostConfiguration`.
- GitHub feedback owner, repository, and OAuth client ID through
  `GitHubFeedbackConfiguration` and the host app Info.plist.
- Optimizely SDK keys, environment keys, user overrides, and datafile URLs.
- Release resources such as `ReleaseHistory.json`, `VersionHistory.json`, and
  TestFlight text output.
- Navigation placement for Settings, Feature Previews, Feedback, and About or
  Version History surfaces.
- Xcode project settings, build settings, signing, entitlements, and app target
  resources.

## Adapter Boundary

The package exposes host-facing adapters instead of depending on app types:

- `AppExperienceHostConfiguration` supplies product copy used by reusable
  loading, lock, and settings surfaces.
- `GitHubFeedbackConfiguration` reads host bundle values when available, but it
  does not supply app-specific defaults from inside the package. Hosts must
  provide repository defaults or Info.plist values if GitHub submission should
  be available.
- `ReleaseControlClient` is the release-control adapter. Host apps choose
  `OptimizelyReleaseControlClient` or `NoopReleaseControlClient` at launch.
- `ReleaseControlDescriptor` lets host apps add app-owned release controls to
  Feature Previews without adding cases to the package-owned `ReleaseControlKey`
  enum. Pass package defaults plus host descriptors to
  `AppSettingsView(featurePreviewReleaseControls:)` or
  `ReleaseControlFlagStatesView(releaseControls:)`.
- `ReleaseControlCustomEvent` lets host apps track safe aggregate events for
  app-owned release controls without adding app-specific event cases to the
  package.
- `FeedbackAIClient`, `GitHubIssueClient`, `GitHubIdentityClient`, `HTTPClient`,
  `GitHubTokenStore`, and `LocalAuthenticating` keep external services
  injectable for tests and for future host apps.

## Validation

Use these checks when changing the package boundary:

```bash
swift test
swift build
```
