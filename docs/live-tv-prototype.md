# Live TV prototype

A native, Debug-only Live TV destination for iterating on a physical Apple TV,
iPhone and iPad. It browses real public channels and plays their HLS streams through
Plozz's existing AetherEngine (`PlozzigenVideoEngine`) integration. It now lives
inside Plozz's actual navigation instead of replacing the application root.
Release navigation and onboarding remain unchanged.

## Run

Generate the project using the normal wrapper:

```sh
export GIT_CONFIG_PARAMETERS="'safe.bareRepository=all'"
tools/generate-project.sh
```

Open `Plozz.xcodeproj` and run a Debug **Plozz** build on Apple TV or
**PlozziOS** on iPhone/iPad. After normal profile/account setup, select **Live TV**
in navigation. Apple TV supports the top tabs, native sidebar and custom
navigation rail variations; iPhone/iPad expose the same destination in their
tab shell. Device installation must be authorized; a build alone does not
install anything.

For isolated physical-TV iteration, build a branded Debug app using the existing
per-branch build configuration. It has its own bundle ID, preferences and data;
normal Plozz remains installed and untouched. Cloud sync and Top Shelf are not
enabled for branded builds. A branded app therefore needs its own normal
profile/account setup. Once installed, launch that bundle explicitly:

```sh
xcrun devicectl device process launch --device <device-id> \
  <branded-bundle-id>
```

The old `--live-tv-prototype` and remembered prototype-entry preference no
longer bypass Plozz's root or its background services. The older prototype
schemes also open the normal app; enter Live TV through navigation.

Additional launch arguments:

- `--live-tv-5000`: repeat the real catalog into 5,000 clearly labeled rows for
  scrolling tests. These are copies, not 5,000 distinct stations.

The former `--live-tv-guide` flag is no longer needed: channels and their guide
are one screen, including when no listings exist.

The entry route, live host, UI and public test catalog are compiled out of
Release builds.

## Try

The preview loads the complete supplied US playlist, then the enabled XMLTV guides.
Channels become available before guide loading finishes. There is one unified
channel guide, not separate Channels and Guide tabs. It groups up to three
**Recently watched** channels first, then **Favorites**, then the full filtered
channel list. Empty groups are omitted. Recent and Favorite entries are
independent shortcuts: a channel can appear in both and always remains in the
main list. Each section/channel occurrence has its own stable row and focus ID.
Search, categories and view filters apply across every group.
Search, categories, sorting and Favorites survive opening the player,
returning to the guide and refreshing sources.
Favorites and recent channels are saved per Plozz profile and restored across
sessions. Initially empty or temporarily unavailable source catalogs do not
erase saved IDs. Unreadable preferences are not overwritten, and failed writes
offer a retry rather than displaying an unsaved change as successful.
Search/category state and guide-source selections remain session-scoped.
View preferences live in the app's **Settings > Live TV** page.
Earlier prototype builds did not store Favorites or Recents on disk, so there
is no prior in-memory history to migrate on the first updated launch.

- Browse, search names/numbers/categories/sources, filter and sort.
- Favorite channels through their context menu.
- Search transforms the current screen rather than opening a second results
  dialog. Apple TV uses the native inline search keyboard above the familiar
  channel/programme rows; iPhone/iPad replace the hero with an inline search field.
  Both use the same query and filtered catalog, not an extra eight-result list.
  The current category remains identified. Leaving Search restores the
  original guide occurrence and time position; the video stays in the same player.
  On Apple TV, Back works from both the native keyboard and the results.
  Search has a full-screen, transparent navigation host rather than an inset
  sheet. The old guide fades away, then the native search surface fades in
  without sliding down; closing reverses that handoff. Reduce Motion removes
  the fade timing. Temporarily opening playback or another sheet hides Search
  without discarding its query or results host.
  App navigation is suppressed before the TV keyboard opens and stays suppressed
  through closing and guide-focus restoration, so Back does not briefly open the
  native navigation menu or pinned rail.
  Live TV also participates in the profile's Hide or Reorder Navigation list,
  alongside Home, Search and the other destinations. Settings remains visible
  but can be moved. Press-and-hold Hide keeps focus at the vacated list position;
  Move Up/Down follows the moved item.
  Pinned navigation reveals its selected row before requesting native focus,
  including Settings or another destination below a long list's visible area.
  An open request expands the complete panel instead of leaving a thin backing
  at collapsed width. Collapsed icons have no panel behind them.
- Wide screens pin Search and an independently scrolling category list
  to the left of the guide. Search never scrolls away
  with either list. Select a category directly; Right returns to the remembered
  guide channel/program. Compact or short windows keep pinned horizontal controls.
  With pinned navigation visible, the Live TV controls also clear its title-safe
  margin; native top-bar/sidebar styles keep their tighter leading spacing.
  The selected category uses a checkmark rather than a second focused-looking
  box. Favorites are grouped in the guide, not a separate sidebar button.
  The More menu is gone: sorting, Auto preview, Favorites-only and guide-only
  preferences are in Settings > Live TV. Sources and Guide time remain
  directly available through channel/programme context menus; failed or empty
  imports also expose Sources beside Retry.
  On Apple TV, Back from a guide row focuses Search without scrolling the list.
  Back from the controls goes to the
  surrounding app navigation. Holding Select on a channel/program also opens
  its context menu with Search channels, Sources, Guide time when available,
  and Back to top. The sidebar's bottom clock remains removed.
  The channel/program context-menu Back to top action remains and does not
  reset the selected time.
- Compact category choices use an explicit navigation list with checkmarked
  selections, not nested system Picker presentations inside a sheet. Sorting
  uses the app's standard Settings controls.
- The guide sits in one rounded tray with roomier channel rows and
  quieter programme tiles. Logo plates, channel tiles and the outer tray use
  concentric radii derived from their insets. TV rows are 128 points tall,
  with full-height 200 x 128-point logo plates and 16-point row spacing.
  On first entry, focus moves to the first available channel once the playlist
  arrives; subsequent playback/Search returns keep their remembered position.
  The backing fills the complete station focus bounds, with the same corner
  radius and no outside gutter. Artwork fits inside without stretching.
  Plozz adds the light/dark backing based on logo contrast; source images can
  also contain their own baked-in background. Hero/search logo sizes remain
  independent of the full-row guide treatment.
  Station tiles show only the logo, or a name fallback when artwork is missing,
  rather than repeating names, numbers and badges beside it. Names and numbers
  remain searchable and available to accessibility; the focused channel's name
  and full programme title remain in the hero.
  No second surface surrounds the logo backing. Programme surfaces are quieter,
  with lighter-weight 26-point TV titles and the standard Plozz system font,
  not a separate rounded face.
  A small Liquid Glass surface anchors Search on the left; compact windows
  retain the glass control group. Programme cells do not create individual glass
  surfaces. Glass reduction preferences and Reduce Transparency use the existing shared
  fallbacks. Guide focus uses a crisp rounded outline and tonal fill, with a
  solid high-contrast treatment under increased contrast or Reduce Transparency.
  Logo tiles retain a contrasting outline above their opaque backing, including
  with accessibility contrast settings, rather than hiding focus behind the image.
  Focus and selection never swap the button's structural identity.
- The preview spans the screen width behind the upper guide. One continuous
  fade reaches the page colour before the video's lower edge; the date/time
  header no longer starts an opaque panel. The tray grows more opaque lower
  down, with a solid fallback for Reduce Transparency or increased contrast.
  Shared smooth edge masks dissolve rows underneath the fixed time header and
  programme cells at the horizontal viewport edges. The guide has no bottom
  fade and extends to the TV screen's bottom and trailing edges in both Search
  and normal browsing, without a trailing gutter or rounded trailing edge;
  the sidebar controls retain their safe inset. Touch layouts retain their
  bottom safe-area clearance. Each remaining fade ramps in only
  when content extends beyond that edge, keeping reached endpoints readable.
  Programme containers match the full height and corner radius of their station
  logo plates. Row spacing still separates channels; time widths and inner text
  padding are unchanged.
- **Sources** reports playlist entries, skipped entries, guide matches, listings,
  coverage dates and per-feed failures. Its toggles enable or disable the five
  preset guides; disabling one immediately removes its contribution. Results
  appear incrementally, and a failed feed does not block the remaining feeds.
  **Show channels with guide listings** applies the corresponding filter,
  making the populated rows easy to find.
- Guide retains all channels, even if none has a schedule. Unknown intervals
  remain honest gaps; they do not hide channels or shift later programs under
  the wrong time. Channel buttons still tune live without guide data.
  Missing listings show the channel name to the right of the logo in place of
  a program, without inventing a show title, start time or duration. Real
  listings still show their programme title. Entirely unlisted rows
  keep that label stationary rather than drawing an empty six-hour program.
  Loading, disabled, failed and unmatched-source diagnostics remain in Sources,
  not repeated on every channel. Program details identify the selected guide source.
- On wide screens, the station/logo column stays fixed while program rows scroll
  horizontally through a shared six-hour window. The time ruler stays above the
  vertical list and follows the same horizontal offset. Its leading label
  identifies the visible channel group instead of showing a date and buttons.
  Guide time in the context menu retains the date and Earlier/Now/Later controls.
  Earlier/Later shifts the
  window from one day back through seven days ahead, subject to source coverage.
  The time anchor does not jump at the half hour while browsing; **Now** recenters
  it on the current wall clock. A shared Now line extends through the guide.
  Focused programme details above the grid show the full title and broadcast times,
  including for very narrow cells.
- Wide-guide stations, programme cells and horizontal scrollers share one scaled
  row height. Short programmes and clipped edge intervals cannot enlarge an
  entire row through timestamp wrapping, including cells outside the viewport.
  Wide cells prioritize titles rather than repeating timestamps/progress bars in
  every row; very small slices show an ellipsis. Compact touch cards retain times.
  Their time widths remain accurate, and full titles/times remain available
  through accessibility and programme details.
- iPhone and narrow iPad windows use compact rows with horizontally browsable
  program cards; no-guide rows put the channel name beside its logo.
  Video stays above the scrolling list. Touch browsing does not automatically
  open streams; selecting a channel starts playback, and returning leaves its
  preview visible. Use Watch channel to reopen playback.
- Select a channel or its currently airing program to watch real video.
  Past/future programs open details, not a pretend future broadcast.
  The live host exposes real buffering,
  failure/retry and live transport state rather than a fabricated VOD timeline.
  Recently watched records only deliberate fullscreen viewing after the matching
  source is playing and has presented video. Automatic previews, failed startup
  and stale callbacks do not count. Revisiting moves a channel to the front.
  Next/Previous snapshots the filtered guide order, deduplicated by channel, when watching starts, so
  promoting a channel into Recents cannot make transport bounce between stations.
  This channel history never writes movie/episode progress or watched status.

### Required follow-up: channel scanning

Channel scanning is a committed product follow-up, deliberately **not implemented
in this UI pass**. After importing a source, offer an optional scan without
blocking browsing or playback; also expose manual scans/rescans through Sources
and the browsing controls.

Keep results per profile/source/channel and stream identity. Hide confirmed
broken links reversibly rather than deleting playlist entries, Favorites or
guide mappings. Provide results, Show hidden, Restore and Rescan actions. Leave
timeouts, offline checks, authentication/geo restrictions and unsupported
playback cases visible as uncertain; one failed request must not remove a channel.
An HTTP 200 master playlist alone is not evidence of a working HLS stream.

Use bounded concurrency, response sizes, request deadlines and retries, with
progress and cancellation. Fence results when a source refreshes or the profile
changes, and never log raw URLs or credentials. Start with imported IPTV links,
not network discovery or tuner-consuming Plex/Jellyfin/Emby scans. Scanning must
not commandeer the playing engine or interrupt the current channel.

### Audible previews and seamless viewing

On Apple TV, resting on a different channel for **600 ms** requests its preview.
Rapid scrolling cancels pending requests; moving between programs on the same
channel does not restart the delay or retune. The delay is **not** a stream
startup guarantee: network, source, keyframe and decoder startup follow it.
There is only one active player, with sound on while browsing. No second stream
is opened to fake an instant crossfade. Search, controls, sheets and inactive
scenes cancel pending focus-driven tunes.

Live video fills the upper backdrop rather than a boxed preview. A leading scrim
protects programme details and a continuous bottom fade blends through the
translucent upper guide into the solid page background.
The picture remains anchored while either guide axis scrolls. The backdrop
extends through the safe-area margins; only text and controls receive the
navigation rail's leading inset. Selecting a ready preview slides/fades the guide
away and expands the existing surface to unobscured, aspect-fit playback.
Back restores the guide's row, program, filters and time position; it does not
stop, reload or replace the engine. Reduced Motion removes the spatial animation.
On Apple TV, Search and surrounding navigation remain unavailable during the
focus handoff. The playing channel's currently airing programme receives focus
in the same Recent, Favorite or main-list occurrence used to start watching;
programme rollover selects the new programme, and missing listings fall back to
the channel. If a shortcut no longer exists, the same channel's main-list entry
is used instead. A changed channel or offscreen programme is brought into view.
Focus restoration waits for the row to mount and for native focus confirmation,
not merely an assigned focus binding. A bounded station fallback releases the
entry gates if it fails, so the guide cannot remain unreachable from Search.
Moving from the sidebar toward the guide reveals its remembered occurrence even
when that row was scrolled offscreen.
Returning from fullscreen keeps the chosen channel playing rather than retuning
on the first navigation press. **Auto preview** in Settings controls whether
focus-following resumes when Live TV is reopened; deliberate watching keeps
the current channel playing during that visit. The remote's Play/Pause also
works during browsing.
The normal tvOS player header has no Close button; Back returns to the guide.
Transport focus selects an available playback action instead of a removed
header target. Startup and interruption escape/retry controls remain available,
and iPhone/iPad retain their touch Close button.

Tuning another channel reuses the engine with a new, fenced source attempt.
Loading/failure states remain local and nonfocusable in the preview, with an
opaque placeholder until the new source actually produces a first frame.
Opening a failed preview exposes the existing full retry/close UI.
Leaving the Live TV destination releases playback and invalidates pending tunes,
including when a native tab keeps its view alive. App backgrounding retains the
existing foreground-only teardown/reload policy.

## Real inputs and artwork

The default inputs are:

- Playlist: `https://iptv-org.github.io/iptv/countries/us.m3u`
- Pluto TV US: `https://i.mjh.nz/PlutoTV/us.xml.gz`
- Samsung TV Plus US: `https://i.mjh.nz/SamsungTVPlus/us.xml.gz`
- Plex US: `https://i.mjh.nz/Plex/us.xml.gz`
- EPGShare US2: `https://epgshare01.online/epgshare01/epg_ripper_US2.xml.gz`
- EPGShare Plex: `https://epgshare01.online/epgshare01/epg_ripper_PLEX1.xml.gz`

The September 6, 2026 source snapshots import 1,468 stream entries across 28
primary categories, with 1,443 logo URLs. The multi-feed import provides listings
for 253 streams, compared with 70 in the original US2-only build. Evaluated at
2026-09-07 03:04 UTC, all 253 had current listings, with 11,257 programs retained.
The selected sources supply 185 Pluto, two Samsung, three Plex and 63 US2
schedules; EPGShare Plex supplies overlapping fallback data, not extra channels.
These counts describe those snapshots, not guaranteed availability or coverage.
The remaining 1,215 streams stay available without invented program information.

Playlist entries are not necessarily distinct stations: feeds can include
alternate resolutions and stream providers. Stable stream identities preserve
variants without duplicate row IDs. Channel logos come from `tvg-logo` metadata
in the [iptv-org catalog](https://github.com/iptv-org/iptv).
Channel and hero marks reuse `HeroLogoArtwork`: cached off-main preparation,
transparent/solid-margin trimming, ink-aware sizing, monochrome contrast and
colour-logo halos. A bounded fit contains the whole mark inside a larger slot
(126 x 72 points in TV rows, 112 x 64 on iPhone/iPad); measured ink chooses a light or dark plate.
Multicolour artwork is not recoloured. Failed/missing artwork keeps a readable
fixed-size text fallback. Loading artwork never changes the reserved row height.

The original nine-channel `LiveTVPrototypeCatalog` remains a small regression
fixture, not the app's default catalog or a channel limit.

Availability and regional restrictions may change. These are developer test inputs, not a
Plozz-provided channel service, broadcaster endorsement, or permission to
rebroadcast, record or redistribute content. No third-party image binaries
are committed.

Import does not certify that every stream plays. A reachable master alone is
not sufficient: inspect its media playlist and segments, then exercise actual
device playback. Playlist request headers pass through the live host to Aether,
including retries and automatic source resets.

For example, ABC News Live 1's published master returned HTTP 200 on September 7,
2026, while all ten advertised media playlists returned HTTP 404. A guide match
or a valid master cannot make those missing media playlists playable. The
prototype keeps the supplied channel identity rather than silently substituting
a different ABC feed.

Guide loading and parsing run outside the main actor. Listings are associated
with imported channel identities, not synthetic layout scenarios. Unknown or
ambiguous matches receive no schedule. Guide failure does not remove a working
playlist; failed refreshes preserve the last successfully imported data that
still belongs to current channels.

Matching first uses exact native Pluto IDs from recognized stream URLs, then
explicit guide IDs, verified aliases and unique display names. Provider guides
only use name matching for streams identified as that provider; similarly named
streams from unknown or different providers are not silently assigned a FAST
schedule. Explicit foreign Samsung stream origins are excluded from the US
guide even when the playlist's station ID ends in `.us`. Country, affiliate
and time-shift conflicts continue to prevent name-based matches. An unmatched
native Pluto ID is not replaced with a guessed same-name station.

Each stream receives one whole schedule, never interleaved programs from
different feeds. Stronger identity evidence wins. Equal-confidence matches
prefer a schedule with upcoming listings, then the source order shown above.
An unavailable refresh retains that source's last good data for current channels.
Source changes fence late network/parse results before reloading.

Compressed input, expanded XML, retained text and program counts are bounded.
The combined in-memory guide cache is also capped at 250,000 programs and
32 MiB of program title/subtitle text. Sequential feed loading limits transient
memory. Two streaming XML passes discover channel metadata before retaining
matched programs, supporting feeds that interleave channel declarations and
listings without keeping all unmatched programs in memory. Plain XML and gzip
are accepted. Normal external XMLTV DOCTYPE headers are accepted without
retrieving the DTD; entity declarations remain rejected.
Custom-source onboarding and persistent guide caching are not exposed.

## Boundaries

General source onboarding, manual guide mapping, Plex/Jellyfin/Emby tuner
adapters, generated library channels, profile persistence/sync, PiP, AirPlay
integration, parental policy and recording management remain planned. This
iteration connects selectable public guide presets, not a finished multi-source
account manager. Many streams still lack a confidently identified schedule;
more name guesses are not a substitute for accurate provider/region mapping.

The normal shell owns account/profile models; the Live TV feature does not
create a second account or profile stack. The small
`FeaturePlayback.LiveChannelPlayerView` hosts the existing real engine without
constructing the VOD `PlayerViewModel`, media-provider reporting sessions, resume
writers or trackers. This avoids incorrectly treating an endless channel as a
movie while leaving ordinary library playback unchanged. The app shells inject the
player into `FeatureLiveTV`; UI feature modules do not import one another.
The app also injects the `LiveChannelEngine` implementation into the host, so
`FeaturePlayback` does not depend back on `EnginePlozzigen`. Engine initialization
failures are visible; the prototype never silently substitutes direct AVPlayer.

The paired `FeatureLiveTV` / `FeatureLiveTVCore` types are explicitly named
`LiveTVPrototype*`; they are not a final provider API. The core's synthetic
30-channel fixture catalog remains for deterministic guide/filter/state tests,
separate from the real catalog used by the app.

## Live activity and diagnostics

The centered activity indicator is owned by `LiveChannelPlayerModel` and driven
by AetherEngine's typed `playbackPhase`, gated on
`hasFirstFrameReadyForDisplay` for initial video. Connecting, buffering, seeking
and reconnecting are distinct. The host no longer reconstructs engine state
from AVPlayer transport hints or a second playback-clock classifier.

TV controls keep one stable set of focus targets. Native glass supplies its own
focus appearance: button styles must not switch in response to `FocusState`,
which replaces the focused control and can stall focus/layout resolution.
Close receives focus when controls mount, without waiting for the stream load.
The connecting indicator does not intercept input. On-device regression checks
must include video rendering and Back/Close while a channel is still connecting;
the headless package test runner has no window scene to exercise TV focus.

Live loads use `isLive: true`, the stable `.standard` join profile and native
remote HLS with Aether's compatibility fallback. A native HLS route still uses
AVPlayer internally; Aether owns route selection, engine state and recovery.
The host uses actual live seekable ranges and Aether's Go Live API, never a
fabricated movie timeline or a guessed seek target.
Native HLS uses the origin's actual sliding window; no local DVR duration is
invented. If compatibility recovery switches to ingest without a DVR window,
timeshift controls disable rather than promising unavailable rewind.

The host subscribes to `liveSourceReset` before loading. A fixed public channel
reopens the same URL, with one automatic retune in flight, at least 20 seconds
between automatic attempts and at most three per channel-viewing session.
Duplicate signals coalesce, pause/inactivity defers recovery, and exhaustion is
visible. Two manual retries remain available; they do not replenish automatic
recovery's budget. Startup is bounded at 30 seconds and sustained activity/stall
at 60 seconds, leaving room for Aether's own recovery before failing visibly.

This prototype is foreground-only. Inactivity pauses; actual background entry
stops its engine, and foreground return opens a fresh live session. A user-paused
channel stays paused until explicitly resumed. Stop, failure, backgrounding and
replacement invalidate outstanding loads and seeks. Ordinary VOD playback and
its lifecycle remain unchanged.

Debug diagnostics use the existing `HandoffDiagnostics` bounded playback journal
and `PlozzLog` recent-log ring, tagged `LIVE_TV` with `engine=AetherEngine`.
Snapshots include typed playback phase, actual video route, first-frame readiness,
playback/buffered positions, behind-live time and seekable bounds. Changes are coalesced to at most one
snapshot per second; steady playback emits a heartbeat every ten seconds.
Lifecycle and classified failure events are also recorded. Correlation uses a
random session ID, not a channel name, locator or credential. Error text and
raw URLs are never included in these new events.

Committed focus previews record monotonic `settleMs` separately from the
player's tune-to-first-frame timing. A canceled focus request emits no tune
event. Startup timings describe actual first-frame readiness, not merely a
manifest response or successful `load` return.

The journal is `Library/Caches/Plozz/playback-trace.log` (64 KiB limit).
Use existing in-app diagnostics export when available. Do not copy the active
tvOS app container, attach a debugger, or relaunch with `--console` during
someone's viewing without authorization: these can interrupt playback.
The existing `PlozzigenVideoEngine` log mirror is reused; the live host installs
no competing `EngineLog.handler`.

Terminal live errors retain Aether's typed `PlaybackErrorInfo` classification.
Explicit source HTTP refusals, connection failures, rate limiting and decoder
failures receive distinct channel-specific copy, rather than generic media-server
or sign-in instructions. Native AVFoundation failures do not imply a particular
HTTP status unless the engine actually supplies it. Bounded failure diagnostics
include an allowlisted error kind/domain and numeric code; messages are not
regex-parsed for classification, and raw locators are not added to those fields.

Run the focused model and native layout tests through the existing simulator runner:

```sh
tools/run-tests.sh FeatureLiveTVTests FeatureLiveTVCoreTests FeaturePlaybackTests EnginePlozzigenTests
```
