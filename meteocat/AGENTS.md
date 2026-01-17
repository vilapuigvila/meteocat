# Repository Guidelines

## Project Structure & Module Organization

Paths below are relative to the repo root.

- `meteocat.xcodeproj/`: Xcode project (open this to build/run).
- `meteocat/`: main app sources.
  - `meteocat/meteocatApp.swift`: app entry point and Firebase setup.
  - `meteocat/Views/`: SwiftUI UI, organized by feature tab (e.g. `Views/Favorites_Tab/`).
  - `meteocat/Components/`: reusable UI pieces and loaders.
  - `meteocat/Network/`: API/request logic (see `Network/Requester.swift`).
  - `meteocat/DTO/` and `meteocat/Model/`: API payloads and domain models.
  - `meteocat/UserPreferences/`: persisted user settings.
  - `meteocat/Assets.xcassets/` and `meteocat/Preview Content/`: images and preview-only assets.

## Build, Test, and Development Commands

Use Xcode (recommended): `open meteocat.xcodeproj`, select scheme `meteocat`, Run.

CLI equivalents (from repo root):

- Build (simulator): `xcodebuild -project meteocat.xcodeproj -scheme meteocat -destination 'platform=iOS Simulator,name=iPhone 15' build`
- Run tests (only if/when a test target exists): `xcodebuild -project meteocat.xcodeproj -scheme meteocat -destination 'platform=iOS Simulator,name=iPhone 15' test`

## Coding Style & Naming Conventions

- Swift/Xcode defaults: 4-space indentation, `PascalCase` for types, `camelCase` for members.
- Prefer feature-scoped files under `Views/<Feature>_Tab/` and keep the existing naming pattern like `FavoritesViewModel.swift` or `Forecast.MainView.swift`.
- Use `// MARK:` to separate concerns consistently with existing files.

## Testing Guidelines

- Current repo has no XCTest suite checked in. If adding one, use XCTest and name files `SomethingTests.swift` under a `*Tests/` target.
- Favor unit tests for `Network/` parsing and view-model state mapping.

## Commit & Pull Request Guidelines

- Commit messages in history are short and descriptive; keep them imperative and behavior-focused (e.g. `keep favorites after update stations`).
- PRs: include a brief summary, how you tested (device/simulator + iOS version), and screenshots/GIFs for UI changes.

## Security & Configuration Tips

- Don’t commit secrets (API keys, tokens). Prefer env/xcconfig-driven configuration for Meteocat and Firebase.
- `GoogleService-Info.plist` is required for Firebase; treat it as configuration and avoid sharing production credentials.
