## [0.0.1] - 2025-05-14

- Initial release.
- Supports blocking/unblocking Android and iOS apps.
- Handles permission requests on both platforms.
- Added helper methods to check and request platform-specific permissions.


## [0.0.2] - 2025-05-21
- Added Dartdoc comments for public API

## [0.0.3] - 2025-05-21
- Added Dartdoc comments for public API
- Readme File updated for easy configuration 

## [0.0.4] - 2025-05-31
- Block Overlay Hide Issue Fixed
- Readme File updated for configuration 

## [0.0.5] - 2026-09-22
- Android: blocking no longer dies silently. The enforcement loop always
  re-schedules itself (a missing permission only pauses enforcement and never
  clears the blocking flag) and is re-posted on every service start.
- Android: the overlay stays up while the user remains in a blocked app. The
  foreground package is remembered between polls instead of being forgotten
  after 10 seconds without a new usage event.
- Android: `BlockAppService` is now a `specialUse` foreground service. The
  previous `dataSync` type is limited to 6 hours per day on Android 15+ and
  cannot be started after boot. Update the Play Console foreground-service
  declaration accordingly.
- Android: `blocAndroidApp()` now returns `bool` and refuses to start (returning
  `false`) when usage access or the overlay permission is missing.
- Android: `BootReceiver` only restores blocking when it was enabled and the
  permissions are still granted; service starts are guarded against system
  refusals instead of crashing the host app.
- Android: service diagnostics are logged under the `AppLimiter` logcat tag.
- Build: Kotlin 2.3 / compileSdk 36; explicit androidx.core and coroutines deps.
- Android: redesigned block screen in Shukr's look and feel — brand gradient,
  wordmark, glass card, Jost/Mulish typography (bundled, SIL OFL; see
  `android/font-licenses/`), plus "Back to home" and "Open <app>" actions.
