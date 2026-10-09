# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

iOS SwiftUI app (bundle `com.pskmoons.meteocat`, Swift 5, iOS 18 target) showing observed weather data from Meteocat's XEMA station network (Catalonia). Single Xcode project with one unit test target (`meteocatalfTests`).

## Commands

Run from the repo root. Scheme is `meteocatalf`; dependencies are SwiftPM (Firebase, Kingfisher, SDWebImage + SVG coder, SwiftSoup, and `Alfy`, the author's own package at `github.com/vilapuigvila/Alfy`).

```
open meteocatalf.xcodeproj
xcodebuild -project meteocatalf.xcodeproj -scheme meteocatalf -destination 'platform=iOS Simulator,name=iPhone 15' build
```

Unit tests (XCTest, run in the app host; no lint command exists). Use the dedicated `Claude-Test` simulator rather than whichever one is booted, since running tests reinstalls the app and wipes its state:

```
xcodebuild test -project meteocatalf.xcodeproj -scheme meteocatalf -destination 'platform=iOS Simulator,name=Claude-Test'
# one class: add  -only-testing:meteocatalfTests/StationMonthTests
```

UI flow (Maestro, needs network, wipes app state): with `Claude-Test` booted and the app installed, run `maestro --device 942A8639-020A-4121-B65C-C85BFDABD70D test --test-output-dir <dir> .maestro/favorites_detail_modal.yaml`; the screenshot lands under `<dir>`.

Launch: once the app is active, `LaunchLocationPermission` (wired in `TabBarViewModel`, skipped under XCTest) ensures the stations list via the shared `StationsListInteractorImpl.ensureStationsAvailable()` and, only if CoreLocation is `notDetermined`, asks "When In Use" permission (never reads the location); flow: `maestro --device 942A8639-020A-4121-B65C-C85BFDABD70D test --test-output-dir <dir> .maestro/launch_location_permission.yaml` (needs network, build with `xcodebuild build` first and `xcrun simctl install` the `Debug-iphonesimulator` app, since `test` builds elsewhere).

Nearest station: on the empty My Station tab (source `.homeStation` only), `NearestStationSuggester` (`HomeStation_Tab/NearestStation.swift`) offers the closest operating station (open `states` entry with code 2) when location permission is already granted (one-shot read, never asks); wired in `TabBarViewModel`, off under XCTest; flow: `.maestro/nearest_station_suggestion.yaml` (`location: inuse`, `setLocation`).

My Station header: on the My Station tab (`.homeStation` only) the interactor fetches `ServerData.request(.curentWeather(code: cityCode))` after the day is on screen and the header shows "Temperatura actual" with that reading and the weather icon (`station.currentWeatherIcon`); until it arrives, or if it fails, it shows "Temperatura mitjana" as before (and the average row stays out of the list); detail and modal are unchanged; flow: `.maestro/my_station_current_temp.yaml`.

Widget: target `meteocatalfWidget` (Home Station widget: current temperature and today's max/min) reads a snapshot from the App Group `group.com.pskmoons.meteocat`; `meteocatalf/WidgetShared/` (Foundation only) is compiled into both targets. The app feeds the snapshot: `HomeStationWidgetUpdater` from the My Station interactor, and `HomeStationWidgetRefresher` on every activation. The widget never touches the network and re-reads every 30 min. Both app-side pieces are off under XCTest. Tests: `HomeStationWidgetTests`.

Loading: one component, `SignalLoader` (`Components/SignalLoader.swift`, square orange drops falling onto an ink line, drawn in a `Canvas`), used by every screen that waits: `SignalLoader("Loading stations")` centred, `SignalLoader(.compact, caption:)` over a map. With Reduce Motion it shows one still frame. Don't add other spinners; the data is fast, so the loader shows for a moment and `.maestro/loader.yaml` checks that it never stays.

Radar tab (`Views/WeatherMap_Tab/`): a MapKit map with RainViewer's radar as `MKTileOverlay` + `MKTileOverlayRenderer`, the last two hours as frames (a new image every 10 minutes) with play and a time slider. `ServerData.request(.radarMaps)` reads `api.rainviewer.com/public/weather-maps.json` (the host and one `path` per frame), tiles are `{host}{path}/256/{z}/{x}/{y}/2/1_0.png`. Things that are easy to get wrong: RainViewer has no tiles beyond zoom 7 and answers a "Zoom Level Not Supported" picture with a 200, and MapKit does not stretch tiles, so `RemoteTileOverlay` loads the z7 tile and crops it for closer zooms (`maximumZ` is 7 + 4); the colour scheme in the URL makes no difference on the free tier; a renderer that starts at alpha 0 never loads tiles, so hidden frames sit at a hair above 0; tiles go through `TileLoader` (few connections, retries, memory cache). RainViewer's terms: free for personal or educational use only, the source must be mentioned with a link (the controls show one), and they do not guarantee availability: check them before an App Store release. If it can't be reached the tab shows "Radar unavailable" with Retry. The map also shows the user (`HeadingLocationView`: an orange square, a wedge toward where the phone points, and the compass point, e.g. `NW 315°`; the wedge and label need a compass, so the simulator shows only the square), centres on the first location fix, and has a button to come back to it; location and compass run only while the tab is on screen, and only if permission was already granted at launch. Flow: `.maestro/radar_tab.yaml`. The scheme runs Thread Sanitizer, and MapKit's own Metal renderer crashed under it in the simulator in some runs with this tab open (the stack is inside MapKit): if that happens, build with `ENABLE_THREAD_SANITIZER=NO`.

Tests cover the day/cache rules, the month maths, the HTML parsing and the SwiftData cache (against an in-memory database). Adjust simulator names to what `xcrun simctl list devices` shows locally.

`GoogleService-Info.plist` is checked in and `FirebaseApp.configure()` runs at launch (`meteocatalfApp.swift`), so Crashlytics is always active.

## Architecture

Each tab under `meteocatalf/Views/<Feature>_Tab/` follows the same Clean-Swift-style split. Read one (Favorites is the cleanest) to see the pattern:

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

**Error reporting**: use `nonFatalCrashlytics(condition, message, domain:)` (defined in `meteocatalfApp.swift`) instead of bare asserts. It logs a non-fatal to Crashlytics and also `assert`s in DEBUG, so a failing condition will trap in debug builds.

The Forecast tab (`Views/Forecast_Tab/`) exists but is commented out of `TabBarView`.

## Conventions

- 4-space indent, `// MARK:` to separate concerns, feature-scoped files named like `FavoritesViewModel.swift` / `Forecast.MainView.swift`.
- Short, imperative, behavior-focused commit messages (e.g. `keep favorites after update stations`). PRs: brief summary, how it was tested (device/simulator + iOS version), screenshots for UI changes.
- Debug `print`s in this codebase are prefixed (`avp -`, `avpv -`); follow that when adding temporary logging.

## Known issue

The Meteocat API key is hardcoded in `Network/Requester.swift` (`meteocatToken`) and in `scripts/meteocat_metadata.sh`, which is a committed secret. Don't copy it into new files; move it to config if you touch that code.
