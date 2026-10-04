# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

iOS SwiftUI app (bundle `com.pskmoons.meteocat`, Swift 5, iOS 18 target) showing observed weather data from Meteocat's XEMA station network (Catalonia). Single Xcode project with one unit test target (`meteocatTests`).

## Commands

Run from the repo root. Scheme is `meteocat`; dependencies are SwiftPM (Firebase, Kingfisher, SDWebImage + SVG coder, SwiftSoup, and `Alfy`, the author's own package at `github.com/vilapuigvila/Alfy`).

```
open meteocat.xcodeproj
xcodebuild -project meteocat.xcodeproj -scheme meteocat -destination 'platform=iOS Simulator,name=iPhone 15' build
```

Unit tests (XCTest, run in the app host; no lint command exists). Use the dedicated `Claude-Test` simulator rather than whichever one is booted, since running tests reinstalls the app and wipes its state:

```
xcodebuild test -project meteocat.xcodeproj -scheme meteocat -destination 'platform=iOS Simulator,name=Claude-Test'
# one class: add  -only-testing:meteocatTests/StationMonthTests
```

UI flow (Maestro, needs network, wipes app state): with `Claude-Test` booted and the app installed, run `maestro --device 942A8639-020A-4121-B65C-C85BFDABD70D test --test-output-dir <dir> .maestro/favorites_detail_modal.yaml`; the screenshot lands under `<dir>`.

Launch: once the app is active, `LaunchLocationPermission` (wired in `TabBarViewModel`, skipped under XCTest) ensures the stations list via the shared `StationsListInteractorImpl.ensureStationsAvailable()` and, only if CoreLocation is `notDetermined`, asks "When In Use" permission (never reads the location); flow: `maestro --device 942A8639-020A-4121-B65C-C85BFDABD70D test --test-output-dir <dir> .maestro/launch_location_permission.yaml` (needs network, build with `xcodebuild build` first and `xcrun simctl install` the `Debug-iphonesimulator` app, since `test` builds elsewhere).

Nearest station: on the empty My Station tab (source `.homeStation` only), `NearestStationSuggester` (`HomeStation_Tab/NearestStation.swift`) offers the closest operating station (open `states` entry with code 2) when location permission is already granted (one-shot read, never asks); wired in `TabBarViewModel`, off under XCTest; flow: `.maestro/nearest_station_suggestion.yaml` (`location: inuse`, `setLocation`).

Tests cover the day/cache rules, the month maths, the HTML parsing and the SwiftData cache (against an in-memory database). Adjust simulator names to what `xcrun simctl list devices` shows locally.

`GoogleService-Info.plist` is checked in and `FirebaseApp.configure()` runs at launch (`meteocatApp.swift`), so Crashlytics is always active.

## Architecture

Each tab under `meteocat/Views/<Feature>_Tab/` follows the same Clean-Swift-style split. Read one (Favorites is the cleanest) to see the pattern:

- `<Feature>.swift`: namespace enum holding `ViewState`, `Representable` (UI-ready values), `Action` and view `ErrorView`.
- `<Feature>ViewModel.swift`: `ObservableObject` that maps the interactor's `Domain` into `ViewState` and forwards `Action`s to `interactor.useCase(...)`.
- `<Feature>Interactor.swift`: protocol plus `...Impl`. Owns a `CurrentValueSubject<Domain, Never>` exposed as a Combine `publisher`; entry point is `useCase(_:)`. Contains the business logic and nested `UseCase` and `ErrorReason` enums.
- `*.MainView.swift`: the SwiftUI view.

`Alfy` supplies shared infrastructure that is not in this repo: `DatabaseManager`/`DatabaseManagerProtocol` (SwiftData wrapper), `Requester` (HTTP), `RequestThrottleController`, `weakAssign`. When a symbol isn't found locally, it's probably there.

**Composition root**: `TabBarViewModel.init` creates the shared `DatabaseManager` with the SwiftData schema (`Model.Station`, `Model.InfoStationByDate`) and wires every tab's interactor to it. A new `@Model` type must be added to that list. `TabBarInteractorImpl` also kicks off a background prefetch of month-to-date data for favorite stations at app start.

**Data flow and caching**:
- `Network/ServerData.swift` (`ServerData.request(.service)`) is the only network entry point. Despite the official REST API existing, most data is **scraped from HTML** with SwiftSoup (`meteo.cat/observacions/xema` for the station list, which is parsed out of an inline `var meta = {...}` script; `/observacions/xema/dades?codi=…&dia=…` for daily tables; `m.meteo.cat` for current weather). Only `lastTemperature` uses the JSON API (`api.meteo.cat`, `x-api-key` header). Scraping is fragile: a markup change on meteo.cat breaks parsing, and the table row labels are Catalan strings matched after diacritic folding (e.g. `"temperatura maxima"`, `"precipitacio acumulada"` in `FavoritesInteractor.mapStationInfo`).
- Request cache: each request's TTL is set in `ServerData.makeRequest(for:now:)` to mirror how long the app keeps that data (`ServerData.CacheTTL`, `DayKey.cacheTTL`), and it needs `.ignoreServer` because Alfy otherwise expires entries by meteo.cat's 3-5 min `max-age`, so a longer `ttl` does nothing.
- `StationWorker` (in `Views/HomeStation_Tab/`, but used by Favorites and the prefetch too) is the cache layer: one `Model.InfoStationByDate` row per station and day (`dayKey` = yyyymmdd), stamped with the real download time (`createdAt`). `DayKey` (`StationMonth.swift`) holds the rules: meteo.cat summarises **UTC days**, so a day is final only if it was downloaded an hour after it ended; any other day is refreshed once it is an hour old. A day whose UTC start is in the future (first local hours after midnight) has no server page and surfaces as `StationWorker.ErrorReason.noData`. Concurrent requests for the same day share one download; the month fetch runs at most 4 requests at once, newest day first.
- Month tiles (`[StationDayInfo].summary()`): the average is the mean of daily means of **complete days only**; rain is the month-to-date sum including today. Don't build dates with `DateFormatter`/`Calendar.current` for requests: use `DayKey` (Gregorian, explicit time zone).
- SwiftData access goes through `@MainActor` helpers, so workers hop to the main actor for DB reads/writes while network calls run off it.
- `DTO.*` are network payloads, `Model.*` are persisted SwiftData models, `Favorites.Representable`-style structs are UI values. Favorite status lives on `Model.Station.isFavorite`.
- `UserPreferences/UserPreferences.swift`: `@UserDefault` property wrapper (JSON-encoded in `UserDefaults`) exposed through `UserSettings` statics, e.g. the home station and last-request timestamps.

**Error reporting**: use `nonFatalCrashlytics(condition, message, domain:)` (defined in `meteocatApp.swift`) instead of bare asserts. It logs a non-fatal to Crashlytics and also `assert`s in DEBUG, so a failing condition will trap in debug builds.

The Forecast tab (`Views/Forecast_Tab/`) exists but is commented out of `TabBarView`.

## Conventions

- 4-space indent, `// MARK:` to separate concerns, feature-scoped files named like `FavoritesViewModel.swift` / `Forecast.MainView.swift`.
- Short, imperative, behavior-focused commit messages (e.g. `keep favorites after update stations`). PRs: brief summary, how it was tested (device/simulator + iOS version), screenshots for UI changes.
- Debug `print`s in this codebase are prefixed (`avp -`, `avpv -`); follow that when adding temporary logging.

## Known issue

The Meteocat API key is hardcoded in `Network/Requester.swift` (`meteocatToken`) and in `scripts/meteocat_metadata.sh`, which is a committed secret. Don't copy it into new files; move it to config if you touch that code.
