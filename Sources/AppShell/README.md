# AppShell

The composition root. Wires every other module into a single running app
and owns the top-level navigation, profile selection, and provider
registry.

## Responsibility

- `AppState` — the `@Observable @MainActor` aggregate root. Holds the
  `ProfilesModel`, the active `[ResolvedAccount]`, the `ProviderRegistry`,
  Trakt service, Top Shelf publisher, and the active settings models for
  the current profile. Orchestrates:
  - profile switching (`switchProfile`, `saveProfile`, `removeProfile`,
    `rebuildSettingsModels`),
  - Plex Home-user activation (`pendingPlexPINRequest`, `submitPlexPIN`,
    `cancelPlexPIN` — the PIN is never stored),
  - per-profile Trakt namespace swap (`updateTraktForActiveProfile`).
- `RootView` + `MainTabView` — the root SwiftUI hierarchy
  (Auth → ProfileSelection → MainTab). Lives here because it must depend
  on every feature module.
- `ProfileSelectionView` — hosts `FeatureProfiles.ProfilePickerView` and
  the create/edit sheet for both the launch picker and Settings.
- `SystemProfileBridge` — narrow seam onto the tvOS `TVUserManager` API
  (`shouldStorePreferencesForCurrentUser`) for the `user-management`
  entitlement.
- `AddAccountView` — first-run "add another server" flow that routes
  into `FeatureDiscovery` and `FeatureAuth`.
- `LibraryDiscoveryModel` — per-account "what libraries does this server
  expose?" coordination.
- `MediaItemActionCoordinator` — the cross-feature action bus (play,
  resume, mark watched, open detail) so any view can request an action
  without knowing the playback / detail routing.
- `PlaybackEngineComposition` — the **only** module that imports
  `EnginePlozzigen` (and any future engine packages). Builds the
  `EngineFactory` closure injected into `FeaturePlayback`, keeping the
  heavy on-device decode binaries out of every other module's dependency graph.
- `PlayerPresentation` handles Back only while preparing the initial playback
  version. Once it creates the player model, it removes that handler so the
  player's menus, controls, and video surface own their normal Back sequence.
- `AppInfo` — version / build / display-name helpers read from
  `Info.plist`.

## Invariants

- **Top Shelf actions retain their intent and owner.** Play opens the title then
  starts playback; More Info opens the same detail/episode-context destination
  without playback. Requests wait for signed-in admission and route through the
  active Home stack. Account-qualified links cannot fall back to another server,
  and cancellation or a superseding request rejects stale resolutions.

- **Missing sources are a recoverable route state.** Home, Watchlist, Search,
  library and series-context destinations show an unavailable state when their
  library provider no longer resolves. External Watchlist/Search details remain
  available without any enabled media server and keep their metadata/request
  behavior. An untagged library item may use the active primary
  provider; an explicit missing account never falls back to a different server.
  Classification and source selection use the same active-source snapshot so
  a stale index cannot send an external ID to a different server. Failed model
  construction is not cached; title, episode and season cache keys include their
  account and library origin inside the existing profile/credential scope.
  Player creation propagates missing-source failures into its visible error path.
  Online trailers bypass library version preparation and retain their dedicated
  provider even when no media-server account is enabled.

- **Mobile notification completion stays on the main actor.** The download
  notification delegate uses the explicit completion-handler entry point.
  Navigation is queued before completion; ignored and malformed notifications
  also complete exactly once on the main actor because UIKit may snapshot
  immediately afterward.

- **One root presentation at a time.** `RootPresentationCoordinator` retains the
  current native cover until its dismissal completes. Startup introductions,
  release notes, identity gates, synced-server prompts, and device setup wait
  rather than replacing one another. Automatic device offers wait for startup
  preparation; once visible, setup keeps confirmation, progress, errors, and
  success in that same cover until the user closes it. A profile authorization
  change stops credential transfer and leaves the error visible.

- **TV-to-phone setup QR.** The sender screen shows a three-minute
  `SyncSetupSourceInvite`. Scanning it opens the phone's existing receive flow,
  advertising the request UUID in Bonjour instead of broadcasting an iCloud
  offer. The TV matches that live request, then requires matching-code
  confirmation before sending credentials. This request has no
  credentials or public-key trust shortcut and cannot decode as the original
  receiver QR. Nearby-device labels inherit native button foregrounds so their
  codes remain readable when focus inverts the surface. The QR, nearby devices,
  and manual code entry stay on one page in distinct sections.

- **Bounded setup summaries.** Both sending and receiving use CoreUI's shared
  scrolling summary on TV and mobile. Group accounts by physical server, retain
  per-server transfer scope and pending sign-in state, and wrap full server and
  profile names. Headers scroll; Done/Continue remains reachable independently
  of the number of servers or profiles.

- **Visible pairing failures on both platforms.** Mobile automatic offers use
  one retained cover for confirmation, progress, retry and completion, waiting
  for existing root presentations. Sender authorization is rechecked during
  transfer; dismissing cancels the connection and any matching-code wait.
  Receivers stop advertising after failure and retain the error until an
  explicit retry. A failed TV-to-phone source QR requires a new scan.
  Sender retries keep the confirmed invitation pinned; a newly generated
  receiver code requires closing the old flow and accepting/scanning the new one.
  Matching-code confirmation is bounded to 60 seconds.

- **Device setup diagnostics.** Each attempt logs fixed role/route/stage/outcome
  categories and bounded elapsed time through `PlozzLog`, so manual diagnostics
  include pairing failures. With crash-reporting consent enabled, failures also
  reach Sentry automatically through `DeviceSetupDiagnostics`; no raw logs,
  device names, URLs, account IDs, codes, keys or credentials are uploaded.
  Failures are grouped by role/route/stage/reason and deduplicated to at most ten
  distinct reports per reporting session. Opt-out invalidates retained attempt
  callbacks. Explicit local cancellation/decline is not a failure report.

- **Composition root, not a feature.** This is the **only** module
  allowed to import all the others. Feature modules don't import
  `AppShell`.
- **Tokens stay in their stores.** `AppState` may *read* a session, but
  it never persists tokens itself — that's `FeatureAuth`'s job.
- **Provider-agnostic above the registry.** `AppState` resolves
  providers via `ProviderRegistry.provider(for:)`; nothing here
  switches on `ProviderKind` except for explicitly provider-specific UX
  (e.g. Plex Home-user PIN).
- **Profile-namespacing on switch.** Every per-user model must be
  rebuilt on profile change (`rebuildSettingsModels`) so settings,
  Trakt, and watched-state stay isolated.
  Tracker connection callbacks defer until every tracker is scoped and the
  watchlist reconciler matches the complete profile/identity/account scope.
  Authentication retries and native refreshes share the setup, PIN, and
  server-identity admission gates; callbacks never restart tracker scoping.

## Appearance onboarding

Apple TV first-run and new-profile setup share Theme, Navigation, and Home Layout
choices in that order. Each selection writes to the active profile's existing
settings model. Continue or Menu accepts the current selection; profile setup
is not complete until Home Layout is accepted.

Existing installations receive a device-local, one-time Home Layout chooser
after any pending navigation introduction and before release notes. The current
layout is preselected; dismissing does not reset it or change other profiles.
Finishing setup also completes these introductions, preventing a duplicate
prompt on first entry. iPhone and iPad retain their existing carousel layout.

`CoreUI.HomeLayoutOptionCard` supplies the same names and previews to onboarding
and Settings. Its illustrations omit navigation chrome, since Home layout and
navigation style are independent choices.

## Native navigation planning

Settings retains the last visible navigation shell while its style picker saves
the profile's new preference immediately. Construct the replacement chrome only
when leaving Settings: mounting a hidden, disabled native sidebar resets the
picker's focus. Opening and closing Settings without changing style keeps the
visited tabs and their state; a Settings-first launch does not mount hidden chrome.
Top-bar selection also prepares its nonpersistent library-navigation handoff
before a style change, so the first render cannot temporarily dismiss Settings.

Native tab builders capture the resolved selection and library entries before
constructing their children. The sidebar reuses that plan for content, labels,
and focus eligibility; lazy tab evaluations must not rebuild it per destination.
Recompute from current account visibility and profile layout when the shell
updates, rather than retaining a cache that could expose removed libraries.

Horizontal navigation offers individual libraries and All Libraries in the same
profile-scoped arranger as the sidebars. These shortcuts start in Hidden to keep
the top bar compact; Show opts them in using the existing saved visibility and
order. Automatic hiding is never persisted as a manual Hide choice. Each tab
retains its account-qualified destination and library root, so same-named
libraries remain distinct and only the visible stack consumes pending routes.

Home, Search, and Watchlist use shared, profile-scoped automatic visibility.
Live-only IPTV opens Live TV; IPTV movies and series expose Home and Search.
Search also remains available for configured Seerr discovery, and Plex keeps its
Home discovery surface. Library metadata comes from the existing bounded
navigation snapshot and library discovery, not a channel/title scan. Failed
accounts retain their last-known libraries; removed accounts cannot contribute.

An untouched Watchlist appears when the profile's hydrated local/native union
has items. Removing its last item does not evict its open page: it hides after
leaving, or on the next launch. Show and Hide are durable overrides; reordering
another row never converts automatic visibility into a manual preference.
Reset Navigation restores automatic defaults. Legacy hidden choices and
explicit whole-navigation arrangements are retained on decoding; an untouched
legacy default or library-only arrangement remains automatic. Runtime content
facts and the temporary open-page exception are never synced as preferences.

## Pinned sidebar remote navigation

At a visible pinned-navigation root, Back opens the menu on the current
destination. If already on Home, the next Back exits directly from the menu.
Otherwise, Back from the menu shows Home while keeping navigation open and focused
on its Home row; the following Back is left to tvOS to exit. Returning Home uses
the existing rendered-page handoff with a navigation focus target, so content never
takes focus and extra Back presses cannot exit before Home appears. Select or Right
still enters the page, where Back always opens navigation again. Leaving the active
scene releases menu focus so reopening starts in the content. Back
inside pushed pages and presentations still belongs to those surfaces. A hidden
Home destination is temporarily available for this explicit return without
changing the profile's hidden/order preferences. Native navigation and its
optional exit protection are unchanged.

`NavigationRailEdgeCatcher` passively observes arrow presses and indirect-touch
swipes. Left at an unresolved content edge opens the sidebar; Right at an
unresolved sidebar edge returns to the page. Both paths wait for native focus to
settle and do nothing if it moved or the sidebar's focus state changed. The Home
hero disables this fallback and requests entry at its own logical leading edge.
Unchanged focus is not sufficient evidence of unused input. Focus environments
conforming to `HorizontalNavigationInputOwning` keep horizontal adjustments,
and presented screens keep input away from the background rail. The native
Search controller remains eligible for its keyboard-edge handoff. Press, swipe,
and deferred Search callbacks recheck ownership before requesting navigation.

On tvOS, indirect touch-down and subsequent movement can use different coordinate
frames inside wide scrolling rows. `SwipeTravel` anchors at the first movement
sample, not touch-down; otherwise a left swipe from Continue Watching can look
like thousands of points to the right. The observer never recognizes, cancels,
or delays native touch gestures. Enable `PLZHFOCUS_STDOUT=1` for sidebar decisions
in the device console.

## Where to look first

- `AppState.swift` — the orchestration entry point.
- `RootView.swift` + `MainTabView.swift` — the root navigation.
- `PlaybackEngineComposition.swift` — how the Plozzigen (AetherEngine) engine
  is injected without leaking past this module.
