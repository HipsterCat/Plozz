# IPTV troubleshooting history

A short reference for future investigations, **not a specification or source of
truth**. Reviewed against [TestFlight 56.4][release-56.4]. These notes describe
past problems and attempted repairs; the code, provider behavior and evidence
may have changed since. A similar symptom can have a different cause.

The broad implementation came from Aether live playback ([080186de3]),
streamed playlist/source handling ([749dffafa]), and authenticated IPTV accounts
with disk-backed catalogs ([33e753ac7]). Account-backed IPTV and older standalone
playlists still have different loading paths. More detail:
[Live TV](live-tv-prototype.md) and [playback routing](playback-engines.md#iptv-live-streams).

## Start with the matching symptom

Commits are grouped by problem rather than release. This is a repair-history
index, not every Live TV UI change, merge, or release-note commit.

| Past problem | What changed and why it matters when comparing a new bug | Related tests |
| --- | --- | --- |
| Valid playlists rejected, headers lost, or fake channels imported | [a63f51d80], [f232a2e65], [6faff1b08], [e3da5f69c]: expanded header/plain-list compatibility, separated optional guide limits from channel import, and filtered placeholders. HLS segments and HTML login pages were important negative cases. | [Parser](../Tests/FeatureLiveTVCoreTests/LiveTVPlaylistParserTests.swift), [authentication](../Tests/ProviderIPTVTests/IPTVAuthenticationTests.swift) |
| Channels classified as movies or absent from Live TV | [623e9789f], [7199de714]: corrected file-extension classification and account enrollment/loading. A channel serving an MP4 is not necessarily a movie; IPTV-only setup also needed its own admission path. | [Mapping](../Tests/ProviderIPTVTests/IPTVProviderTests.swift), [account-to-guide import](../Tests/ProviderIPTVTests/IPTVLiveTVImportTests.swift) |
| Empty event playlists rejected, or Refresh appeared ineffective | [487b0764c] clarified invalid/empty errors; [ea7bb802f] subsequently accepted valid empty event playlists. [b58ae04b3] connected explicit refresh to an actual provider refresh. Empty, malformed, and temporarily unavailable were different cases. | [Empty/live/empty transitions](../Tests/ProviderIPTVTests/IPTVAuthenticationTests.swift), [refresh UI](../Tests/HomeRemoteTests/LiveTVPreviewIntroductionRemoteTests.swift) |
| Saved channels unavailable while a refresh was slow or failed | [d30d3fdf0], [daf932b7b]: reused committed catalogs and separated freshness from availability. Background reads, explicit refresh, first import, cancellation and rollback have different behavior. | [Refresh and recovery](../Tests/ProviderIPTVTests/IPTVIntegrationTests.swift), [interrupted imports](../Tests/ProviderIPTVTests/IPTVScaleAndRecoveryTests.swift) |
| One unnamed Xtream entry prevented import | [269adb95c]: used a valid native ID when the display name was missing, while retaining malformed-record and rollback checks. | [Unnamed entries and rollback](../Tests/ProviderIPTVTests/IPTVScaleAndRecoveryTests.swift) |
| Playlist setup actually needed an Xtream login | [442ddea89]: recognized supplied Xtream credentials with a bounded fallback. Real M3U feeds and authentication/network failures were comparison cases, rather than reasons to try every protocol. | [Protocol detection](../Tests/ProviderIPTVTests/IPTVXtreamDetectionTests.swift) |
| Missing guide or endless guide loading | [e3da5f69c] added selective Xtream-to-XMLTV fallback; [f692c9818] recognized accounts without a guide. [31fa490f1] replaced the earlier manual cross-origin guide opt-in with automatic declared-guide loading and origin-scoped credentials. | [Guide integration](../Tests/ProviderIPTVTests/IPTVIntegrationTests.swift), [guide capability](../Tests/ProviderIPTVTests/IPTVAuthenticationTests.swift) |
| Sources looked unloaded or became inaccessible | [7199de714], [d98197268], [361f14483], [1f6a34413]: shared source loading, excluded sync bookkeeping from authority comparisons, restored saved counts in Settings, and resumed loading after authorization returned. These were not all source-deletion bugs. | [Source lifecycle](../Tests/AppRuntimeTests/LiveTVSourcesRuntimeTests.swift), [hosted authorization](../Tests/FocusIntegrationTests/LiveTVSourcesRuntimeHostedTests.swift), [setup recovery](../Tests/AuthPresentationSupport/IPTVLibrarySelectionHostedTests.swift) |
| Raw IPTV stream failed before its first frame | [ae58eb8ae] retained format suffixes; [d30d3fdf0] added declared-output hints and faster raw joining. [ff00fc920] inspected undeclared streams with one extra sequential GET. That tradeoff and working fragmented-MP4 HLS are relevant when reconsidering the route. | [Actual rendered playback](../Tests/SubtitlePresentationSupport/IPTVPlaybackHostedTests.swift), [format detection](../Tests/EnginePlozzigenTests/PlozzigenLiveSourceProbeTests.swift) |
| Redirected HLS stopped or kept changing session URLs | [442ddea89] allowed provider-issued playback redirects with cross-origin account headers removed. [ac1515b1b] retained the redirected playlist session and allowed one renewal for an expired delivery URL. Playback and login/catalog redirect policies differ. | [Redirects and renewal](../Tests/ProviderIPTVTests/IPTVPlaybackRedirectTests.swift) |
| Stop/cancellation raced request creation and could crash | [0913e8938] fenced `IPTVHTTP` startup against session invalidation. The new format probe needed the same protection in [ed6d4a4f9]. That second race was found before 56.4 shipped, not established as a shipped crash. | [HTTP lifecycle](../Tests/ProviderIPTVTests/IPTVHTTPLifecycleTests.swift), [probe startup barrier](../Tests/EnginePlozzigenTests/PlozzigenLiveSourceProbeTests.swift) |
| Switching channels overlapped connections or lost the Watch request | [361f14483] drained owned connections and serialized root requests. [29800498d] then moved presentation commit after cleanup so it did not cancel its own pending preview. Intentional Multiview and HLS child requests are separate cases. | [Proxy lifetime](../Tests/ProviderIPTVTests/IPTVPlaybackLifecycleTests.swift), [handoff ordering](../Tests/FeatureLiveTVCoreTests/LiveTVPlaybackCoordinatorTests.swift) |
| A generic playback error hid the useful cause | [1319ce4f2], [ae58eb8ae], [2e0906593], [eb7170086] retained typed refusals and bounded, redacted evidence. [deb0093f4] stopped an unfinished native probe from replacing completed root-request evidence. Better diagnostics were not themselves a playback repair. | [Proxy evidence](../Tests/ProviderIPTVTests/IPTVPlaybackDiagnosticsTests.swift), [retained reports](../Tests/CoreModelsTests/PlaybackFailureDiagnosticTests.swift) |

## Related large-library work

These are useful leads when a report is about slowness, storage or sync rather
than stream decoding:

| Area | History and comparison points | Related tests |
| --- | --- | --- |
| Import and browsing cost | [be1f265f0], [6ad1d6b15], [32e37c3e7], [0f4e41aad], [5bae53dfc]: reduced publication copies, import/save work and repeated category lookups; kept imports awake. Record completeness and stable identities were comparison points, not just elapsed time. | [Scale/recovery](../Tests/ProviderIPTVTests/IPTVScaleAndRecoveryTests.swift), [import measurements](../Tests/ProviderIPTVTests/IPTVPerformanceProbeTests.swift), [publication](../Tests/FocusIntegrationTests/LiveTVLargePlaylistHostedTests.swift) |
| SQLite teardown and disk growth | [e832c1050] moved main-thread teardown work; [42438a9c8] bounded reusable journals and reclaimed staging. Committed catalogs and active readers were separate from disposable working data. | [Teardown](../Tests/ProviderIPTVTests/IPTVCatalogTeardownTests.swift), [storage](../Tests/ProviderIPTVTests/IPTVCatalogStorageTests.swift) |
| Shared Live TV sync cost and limits | [3e2f229b2], [0d8402f74], [d6ba79465], [29106c8b3], [42438a9c8]: revised journal limits, reused unchanged preparation and reduced staging/ledger work. Generated-channel snapshots are different from IPTV provider catalogs; a fix in one does not establish behavior in the other. | [Portable state](../Tests/CoreModelsTests/LiveTVPortableSyncTests.swift), [library sync](../Tests/AppRuntimeTests/LiveTVPortableLibraryImportTests.swift) |

## 56.4 outcome and limits

- [#112](https://github.com/brandomoore/Plozz/issues/112) reported native-HLS
  failure (`-11850` / `-12939`) while upstream evidence showed transport-stream bytes. The 56.4
  routing repair was reproduced with controlled fixtures on iOS and tvOS;
  that does not establish compatibility with every provider.
- [#113](https://github.com/brandomoore/Plozz/issues/113), disappearing Sources
  followed by duplicate re-addition, remained **unreproduced and unresolved**.
  [ff00fc920] added outage, account-readmission, storage-recovery and sync
  coverage, but did not establish a production source-deletion fix.

For another report, the matching row and its neighboring cases are starting
points, not a prescribed solution. A useful addition here would be one short
entry linking the new symptom, commit, regression example and remaining
uncertainty. Earlier decisions can be revisited when new evidence supports it.

[release-56.4]: https://github.com/brandomoore/Plozz/releases/tag/release/056.4
[080186de3]: https://github.com/brandomoore/Plozz/commit/080186de3
[1319ce4f2]: https://github.com/brandomoore/Plozz/commit/1319ce4f2
[a63f51d80]: https://github.com/brandomoore/Plozz/commit/a63f51d80
[f232a2e65]: https://github.com/brandomoore/Plozz/commit/f232a2e65
[749dffafa]: https://github.com/brandomoore/Plozz/commit/749dffafa
[33e753ac7]: https://github.com/brandomoore/Plozz/commit/33e753ac7
[623e9789f]: https://github.com/brandomoore/Plozz/commit/623e9789f
[6faff1b08]: https://github.com/brandomoore/Plozz/commit/6faff1b08
[7199de714]: https://github.com/brandomoore/Plozz/commit/7199de714
[487b0764c]: https://github.com/brandomoore/Plozz/commit/487b0764c
[e3da5f69c]: https://github.com/brandomoore/Plozz/commit/e3da5f69c
[ea7bb802f]: https://github.com/brandomoore/Plozz/commit/ea7bb802f
[ae58eb8ae]: https://github.com/brandomoore/Plozz/commit/ae58eb8ae
[0913e8938]: https://github.com/brandomoore/Plozz/commit/0913e8938
[d30d3fdf0]: https://github.com/brandomoore/Plozz/commit/d30d3fdf0
[daf932b7b]: https://github.com/brandomoore/Plozz/commit/daf932b7b
[b58ae04b3]: https://github.com/brandomoore/Plozz/commit/b58ae04b3
[269adb95c]: https://github.com/brandomoore/Plozz/commit/269adb95c
[f692c9818]: https://github.com/brandomoore/Plozz/commit/f692c9818
[31fa490f1]: https://github.com/brandomoore/Plozz/commit/31fa490f1
[442ddea89]: https://github.com/brandomoore/Plozz/commit/442ddea89
[d98197268]: https://github.com/brandomoore/Plozz/commit/d98197268
[361f14483]: https://github.com/brandomoore/Plozz/commit/361f14483
[29800498d]: https://github.com/brandomoore/Plozz/commit/29800498d
[1f6a34413]: https://github.com/brandomoore/Plozz/commit/1f6a34413
[2e0906593]: https://github.com/brandomoore/Plozz/commit/2e0906593
[ac1515b1b]: https://github.com/brandomoore/Plozz/commit/ac1515b1b
[eb7170086]: https://github.com/brandomoore/Plozz/commit/eb7170086
[deb0093f4]: https://github.com/brandomoore/Plozz/commit/deb0093f4
[ff00fc920]: https://github.com/brandomoore/Plozz/commit/ff00fc920
[ed6d4a4f9]: https://github.com/brandomoore/Plozz/commit/ed6d4a4f9
[be1f265f0]: https://github.com/brandomoore/Plozz/commit/be1f265f0
[6ad1d6b15]: https://github.com/brandomoore/Plozz/commit/6ad1d6b15
[32e37c3e7]: https://github.com/brandomoore/Plozz/commit/32e37c3e7
[0f4e41aad]: https://github.com/brandomoore/Plozz/commit/0f4e41aad
[5bae53dfc]: https://github.com/brandomoore/Plozz/commit/5bae53dfc
[e832c1050]: https://github.com/brandomoore/Plozz/commit/e832c1050
[42438a9c8]: https://github.com/brandomoore/Plozz/commit/42438a9c8
[3e2f229b2]: https://github.com/brandomoore/Plozz/commit/3e2f229b2
[0d8402f74]: https://github.com/brandomoore/Plozz/commit/0d8402f74
[d6ba79465]: https://github.com/brandomoore/Plozz/commit/d6ba79465
[29106c8b3]: https://github.com/brandomoore/Plozz/commit/29106c8b3
