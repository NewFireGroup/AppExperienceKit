# Contributing

Thanks for helping improve `AppExperienceKit`.

## Scope

`AppExperienceKit` should stay reusable across host apps. Keep app-specific
configuration in the host app, including product names, GitHub repositories,
OAuth client IDs, Optimizely keys, release JSON resources, navigation
placement, signing, entitlements, and Xcode project settings.

Before broad API, UI, or adapter changes, open an issue describing the host-app
need and why the behavior belongs in the package instead of a consuming app.

## Development

Use the full Xcode toolchain when working locally:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

For a broader smoke check:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

## Pull Requests

- Keep pull requests focused and reviewable.
- Add or update tests for behavior changes.
- Update `README.md`, `docs/APP_EXPERIENCE_KIT.md`, or `CHANGELOG.md` when
  changing public APIs, setup, or package boundaries.
- Avoid adding host-specific defaults or example values from consuming apps.
- Use patch releases for source-compatible fixes within the current minor
  version.

## Release Notes

Release notes should be written for package consumers. Include user-facing API,
behavior, setup, validation, or dependency changes. CI-only or documentation-only
changes can be described as maintenance.

## Pre-1.0 Versioning

Use patch tags such as `v0.1.2` for source-compatible fixes within the current
minor version:

- bug fixes
- documentation or CI maintenance
- dependency updates that do not change host app integration
- additive APIs that do not change existing adapter expectations

Use minor tags such as `v0.2.0` when the package boundary changes:

- source-breaking public API changes
- adapter protocol changes
- changes that require host apps to update wiring or resources
- larger feature additions that need a new stabilization window

Package release pull requests must update `CHANGELOG.md`. Mark a pull request
as a package release by using a title that starts with `release:` or by applying
the `release` label.
