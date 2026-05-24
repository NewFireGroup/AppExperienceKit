# Changelog

All notable changes to `AppExperienceKit` are documented here.

This project uses semantic versioning. While the package is below 1.0, minor
releases may include source-breaking API changes as the public adapter surface
stabilizes. Patch releases should remain source-compatible within the same
minor version.

## 0.1.2 - 2026-05-24

- Added host-defined release-control descriptors so apps can extend Feature
  Previews without adding app-specific keys to AppExperienceKit.
- Added descriptor-based preference, decision, state loading, Settings, Feature
  Previews, and custom aggregate-event APIs while preserving existing
  `ReleaseControlKey` APIs.

## 0.1.1 - 2026-05-24

- Added GitHub Actions CI for Swift package validation.
- Added Dependabot coverage for GitHub Actions updates.
- No API or runtime behavior changes.

## 0.1.0 - 2026-05-24

- Initial public Swift package release.
- Added reusable release history, feature preview, feedback, local
  authentication, and host adapter surfaces.
- Published under the MIT License.
