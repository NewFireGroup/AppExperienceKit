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

## Validation

```bash
swift test
swift build
```

See [docs/APP_EXPERIENCE_KIT.md](docs/APP_EXPERIENCE_KIT.md) for adapter
boundary guidance.
