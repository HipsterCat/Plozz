# Screenshots and original demo media

The README uses real Plozz simulator captures. Home and library views use a
catalog of 37 original titles, including eight in-progress titles at different
playback positions. Posters, backdrops, videos, descriptions and subtitles were
created for this project. Online metadata and artwork are disabled for capture.

## Provenance

- [Image records](assets/screenshots/provenance.json) identify the app revision,
  capture bootstrap, original PNG hashes and published JPEG hashes.
- [Demo source archive](assets/screenshots/demo-media-source.zip) contains the
  original media generator, loopback catalog fixture, capture-only bootstrap
  patch, media inventory and font/license notices.
- The original procedural media is supplied under the MIT license. Manrope is
  supplied under SIL OFL 1.1. Plozz's interface retains the app's own license.

The catalog fixture supplies original data to Plozz's normal media-provider
client; it is not a real Jellyfin deployment or an interoperability test.
The capture bootstrap configures this local source and completes onboarding
through existing app paths. It also keeps the internal screenshot router from
cancelling its own navigation before an acknowledgement. It does not recreate,
paint over or replace the application interface.

The player and subtitle-editor captures use the earlier version of the same
original-media collection. Their exact source hashes are recorded separately.

## Preparing captures

Use an isolated checkout and fresh, owned simulators with no personal accounts
or libraries. Follow the repository's build-lease and signing procedures. Do not
reset or reuse another session's simulator, and do not deploy capture builds to
physical devices.

Generate media from the archived source with CairoSVG, Pillow, FontTools,
ImageMagick and FFmpeg, then serve it through the included loopback fixture.
The capture environment points to that fixture. The legacy NFS capture variable
enables the existing command channel; it does not require connecting a personal
share.

The DEBUG-only screenshot directors accept named requests in the app's
Documents directory:

```text
home
library
detail?title=Orbital%20Drift
play?title=Orbital%20Drift&at=45&pause=1&subs=0
play?title=Tidal%20Light&at=40&panel=subtitleStyle&pause=1
```

Require a successful acknowledgement and loaded artwork before capturing the
framebuffer with `xcrun simctl io <owned-simulator-id> screenshot`. A missing
title, blank poster, loading screen or timed-out request is not a usable image.
Keep progress values within each actual video's runtime.

Native PNGs can be normalized to sRGB with an opaque alpha channel removed.
README JPEGs are proportionally resized from those originals. Do not stretch
screens, replace app text, add fictional controls or paint over unapproved art.
Keep portrait iPad captures portrait unless the app was genuinely captured in
landscape.

Stop the fixture server and owned simulators after capture. Retain the native
PNGs and source records. Use content-versioned image filenames when updating
the README so cached previews do not retain the previous image.

## Publication checks

Review every visible frame, poster, backdrop, avatar, description and caption
for reuse permission. Buying or streaming a film, using a metadata service, or
distributing a free app does not itself grant permission to reproduce its art.
Do not use the historical commercial-title lists or personal-share defaults in
older capture scripts for public assets.

Verify README image paths, image dimensions and provenance hashes. Keep
unreferenced or unapproved captures out of the published screenshot directory.
The marketing website has its own reviewed screenshot inventory and
publication checks; follow that repository's import instructions rather than
copying images into it implicitly.

For App Store assets, use the
[current Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
and [asset guidance](https://developer.apple.com/app-store/asset-best-practices/).
README JPEGs are not submission-sized originals. Confirm the final screenshots
match the intended submission build, and obtain design approval before
localization, upload or submission. Asset records do not guarantee legal
clearance or App Store approval.

## Channel identity theme comparison

`PlozzChannelIdentityCaptureTests/testNativeBylineThemes` in
`PlozzHomeFixtureTests` captures the Byline artwork in Light, Dark, and Black using
the production tvOS guide, sidebar, hero, and focus components. Run this selected
test on an owned Apple TV 4K simulator. The fixture uses identical sample
channels, category moods, a fixed schedule, and the same focused programme for
all images.

The fixture-only `PLOZZ_CHANNEL_IDENTITY_THEME` launch environment selects
`light`, `dark`, or `black`. These are native simulator captures, not physical-TV
captures or a configured user's library. The saved
`assets/plozz-oled-icon-concept.svg` and matching PNG are separate icon
explorations, not shipping assets.
