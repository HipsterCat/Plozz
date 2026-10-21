# FeatureSettings

Mobile customization lists apply the shared native switch style to both standard
sections and grouped cards. Enabled switches keep the system green appearance
instead of inheriting the page's monochrome navigation tint.

The Settings screen and its detail pages. Profile-aware, integration-aware,
and the single place caption customization lives.

On tvOS, profile Appearance, Profile Lock setup, and Parental PIN setup use the
workspace's full-width destination layout, like subtitle styling. Their
two-column content must not be squeezed into the ordinary centered Settings
column. The stack retains the narrower parent page and its focus on return.

On tvOS, **Everyone → Top Shelf** reuses the native left/right `SettingsStepper`
for Continue Watching and Recently Added counts (4 by default, 1–20 each).
`TopShelfSettingsModel` owns one device-local preference shared across Plozz
profiles, excluded from profile transfer and sync. Household settings require an
adult profile; changing these counts never broadens the shelf's content access.
The page explains how top-row apps appear on the Apple TV Home Screen. The
default-on **Show Top Shelf** switch clears published media when disabled and
hides the count controls while retaining both counts for re-enabling.
The category uses a monochrome Home Screen icon with the shelf highlighted.
Posters / Full Screen reuse the shared `PreviewCard` focus and selection style
with schematic Home Screen previews. A slightly larger solid-white tile marks
the focused app, without an icon. Posters stays the default; full-screen explains
tvOS's swipe-up expansion and retains the same two item limits.

Playback > Advanced also contains **Dolby Vision FEL (experimental)** on TV,
iPhone and iPad. This is a profile-scoped, default-off preference, unlike the
device-wide external-player choice. It applies to new built-in on-demand sessions
and travels through profile settings transfer. The helper explains the added
GPU/memory cost and loss of Atmos objects and DTS:X height audio on the FEL route.
Live playback, shared players and muted previews do not opt in.
See [playback engines](../../docs/playback-engines.md#dolby-vision-fel) for eligibility
and output limits.

Playback > Advanced > External player is a device-only, default-off preference
shared by all profiles on that device. It stays inside Playback rather than
adding an Everyone category. The picker has one short scope label; About external
playback and custom configuration are separate drill-ins.
Choosing an installed player redirects compatible movies and episodes:
Native Player on tvOS, Infuse 8.4.7+ on both platforms, and VLC on both platforms.
The further-nested custom player editor accepts one encoded `{url}` placeholder.
Unavailable apps, failed handoff preparation, and unsupported sources use Plozz
automatically without a confirmation prompt or changing the preference.
Cancellation and profile/authorization changes abort playback, not fall back.
All IPTV content (including movies/episodes), NAS shares, and Silo bypass external
negotiation altogether. Silo's session-bound grants need its built-in lifecycle;
no speculative external session is opened. Live TV, trailers, and music keep
their existing runtimes.

External playback requires directly accessible HTTP(S) media: no app-local
proxy, downloaded file, private share credentials, separate audio stream, or
server conversion. Mobile quality limits are not bypassed. Links can contain
server tokens, so the settings explain that the chosen app receives them.
Jellyfin, Emby, and Plex direct-play sources remain eligible. Native Player and
Infuse receive resume positions and up to eight SRT sidecars;
VLC receives at most one sidecar and no resume/progress promise. Track selection,
skip markers, Plozz controls, and Plozz autoplay are not available after handoff.

`AppRuntime.ExternalPlaybackRuntime` correlates returns with a random session,
bundle-specific callback scheme, and media-URL digest. Its device-local receipt
contains no media URLs or tokens. Only the authorized launching profile,
account, server user, and credential revision can apply returned progress through
the existing durable watch outbox. No callback means no inferred watch progress.
Callbacks expire after 24 hours; a new playback intent supersedes older returns.
VLC/custom app links do not update Plozz watch progress. Once another app has
accepted a handoff, Plozz cannot detect arbitrary playback failures inside it;
supported error callbacks show the existing error without fabricating progress.
Native Player's optional `progress` fraction must be finite and within 0...1.
When present, it determines completion and its returned position is not clamped
to a possibly missing or inaccurate catalog runtime. Without that fraction,
existing runtime-based validation/calculation remains, including for Infuse.
The fraction survives receipt restoration; malformed or duplicate values are
rejected before watch state changes.
Supported partial returns also queue their percentage to Trakt as paused
playback; completion retains the existing watched-history reporting.
`ExternalPlayerSettingsModel` owns the unnamespaced device key, excluded from
profile transfer. The active profile's old choice migrates once; later profile
switches or sync never overwrite the device selection. `PlaybackSettings` reads
the retired field only for migration and no longer encodes it.
Protocol references: [Native Player](https://docs.google.com/document/d/e/2PACX-1vRfEYlU-LdWIAvIDXuHeoSs_d1ifydou7NBAhIUGsI5F663IlejVFQZ3UOaPPd9y9DhQcwKtM3VAKxz/pub),
[Infuse](https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps-Services),
and [VLC's Apple URL handler](https://github.com/videolan/vlc-ios/blob/749cf8be5f3abe0a044f1680a471999d714eb9e3/Sources/Helpers/Network/URLHandler.swift).

Trackers includes WeTrakr on both platforms, using device codes on TV and
verified HTTPS PKCE on canonical mobile builds. Its connection is profile-scoped;
watch history and planning-list behavior are documented in
[WetrakrService](../WetrakrService/README.md).

## Responsibility

- **Libraries** owns profile-wide library availability. Mobile Customize Home
  does not duplicate its Enabled controls: the Home editor manages section presentation,
  and Hero source selection uses the enabled library inventory. Discovering
  libraries for those controls must not restore a separate management list.
- **Customize Home** is one shared section editor on TV, iPhone and iPad.
  Normal rows open their own settings. Source-specific rows and their settings
  use the shared provider brand mark, including the transport badge for shares.
  In the editor, Add section, and reorder rows, the mark sits beside the
  library/server name on the second line rather than before the section title;
  generic row glyphs appear only during reordering.
  An inline Preset selector sits below the title, with up/down chevrons beside
  its current value to expose the native menu; mobile uses a secondary heading
  with a trailing native menu capsule and a divider, not another section card.
  TV gives this control row additional vertical separation from the header and sections.
  It scrolls with the content and stacks at large text sizes when needed.
  An accessible + action remains beside Reorder/Done in the native toolbar.
  TV keeps its labeled Add section beside Preset. A second, labeled
  Add section action follows the list. Reorder/Done switches to
  native movement controls with no Hidden drop zone; Hero stays
  pinned and cannot move. Its editable row carries a subtle pin rather than a
  lock, without a “Pinned at top” subtitle in either editing mode.
  On TV, the single-line title is “Home layout: Hero” or “Home layout: Showcase”,
  reflecting the active layout and opening the Home layout settings page.
  Mobile uses the shared page inset without extra gutters.
  Add section offers available existing rows not already shown. Removing a
  section hides it without erasing its configuration or disabling its libraries.
  Section context menus also offer removal. Reorder menus include Move to top
  and Move to bottom within the movable sections, never above Home layout.
  On TV, picked-up rows retain native focus during rapid directional presses
  and held Up/Down; reaching an edge does not move focus out of the list.
  Continue Watching owns its merge and artwork controls. Hero owns its sources
  and presentation, including the existing TV Home Layout/Showcase options.
  Continue Watching offers three native preview choices: Artwork + logo,
  Thumbnail, and Poster. Simple fabricated illustrations distinguish a backdrop
  with an overlaid logo, an unbranded scene, and portrait poster artwork without
  implying a fixed title position. Figures preserve their proportions; artwork
  and playback controls use a shared scale that preserves the cards' relative
  sizes, with larger compact previews, 12-point horizontal gutters, and tighter
  vertical padding. Visible artwork and optional labels are centered together,
  with no empty caption space when labels are off.
  TV examples use a taller preview area and larger playback details for viewing-distance
  legibility; this illustration-only adjustment does not change real cards or mobile previews.
  Their containers use the same `ThemeCardButtonStyle` as `PreviewCard`, including
  its shared selection and focus treatment, rather than a separate glass action-button style.
  Each choice owns its hit shape and accessibility label so scaled decorative
  artwork cannot overlap neighboring controls or expose fabricated playback text.
  They share equal choice sizes on TV and
  wide layouts, becoming preview-led rows on compact mobile layouts. The native
  Playback details control applies to all three choices: Detailed retains the
  play/progress/text overlay; Progress only uses the existing shared white bar
  without playback text on the artwork. Detailed remains the default.
  Portrait uses complete movie/show posters, with a short progressively blurred
  reflection in Detailed or standard-height posters in Progress only.
  Portrait cannot combine with thumbnails and preserves the saved landscape artwork
  preference. The presentation is profile-scoped and also applies to library
  Continue Watching rows. All three styles expose a Labels control bound to the same
  Continue Watching override in Appearance -> Cards -> Labels by view:
  Follow Appearance inherits Home rows or Recommended; On/Off controls the labels
  below any Continue Watching artwork. Each preview shows or hides its caption
  lines using the same choice. The previous portrait override is preserved.
  Caption presets/reset clear this override, and
  switching artwork presentation preserves it. Playback details is independently
  profile-scoped, survives layout changes, and does not change the Labels override.
  The Merge Next Up explanation belongs to the native toggle's label, not a
  separate helper-text row.
  Preset retains the confirmed Match server and Combined rows choices and shows
  Custom for edited arrangements. Selecting a new preset still requires
  confirmation.
  Merely opening the editor, a destination, or Reorder does not freeze a preset.
  One bottom card on the main editor uses shared `InlineErrorMessage` warnings
  to name affected sources and offers Retry, without repeating these on detail pages.
  The root and every catalog-editing destination keep discovery active while
  visible and retain loading status and local edit failures. Preset changes reload the catalog.
  Reorder is available as soon as two known sections can move, independently of
  server discovery or failures. An editing session snapshots its known rows so
  late discovery cannot move or disable a lifted row; the first actual move
  saves that arrangement, retaining unavailable saved identities. Newly discovered
  sections remain available through Add section. Known, identity-scoped sections
  remain focusable and editable while optional discovery runs; loading only
  delays choices that have not been discovered yet.
  Mobile library discovery publishes one identity-scoped snapshot, never pairing
  a previous viewer's library metadata with the newly active credentials.
  Continue Watching artwork previews remain inside equal native choices rather
  than a separate floating preview; compact mobile layouts use preview-led rows.
- `HomeSectionCatalog` owns typed choice deduplication and validated section
  edits; `HomeSectionCatalogModel` owns bounded, identity-fenced discovery.
  The UI writes through the existing profile-scoped `HomeLibraryVisibilityModel`.
  See [CoreModels](../CoreModels/README.md#home-section-editing) for ownership
  and extension boundaries. This editor does not introduce another feed engine.
- Individual profile settings expose the existing device-wide Automatically
  Sign In preference below Kids Profile, followed by a separate Delete Profile
  group. Everyone → Profiles keeps the same control and binding. Shared
  `FeatureProfiles` controls explain device scope in the description, not an
  additional heading; profile locks and parental gates still protect management.
- **Servers > Connection addresses** opens the shared address editor for each
  Jellyfin, Emby, Plex, or Silo sign-in on TV and mobile. One explicit
  **Add or manage addresses** action replaces a second list of user names.
  Multiple sign-ins get a native chooser explaining which sign-in is being
  updated; a single sign-in opens directly. The editor names both the server and
  sign-in, while address rows show URLs rather than user names. The original sign-in
  address remains visible; verified aliases can be added or removed. Saving
  updates retained providers' routes without rotating credentials or discarding
  active playback grants; unrelated sign-ins retain their providers. Address
  changes apply to subsequent work, not seamless migration of an active stream.
  Network-share aliases are a separate feature.
- `ProfileSettingsCategory` in CoreUI owns the cross-platform profile category
  order, names, icons, and summaries: Playback, Subtitles, Live TV, Libraries,
  Appearance, Screens & Navigation, Trackers, Language. iPhone and compact iPad
  use native push navigation; regular-width iPad uses a sidebar and detail stack.
  Both mobile layouts share their category section and destinations. Appearance
  groups Theme, Cards, Artwork, Spoiler Protection, and Circadian Mode; Display
  Size is last inside Cards. Screens & Navigation groups Customize Home,
  Navigation, and Detail Page; Music Player remains TV-only because mobile does
  not implement those presentation choices. Mobile navigation editing still
  excludes unsupported individual library tabs and Music/All Libraries entries.
  Everyone uses the TV order, with mobile-only Downloads last. Version/build,
  release notes, and community links are inline on both mobile root layouts.
  Mobile Community uses standard-height, single-line Discord and GitHub links
  with small brand icons, without subtitles or QR codes. TV keeps its scannable
  community cards.
  Mobile Settings also includes a **More apps** section linking Mozz to its
  public TestFlight beta. Both compact and regular layouts share the same native
  link and preserve the official full-color light/dark app icon. Its three-line
  label identifies Mozz as a free, open-source music player and names the
  TestFlight public beta without adding another line. Mozz is not
  advertised on tvOS. The iOS-only `MozzAppIcon` imageset is copied unchanged from
  `brandomoore/Mozz` at `b262a5a1257ac20369287599e6fea888462f8284`,
  `App/Mozz/Assets.xcassets/AppIcon.appiconset`; `AppLinks.mozzTestFlight`
  owns the invite URL.
  The compact and regular root menus eagerly lay out their small, fixed set of
  sections. This keeps variable-height groups stable while scrolling rather
  than repeatedly revising lazy height estimates as the promotion enters view.
  Kids-profile gates and profile/household storage ownership are unchanged.
  `SettingsLibrarySourcesSummary` shares configured source grouping and profile
  inclusion with TV. Mobile keeps the source icons/names on one horizontal line,
  showing up to three names when they fit and counting the rest in `+N more`.
  Narrow sidebars and larger text show fewer names; an oversized first name
  truncates beside a compact `+N` count rather than wrapping or hiding the count.
- `PlaybackReadAheadControl` — Playback's device-local **Video buffer**
  uses the shared checkable option list on TV and a native menu picker on mobile,
  including share-only profiles. Automatic, 1 minute, 5 minutes, 10 minutes and
  Maximum available share one ordered model and default. One short note explains
  the storage cost and excludes Apple's native player without naming internal
  engines or explaining when settings take effect. This is
  independent of profile preferences and metadata/artwork cache budgets.
- `HeroSettingsControls` — Hero keeps content selection, watched filtering, item
  count, and automatic changes together, shared by TV and mobile. **Ratings** and
  **Trailers** each show their current On/Off state and open their detailed
  controls; neither is hidden behind a generic Appearance label.
  The shared rating-count picker is visibly labeled **Maximum ratings shown**:
  it caps available scores rather than promising every title has that many.
  **Hero content sources** is the source-selection page; its link summarizes the
  currently permitted selections using the current app locale for both source
  labels and list formatting. Library, collection, Watchlist variety, and
  Discovery options use the shared `ViewPreferenceChoiceGroup` with the source
  they configure, so a source toggle and its links form one visual group.
  TV forms share row/section spacing and contained, concentric focus geometry;
  steppers focus the whole labeled row, with visible minus/plus cues and
  Left/Right adjustment. Values stay aligned to the trailing column.
  `ViewCustomizationList` varies edge-fade strength over fixed mask geometry.
  Resizing the mask while native focus scrolls can feed back into layout and
  leave long forms, including Hero content sources, unresponsive.
  `SettingsControlRows` separates controls sharing a container, keeping each
  helper with its control and omitting the divider after the last visible row.
  Hero copy uses **content** for the overall selection and **item** for one entry,
  rather than calling entries titles. **Advance automatically** and its conditional
  **Seconds per item** control share a group without a redundant section heading.
  Mobile source groups use separate native Section rows; grouped-page links
  use independent buttons with native navigation destinations so no link can
  claim a sibling switch's cell action. Each mobile destination explicitly receives
  the link's existing profile-scoped hero and trailer settings models, including
  nested source pages; page-local environment injection does not cross the native
  navigation boundary.
  **Discovery** consistently means external recommendations; its
  provider selections and **Show provider labels** attribution toggle live together.
  Ratings, trailers, and the longer source/provider/library/collection lists use subpages. TV uses
  retained detail panes with a separate nested navigation owner and returns focus
  to the originating link; mobile keeps system switches and native navigation.
- **Kids profiles** always disable external Home Discovery, including Showcase's
  Discovery row, independently of whether a Parental PIN exists. Preferences stay
  saved for later use outside Kids mode; this restriction is not synced as an
  editable setting. Connected server-user restrictions still govern library
  content—Plozz does not infer maturity from incomplete external catalog ratings.
- `CardAppearanceControls` — the independent **Show unwatched episode count**
  toggle lives beside Watched Indicator on both platforms. It defaults on,
  persists per profile, and transfers/syncs with that profile without changing
  its watched/unwatched style.
- `SettingsView` / `SettingsWorkspace` — tvOS shows one centered page at a time.
  The root contains profile identity and the category list, without a preview pane.
  Categories and ordinary descendants share `SettingsFormMetrics.pageWidth`;
  entering and returning fades between those equally sized pages with a short
  directional movement, without resizing or sliding across the screen.
  Back from a category restores its selected row and retained scroll position;
  Back from a child returns one page. Playback initially owns focus, not a second pane.
  The remembered category only restores navigation: native focus owns the row's
  highlight and selected accessibility trait. Moving to profile actions, credits,
  or any other root control must not leave an inactive category highlighted.
  The avatar/name switches profiles; the adjacent
  Edit action uses the same `ProfileActionsList` as the profile picker.
  Profile and Everyone headers share title weight/size, icon width, label gap
  and content insets so their icons and names align. Everyone's scope glyph sits
  inside a circle the same size as the profile avatar. The separators beneath
  these two headers span the full card; category-row separators stay text-aligned.
  `SettingsFormLayout` groups related controls into one vertical form, retaining
  child pages for longer editors. Single-control preferences such as Language
  use one compact label-and-control row without an extra heading or explanatory
  paragraphs. Language is a native menu directly on the root, after Trackers,
  showing the current selection. A translation-feedback QR dialog remains
  available from that menu for non-English languages and restores focus on dismissal. It shares the category
  focus/return behavior without opening an intermediate General page.
  `SettingsMenuRow` gives app/audio/subtitle language, subtitle download policy,
  and Circadian location the same whole-row focus and native menu presentation.
  A setting's label and current value form one control, not a detached value pill.
  Appearance contains Theme (including gradient backgrounds and Liquid Glass),
  Cards (with Display Size last), Artwork, Spoiler Protection and Circadian Mode.
  Screens & Navigation contains Customize Home, Navigation, Detail Page and
  Music Player. Moving these controls does not change their profile-scoped stores.
  Playback groups
  audio, autoplay/Up Next, marker skipping, seeking and display fades.
  Marker skipping is inline on the Playback page: the shared mode, per-kind
  overrides and community-marker switch do not require opening another page.
  Subtitles is its own profile category for mode, the shared/Live TV style
  editors, language, downloading and per-series memory; downloading still
  follows the active profile's provider capabilities.
  Both subtitle-style editors deliberately use the full workspace for their large
  live preview; this is the only width exception. The shared
  `SettingsPageStack` retains parents and owns typed routes, local child pages,
  and Back, including IPTV and profile editors. All use the same directional
  420ms eased fade and 64pt travel as the subtitle editor's internal panels.
  Reduce Motion changes the layout without animation.
  The incoming and outgoing style destination always lays out at the final
  workspace width; the navigation viewport reveals it without resizing the preview.
  Hidden or focus-ineligible categories also stop observing native focus, so
  an editor control cannot be mistaken for a category during the transition.
  The navigation history and profile context remain intact, including
  inside the editor's font and appearance subpages.
  Libraries, Live TV and Trackers remain profile-owned. Household setup is
  separate under Everyone. Beneath Libraries, the original signed-in strip shows
  the names and provider icons of the added sources this profile watches, grouped
  by server like the detail page. It shows up to three, then a "+N more" count.
  These are configured source names, not discovered sections such as Movies or
  Music, so they remain visible before discovery or while a server is offline.
  Profile categories start with Playback, Subtitles,
  Live TV and Libraries, then Appearance, Screens & Navigation, Trackers and Language.
  Appearance, Screens & Navigation and Trackers retain concise explanatory subtitles.
  Artwork remains profile-owned; Metadata Providers remains shared under Everyone.
  Kids profiles retain their existing parental authorization and household restrictions.
  About is a compact
  root summary with version/build, release notes and community QR codes; credits,
  Help & Diagnostics and the adult-only sign-out action follow in one group.
  `SettingsRowStyle` and `SettingsContext` provide shared controls and dependencies.
  The navigation viewport extends through the vertical safe area, keeping
  the initial top inset inside its scrollable content instead of clipping pages
  at that inset. Segmented choices share the body-sized control font; explanatory
  copy uses the smaller shared helper style.
  `SettingsFormMetrics` in CoreUI owns the centered page width, page insets, group padding and the gaps
  between sections, controls and related content, using `PlozzTheme.Spacing`.
  A legacy split-pane gap must not become large empty space between controls
  inside a workspace form. The navigation owner supplies a focus-aware Back
  control through `settingsPageBackButton`; page headers and custom editors
  host it inside ordinary pages' scrolling content. `SettingsBackButton` selects
  the same native style everywhere, and `SettingsPageHeader` places the title to
  its right, including Customize by view. Full-screen subtitle
  customization is the explicit exception: Back sits beside the stationary title,
  and only the bounded left tool pane scrolls beside the large preview.
  Preview controls below the pane expand on focus, smoothly reducing the pane's
  available height instead of scrolling the whole page. There is no redundant
  Appearance heading.
  Standalone page links use matching 28pt idle/focus corners and compact 8pt gaps.
  Controls within sections use inset rounded focus geometry instead. The shared
  `SettingsControlGroup` supplies section surfaces, row separators and insets;
  `SettingsDetailGroup` uses it for Cards and other multi-group pages. A row marked
  `groupedContent()` already owns its groups and must not gain another outer box.
  `ViewCustomizationList.hasGroupedContent` preserves the same boundary for
  editors such as Hero's source groups instead of adding a second container.
  Illustrated groups use 16pt padding on every side and a 16pt gap without a
  divider between previews and controls, including Theme, Cards and Navigation.
  Ordinary form groups share that 16pt inset and a concentric 12pt focus radius.
  Illustrated cards derive their outer chrome from the same contained radius and
  do not scale through the inset on focus; standalone/onboarding cards are unchanged.
  Group headings, compact labels, toggle/stepper labels, helper copy and ordinary
  separators use one 28pt leading text keyline. Static copy inherits its inset
  from the group; already-padded control labels consume it instead of doubling it.
  `illustratedContent()` selects that layout for single-group form rows. Ordinary
  row separators leave 8pt clear of focus on each side; root category separators
  align with the labels rather than extending under their icons.
  Compact About community cards keep their QR codes beside wrapping captions and
  share one equal-height row; mobile and expanded community layouts are unchanged.
- **SDH subtitles** is a profile-scoped playback preference, available even
  without a subtitle-download provider. TV uses the shared whole-row menu in Subtitles;
  mobile includes it in Subtitles > Behavior. Prefer SDH permits regular-subtitle
  fallback; Only SDH does not. The same saved preference also filters searches.
- **iCloud Sync > Troubleshooting** remains reachable with sync off. The grouped
  breakdown is an on-demand local-ledger snapshot of encoded payload bytes and
  record counts, not an iCloud quota or network-usage measurement. Pending uploads
  are included, pending deletions are counted separately, and separately managed
  iCloud Keychain/Trakt authorization data is explicitly excluded.
  **Erase Sync Data** needs no Developer Mode. A compact, single-title shared dialog
  separates iCloud data, local data, and unaffected media, with native buttons
  for its standalone actions. tvOS presents from the app root to avoid contested
  nested Settings modal hosts; mobile uses the shared sheet. Choose **Erase Sync Data…**,
  then confirm the native destructive alert. Cancellation at either
  step does nothing. Kids profiles cannot execute it, including after a profile
  switch. Erasure drains the sync engine, switches sync off, enumerates all
  configured server zones (including unmirrored and direct tracker records),
  checks every deletion and verifies emptiness before resetting local profiles
  and servers. In-flight Trakt exchanges are drained and their local replay state
  retired before remote deletion, including already-cancelled exchanges.
  Sync cannot be re-enabled while recovery is still running.
  Failures remain failures, even after a partial erase; no automatic reseed follows.
  Other devices must stop syncing to avoid republishing. Apple TV cannot remove
  server logins from iCloud Keychain; the review page directs that step to mobile.
- `ProfileDetailView` — manage the active profile: rename, recolor,
  switch / sign out of accounts, configure the Plex Home-user mapping
  (`PlexLinkedUserDetailView`).
- `ServerDetailView` + `ServersAndLibrariesDetailView` — manage stored
  household servers / accounts (`AccountStore`) and remove accounts.
  `MyLibrariesDetailView` owns the active profile's server-user and library choices.
  On TV, each enabled media-share section shows its own compact update phase,
  progress bar and known percentage. Only accounts included in the current
  profile contribute; idle, excluded and removed shares show no status. Progress
  observation stays in that small row, not the Settings workspace. Other Settings
  categories no longer carry a global scan card; mobile and browsing banners
  retain their existing behavior.
- `IntegrationsDetailView` — "Trackers" page: connect/disconnect for Trakt,
  Simkl, AniList & MyAnimeList (delegates to each tracker service) plus the
  Watch Status across-servers sync toggle.
- `PreferenceDetailViews` — subtitle behaviour / spoiler / diagnostics /
  Home-customization preferences. Subtitle *behaviour* (mode, language,
  auto-download) lives here; the subtitle *look* is now adjusted in the
  player while watching.
- **Send Diagnostics** on TV and mobile uses the existing crash-reporting consent.
  Each submission appears in Sentry's User Feedback inbox with the optional note
  (or "User diagnostics report" when blank), linked to the diagnostic event in
  Issues and its `plozz-recent-activity.log` attachment. No name or email is
  collected. The privacy filter retains only the feedback message, custom source,
  and valid associated event ID, not identity or arbitrary feedback fields.
  Success means SDK handoff, not server acknowledgment; inactive reporting or a
  rejected event returns failure. Feedback is not submitted when its diagnostic
  event is rejected. Both events pass through the same privacy hook before upload.
- `HeroCollectionPickerView` — Customize Home's opt-in **Collections** hero source
  chooses multiple collections across enabled movie and TV libraries, or from accounts'
  personal collections when its provider advertises that capability. The native picker
  is shared by TV, iPhone and iPad, scopes requests to the active account and
  server viewer, and loads collection pages only while open. Errors retain
  loaded rows and expose Retry. TV reuses the settings detail-page scroll layout,
  local header, native Back and wrapping checkable source rows rather than a
  full-page List or automatic segmented Picker. Mobile retains grouped native
  navigation. Choosing a collection toggles only that selection; switching sources
  retains other selections. Selected rows show their source and can be removed
  individually, including when a source is unavailable. Choice identity includes
  account, optional library, server viewer and collection, not the display name.
  The account/optional-library/collection selections stay
  in the profile's `HeroSettings` blob and travels with existing profile
  transfer/sync; older single-selection blobs migrate to a one-element array,
  and unavailable sources do not silently erase saved choices.
- `SettingsAboutSection` — app identity / version / release notes.
- `SettingsCommunityLinks` — separate Discord-first and GitHub cards shared by
  About and mobile Settings. Apple TV shows them below the app identity.
  Mobile uses one shared Community section with full-wordmark direct links and
  expandable QR cards: directly above Support in compact iPhone Settings,
  and on the About page in regular-width layouts. The cards use
  official icon-and-wordmark lockups directly on their surfaces, without colored
  icon tiles or duplicate name labels. They follow the theme's primary text color
  and stay outside the codes' white scan margins. Narrow layouts stack without
  shrinking the codes. Public destinations are centralized in `CoreModels.AppLinks`.
  `SettingsCommunityLogo` balances both brands by visible ink area rather than
  equal height: Discord renders at 75% of GitHub's height, with each original
  aspect ratio preserved. A common layout height keeps caption baselines aligned
  on TV and mobile; hosted coverage compares the rendered areas at both sizes.
  Lockup sources are from [Discord](https://discord.com/branding) and
  [GitHub](https://brand.github.com/foundations/logo); original SVGs are in
  `docs/assets/{discord,github}-lockup.svg`. The marks and lockups live in
  `App/Resources/CommunityAssets.xcassets`, linked by both app targets and their
  presentation-test hosts; platform-only catalogs must not own shared logos.
  Their vector PDF exports use CairoSVG
  with `dpi=72` so source units map to PDF points without fractional-height
  rounding by the asset compiler:
  `python3 -c "import cairosvg; cairosvg.svg2pdf(url='docs/assets/discord-lockup.svg', dpi=72, write_to='App/Resources/CommunityAssets.xcassets/DiscordLockup.imageset/discord_lockup.pdf')"`
  (substitute `github` / `GitHubLockup` for the GitHub export).
  The Discord mark comes from [Simple Icons](https://simpleicons.org/) (CC0).
  Its original path is in `docs/assets/discord-mark.svg`; the asset catalog uses
  a vector PDF because Xcode's SVG renderer distorts this path's compact arcs.
  Regenerate it with
  `python3 -c "import cairosvg; cairosvg.svg2pdf(url='docs/assets/discord-mark.svg', write_to='App/Resources/CommunityAssets.xcassets/DiscordMark.imageset/discord_mark.pdf')"`.

## Invariants

- **Settings surfaces.** Read-only focusable panels use the same adaptive
  gradient surface as ordinary groups, including the opaque Reduce Transparency
  fallback. Their native focus behavior stays unchanged.
- **TV navigation ownership.** Focusing a category selects its row; Select
  or Right opens the equally sized category page.
  Back pops a child, then returns to categories, then leaves Settings for the
  previous available app destination. MainTabView presents the workspace outside
  the navigation-style shell, retaining the hidden shell while excluding it from
  focus and accessibility. This prevents native sidebar adaptation from resizing
  the Settings page. Changing navigation style retains
  the Settings section and typed child path; all three styles restore on exit.
  Focus requests are separate from native focus arrival: competing controls stay
  gated until `NativeFocusRegionObserver` confirms ownership.
- **Profile and parental scope.** Switching profile or changing Kids/PIN status
  resets the workspace. Parental unlock proof is tied to the active profile and
  current PIN verifier, not a persistent boolean. Route rendering enforces the
  same restrictions as category visibility, including artwork/metadata cross-links.
  A PIN unlock opens the selected protected pane in place; it must not dismiss
  Settings. Kids without a household PIN retain their simplified, unsealed setup.
  Mobile keeps its existing Settings navigation and control layouts.
- **Review capture.** `SettingsWorkspaceRemoteTests` is opt-in through
  `PLOZZ_SETTINGS_REVIEW=1` and runs only against the real app on an explicitly
  owned simulator. The DEBUG-only `PLOZZ_SHOTS_SETTINGS=1` launch fixture uses
  fictional Alex/Sam profiles. `PLOZZ_SHOTS_SETTINGS_NAVIGATION` chooses the
  initial navigation style; `PLOZZ_SHOTS_SETTINGS_KIDS` configures the test child
  as `off`, `no-pin`, or `pin`. These fixtures are never enabled on physical TVs
  or normal launches. Attachments include native screenshots and accessibility
  trees, not browser mockups.

- **Shared TV control scale.** Tri-state segments, reorder labels, compact preview-card
  captions, and form controls use `SettingsRowMetrics.titleFont`. Feature and group
  descriptions share the smaller `descriptionFont`. Segmented tracks and single-line
  reorder rows match the shared primary control height. Only the selected segment
  makes room for a checkmark; that space animates between options without padding
  unselected labels. Focus still only previews an option: Select commits it.
  Reorder lift/drop behavior and mobile sizing are unchanged.
  Checkable choices (including Artwork presets), option chips, stepper values, and
  navigation labels consume the same title token; inline explanations use the
  description token. Checklists and segments share `SettingsCheckmark`, rather than
  styling separate oversized selection indicators. Rank columns reserve the largest
  enabled number using monospaced digits, including lists with 20 or more items.
- **Artwork and label presets.** Choosing any preset, including reselecting the
  previous one, replaces the whole configuration through `applyPreset`. Editing
  a view switches to Custom: no preset is selected, and a single badge appears on
  "Customize by view". `selectedPreset` derives this status from existing stored
  overrides; the backing preference retains unedited views' behavior, including
  mixed recommended rules. Settings remain in the existing profile store and sync
  payload; artwork's `scopeVersion` migrates earlier shared choices once.
  Matching a preset's value manually stays Custom; choosing a preset replaces all
  overrides. Rows show a name and short value: Library / Metadata providers, or
  On / Off. Only title-detail artwork and Home/Recommended labels also offer
  Mixed: metadata backgrounds/logos with library posters, or labels except in
  Showcase/on series artwork, respectively. Mixed is an explicit, persisted
  per-view choice independent of the backing preset. TV Select cycles the same
  supported choices as the mobile menus, with focused explanatory artwork.
  On iPhone/iPad, a chevron-marked value control opens a native checked menu:
  opening or dismissing it never changes settings. It checks the effective
  value, without an extra default/inheritance option. Presets reset the entire
  configuration, including explicit Mixed choices. The mobile Artwork page
  places its heading outside the three-preset group and customization in its
  own group below.
  Mobile customization pages use inset grouped rows on an opaque theme-aware
  background, not the ambient gradient. Only the value opens the menu; the view
  label stays in the row while the menu shows choices without a repeated title.
  Accessibility hints retain explanations without repetitive row descriptions. Mixed labels in
  Home and library Recommended retain their Showcase/title-artwork rules until
  edited. Long values and accessibility text sizes stack instead of clipping.
  Both lists group library tabs under "Libraries". Artwork separates Home's
  Showcase/hero from other Home rows, and library Recommended's hero (TV only)
  from its rows. Browse, Collections, and Playlists have independent choices;
  titles inside collections/playlists use Browse. Continue Watching rows share
  one choice across Home and libraries, independent of the series-artwork option.
  Watchlist means the standalone page, not Home's Watchlist row. Episode browser
  means detail-page episode cards; Video player artwork covers player menus,
  Up Next, and system Now Playing. Shared view components retain these scopes
  rather than treating a common layout as a shared preference.
  Labels retain equal-height visual presets: App default uses a single split illustration with
  caption bars on only one half. Show labels everywhere and Hide labels everywhere
  govern all media captions; App default owns Showcase and title-artwork exceptions.
  Explicit per-view choices, including Episodes, last until a preset replaces them.
  Library navigation names and on-artwork information are not captions.
  Per-view help states whether labels are visible or hidden; Mixed explains
  the Showcase and series-artwork exceptions. It follows the focused setting
  and updates when that setting changes.
  TV customization pages share the same scrolling Back control and title.
  Their scroll content can cross the top safe-area inset without a hard crop;
  a scroll-dependent fade handles the outer edge. Neither Back nor the title
  is pinned. Pages without contextual help also draw through the bottom safe
  area to the screen edge; pages with a fixed help footer retain its clearance.
- **Scoped TV detail navigation.** `SettingsDetailPages` and `SettingsDetailLink`
  in `SettingsDetailNavigation.swift` are reusable across settings, independent of
  artwork and labels. A `SettingsSplitRow` opts in with `SettingsDetailSubpage`;
  use `SettingsDetailLink` inside its root content to open that child. Outside a
  scoped pane, the link uses ordinary navigation. Both pages slide by the pane's
  full width: the root leaves toward the leading edge as the child enters from
  the trailing edge, and Back reverses both motions. The root stays mounted to
  preserve state and scroll position; it becomes ineligible for input while away.
  The sidebar stays stationary. Entry transfers native focus to the first row;
  Back restores the originating link after removal completes. Stale completions
  are invalidated when changing the selected sidebar page. Left remains available
  for sidebar navigation, RTL mirrors the motion, and Reduce Motion disables it.
  The slide mask contains horizontal overflow but extends through the vertical
  safe area, preserving native scroll rendering at the pane's top and bottom.
  Do not clip the safe-area frame on both axes: it cuts preview cards off above
  the panel's lower edge.
  Child content chooses its initial native focus target and calls
  `SettingsDetailNavigation.focusArrived()` when that control receives focus.
  Customization lists and their inset contextual cards occupy separate regions.
  Larger 16:9 illustrations highlight only the affected artwork, beside one sentence
  of help; full-page outlines sit inside the preview's rounded corners rather than
  being clipped by its mask. Label settings reuse the card-style preview. Navigation follows the active
  profile, including native sidebar, pinned rail, and top-tab differences. Ordinary
  title rows use 2:3 posters; episode/player thumbnails use their landscape ratios.
  Home follows the active Fullscreen Hero/Showcase layout, including disabled heroes;
  Continue Watching uses its actual thumbnail or extended series-artwork shape.
  The shared title-detail choice shows separate movie and show layouts: show episodes
  stay muted because the episode choice owns those images. Extras and cast photos
  are not promised a title-level source replacement. Keep the card and viewport
  stable as focus or values change, with no extra focus stop or content behind
  the card. A smooth 40-point bottom fade and matching scroll clearance keep focused
  rows above the fade. Lists without help reserve no footer. Horizontal pane-level
  transition clipping remains. Artwork values use "Library" and "Metadata providers", with "Mixed" for
  Recommended title details (metadata-provider heroes and library-first related posters); narrow/mobile
  and accessibility layouts stack the complete value rather than abbreviating it.
- **Profile Seerr setup uses page gutters, not artwork padding.** On iPhone/iPad,
  `ProfileSeerrSetupView` uses `SettingsPageScroll` and a centered, at-most
  720-point column. Its noninteractive profile chip uses `ProfileAvatarView`
  for the real photo, emoji, or symbol and wraps below the heading when needed.
  Panel rows and footers share one inner inset. Actions fill
  the column and stack at accessibility text sizes; long profile/user names
  wrap without widening the scroll content. TV retains its bounded settings
  layout with contained row focus.
- **Mobile Settings is a presentation action.** The profile button is the default
  entry point. Its navigation shortcut starts hidden on iPhone and iPad, keeping
  the default navigation at five destinations or fewer even with Watchlist.
  The arranger can explicitly Show it; this profile-scoped override survives
  relaunches, while Reset Navigation restores the hidden default. Automatic
  hiding is not saved as a manual preference and does not hide Settings on TV.
  Its optional tab or More entry opens
  the drawer over the current page without selecting a replacement destination.
  Keep the active content stack and overflow navigation intact on dismissal;
  destination normalization still retains the Settings-only recovery screen.
  The native tab delegate must reject the Settings transition before UIKit
  changes navigation insets; declining only the SwiftUI selection binding can
  move a scrolled page. Forward other delegate callbacks and restore the prior
  delegate when the action bridge is removed.
  Replacement bridges take over the original delegate directly rather than
  chaining through an older bridge; overlapping SwiftUI lifetimes must not
  create a forwarding cycle or let a removed bridge uninstall its replacement.
- **Automatic iCloud sync.** The main sync page does not show a separate Live TV
  explanation panel. Recovery lives in Troubleshooting, with a warning above
  Reload and Reset explaining that neither is normally needed. Both platforms
  use the shared transient-status presenter for progress and the actual result,
  and disable both actions while either is running. Reset still requires
  confirmation. Pending Live TV source repair rows remain in Troubleshooting.
- **Profile-namespaced settings.** Per-user prefs (theme, captions,
  diagnostics, spoiler) are namespaced by the active profile id; the
  default profile uses no suffix so an upgrading install keeps existing
  values (`migrateLegacyIfNeeded` in `ProfileStore`).
- **No tokens here.** Account & Trakt token management is delegated to
  `FeatureAuth.AccountStore` / `TraktService.TraktTokenStore`.
- **Dual-provider.** Server/library management must work for both Plex
  and Jellyfin accounts (Plex Home-user mapping is Plex-specific, but
  the UI must clearly say so).
- **No persistence schema duplication.** Persistence lives in
  `CoreModels` / `FeatureAuth` / `TraktService`; this module only
  **edits** what they store.

## Where to look first

- `SettingsView.swift` — the row composition (the tree of detail pages).
- `ProfileDetailView.swift` — profile-scoped editing.
- `PreferenceDetailViews.swift` — caption / spoiler / diagnostics prefs.
