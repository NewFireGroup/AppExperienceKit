# AppExperienceKit

`AppExperienceKit` is a reusable Swift package for app experience surfaces that
can be shared across Xcode app projects.

## Package Scope

- Public/internal release history models and Version History UI.
- Feature Previews models, release-control adapters, and status UI.
- Feedback models, draft storage, issue rendering, feedback UI, and client
  protocols.
- Optional authentication models, local-authentication gates, and app-lock
  launch coordination.
- Generic host copy through `AppExperienceHostConfiguration`.

Host apps own product names, release JSON resources, Optimizely keys, GitHub
repository defaults, navigation placement, build settings, signing, and target
resources.

## Installation

Use Swift Package Manager:

```swift
.package(url: "https://github.com/NewFireGroup/AppExperienceKit.git", from: "0.1.1")
```

For apps that need tighter pre-1.0 stability, pin to the current minor release
or an exact revision.

## Validation

```bash
swift test
swift build
```

See [docs/APP_EXPERIENCE_KIT.md](docs/APP_EXPERIENCE_KIT.md) for adapter
boundary guidance.

## Versioning

`AppExperienceKit` uses semantic versioning. While the package is below 1.0,
minor releases may include source-breaking API changes as the public adapter
surface stabilizes. Patch releases should remain source-compatible within the
same minor version. See [CONTRIBUTING.md](CONTRIBUTING.md) for the pre-1.0
patch-versus-minor tagging policy.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
before broad API, UI, or adapter changes so the package boundary can stay
useful across host apps.

See [CHANGELOG.md](CHANGELOG.md) for release notes.

## License

`AppExperienceKit` is available under the MIT License. See [LICENSE](LICENSE).
