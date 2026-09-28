# FeatureHome

Home rows, item detail, series/season experience, and the online-trailer
fallback when the user's server has no attached trailer.

## Responsibility

- **Home** — `HomeView` + `HomeViewModel` render the focused tvOS rows:
  Continue Watching, Latest, Recently Added (per library). `HomeLayout`
  centralises sizing/spacing so all rows feel uniform.
- **Multi-account aggregation** — `HomeAggregator` fans out across the
  active account set (`[ResolvedAccount]`) so Home is a merged view
  across multiple servers / profiles. Uses the `MediaProvider`
  abstraction; never imports a specific provider module.
- **Item detail** — `ItemDetailView` + `ItemDetailViewModel` and
  `DetailHeroView` / `DetailExtrasView` render the cinematic full-bleed
  backdrop, logo, overview, ratings, cast, and Play/Resume button. Works
  for movies, episodes, and people.
- **Series** — `SeriesDetailView` + `SeriesResume` provide one stable
  series backdrop with focus-driven season tabs and an episode rail; the
  hero text updates as focus moves without distracting backdrop swaps.
  The compact logo above Seasons fits wholly inside its 200pt slot, including
  tall wordmarks; it does not use the full hero's flexible height allowance.
  This changes only artwork sizing, not season/episode focus geometry.
  While the browser reveals, only the outer page's native scrolling is held:
  horizontal episode focus stays live without provoking a second vertical
  scroll that lifts the logo. The page restores normal scrolling when the
  reveal finishes or is cancelled. Season pills, resting episode artwork,
  loading cards, and About share the same leading keyline; card spacing stays
  on the trailing side rather than indenting the artwork.
  The shared hero/browser motion uses a finite 0.9-second ease-in/ease-out,
  including logo and backdrop parallax. A spring's logical completion leaves
  several points of upward travel after the apparent landing, even when the
  outer page never scrolls.
  When pinned navigation hides on detail pages, horizontal rows draw through
  the empty side gutter to the screen edge, including focused episode artwork.
  The sidebar's mask changes without replacing the scroll view, preserving
  browse position and restoring the normal feather when navigation returns.
- **Library browsing** — `LibraryBrowseView` + `LibraryBrowseViewModel`
  for the per-library grid behind a Home row. Video libraries can switch
  among Browse, Collections, and Playlists when their provider advertises
  those capabilities. Plex, Jellyfin, and Emby discover existing video
  playlists by actual member/library intersection; a mixed playlist appears
  in each matching library but opens with its full authored order. Music
  playlists remain in `MusicProvider`. Unsupported sources (including Silo)
  do not advertise a video-playlist mode. Snapshots are bound to the provider
  account and refreshed on the first page, not during poster scrolling.
- **Trailers** — `OnlineTrailerSource` and `TrailerResolutionCache`
  handle the TMDb → YouTube fallback when the server has no attached
  trailer, by routing through `ProviderTrailers.YouTubeTrailerProvider`
  to surface a real `PlaybackRequest`.

## Showcase

`FocusHeroHomeView` keeps focus-driven movement and hero updates outside the
row-building view. Posters use the profile's full normal poster dimensions.
Preview headings have a 16pt inter-row spacer above them and more room below
before their cards. Only the active heading lifts, preserving its focus
clearance. That movement is a title-only drawing offset, not a rail
relayout. Native card/shadow drawing bounds remain intact.
Vertical movement uses a real `ScrollView` and UIKit's content-offset animation,
not a SwiftUI animation of the entire stack. Focus still chooses the row and its
measured bottom edge determines the exact destination, preserving the hero,
heading positions and next-row peek. Only the outer viewport's automatic
scrolling is disabled to avoid a second competing focus-reveal animation;
horizontal rows stay native and retain their focus and scroll state. The rows
remain in the original SwiftUI hierarchy, including navigation and accessibility.
Repeated updates to an unchanged destination never cancel an in-flight scroll,
and Reduce Motion moves directly to the same anchor.
The schedule badge sits 16pt above the logo slot; Showcase
constrains even tall logos to that slot rather than letting artwork grow into
the badge. The outgoing row fades over 64pt, with its bottom edge trimmed so no
strip remains above the next row. Earlier rows retain native Up eligibility;
making their entire mask transparent would break that navigation. Showcase's
backdrop uses wider leading and bottom gradients without lengthening its crossfade.
Crossfade is the only Showcase backdrop transition. The retired slide preference
is ignored when reading older settings without resetting the remaining choices.
Showcase's optional titles under cards remain in Customize Home > Home Layout;
they do not control title visibility elsewhere in the app.

Native poster layout slots use artwork size on both axes, rounding fractional
heights up so SwiftUI cannot round artwork down into its caption. TVUIKit's focus
margins settle after realization and draw outside that slot; feeding their
changing height into a lazy row shifts both the pinned row and hero during deep
horizontal scrolling. Hosted native-poster coverage checks this before and
after layout, and the Home UI regression traverses all 75 fixture cards.

Metadata belongs to the current Home view-model identity (profile, account set,
and credential generation), never a process-global cache. Cached details only
fill presentation gaps in the current row record: watched/resume state, source
identity, availability, and the selected series remain current. Background
enrichment publishes batches of at most four, and focus-driven loads share the
same deduplication. `FocusHeroMetadataTests` covers freshness and ownership;
`ShowcaseNavigationTests` covers geometry and native presented-frame hitches.
For existing-library coverage, the guarded physical driver supports
`--run-showcase-mixed`: it verifies on-screen Continue Watching, deep mixed-speed
paging, rapid reversals, sustained deep holds, stable vertical anchors, and
slow/fast tours through multiple real rows.
Its functional result is separate from `--measure-right` and
`--measure-vertical-burst` native hitch measurements. The driver accepts an
explicitly confirmed `PLOZZ_HOME_APP_CONFIGURATION=Debug-optimized` candidate
as well as Release; it never rebuilds or replaces the app under measurement.
Use optimized physical-device measurements for performance acceptance, not
simulator timing or passing navigation assertions alone.

## Invariants

- **Provider-agnostic.** All data flows through `MediaProvider`. No
  Jellyfin- or Plex-specific code paths above the provider seam.
- **Server art first.** External art (`MetadataKit`) is used as a
  fallback via `CoreUI.FallbackAsyncImage`, never as the default — the
  server's own backdrop/logo is always tried first.
  Shared logo views pair fallback lookups with the source item/account and
  metadata query. Memoized logos and in-flight tasks also distinguish artwork
  preference, so a missing server logo never gives unrelated titles a shared
  cache entry. A reused view rejects the previous title's image immediately.
- **`LoadState` everywhere.** Loading / empty / failure rendering uses
  `CoreUI.ContentStateView` so all surfaces feel identical.
- **No tokens in logs.** Provider calls log only opaque ids — never
  authorisation headers.

## Where to look first

- `HomeView.swift` + `HomeViewModel.swift` — the row composition.
- `HomeAggregator.swift` — multi-account fan-out.
- `ItemDetailViewModel.swift` + `SeriesDetailView.swift` — detail/series
  state coordination.
- `OnlineTrailerSource.swift` — the TMDb-keyless → YouTube fallback.
