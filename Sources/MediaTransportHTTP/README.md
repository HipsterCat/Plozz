# MediaTransportHTTP

HTTP/WebDAV protocol primitives used by `MediaTransportWebDAV` and
`ProviderShare` on tvOS and iOS/iPadOS. Shared ownership, identity, resolver,
and byte-source contracts live in `MediaTransportCore`.

## Adapter guarantees

- **Origin discipline**: exact scheme/host/port normalization
  (`TransportOrigin`). `OPTIONS` and `PROPFIND` retain same-origin redirects
  (`RedirectPolicy`). File GETs have the separate delivery policy below.
- **Credentials**: `CredentialPreflight` owns the existing LAN policy.
  Configured HTTP shares permit credentials with an onboarding warning;
  HTTPS is recommended. This permission does not allow redirect downgrades.
  Password challenges enforce the immutable `PasswordAuthPolicy` and use
  nonpersistent credentials. Descriptions and errors exclude secret values.
- **TLS trust**: system trust by default; an explicitly accepted override pins
  the exact leaf certificate DER for one origin/trust revision, never "trust
  all." A mismatch fails closed.
- **Session isolation**: ephemeral sessions are scoped to account, credential
  revision, origin, trust revision and role. Cookie storage, URL caches and
  shared credential storage are disabled. Retirement cancels the source's
  sessions without affecting another account.
- **WebDAV surface**: bounded OPTIONS, PROPFIND Depth 0/1, external-entity-free
  XML parsing, normalized root-contained hrefs, and explicit byte/entry caps.
- **Range safety**: identity encoding, exact `206`, matching `Content-Range`
  offsets/total and body length. A one-byte GET establishes the actual
  representation's strongest usable validator. Every later read sends
  `If-Match` for a strong ETag, or `If-Unmodified-Since` for Last-Modified, and
  requires the same response validator. Weak ETags alone are insufficient.
  Missing/changed validators, HTTP 412, changed sizes, ignored ranges and
  truncated responses fail instead of being treated as usable media.
- **Response buffering**: each task owns one mutable body accumulator under the
  delegate lock. Callback appends must not copy the entire previously received
  body. The byte cap is enforced before appending, and cancellation/errors never
  return the partial body as successful media.

## File identity and compatibility

Directory listing and ordinary stat do not require a validator or read file
contents. When preparing a locator, `statForOpening` tries a bounded GET if DAV
metadata lacks both a strong ETag and modification time. This learns a real
identity without imposing seekability on sidecars. It never invents a timestamp,
ETag or size. Files with neither a usable GET ETag nor Last-Modified still
cannot play; validator-free best-effort streaming is not enabled.

GET-only identity discovery requires the exact stable DAV URL, not a redirected
resource: equal ETag strings on different resources are not comparable. Redirected
files therefore need a DAV ETag or modification time; a CDN validator alone cannot
be persisted as the stable file's identity. Opening reuses the identity-discovery
probe rather than resolving a second, potentially different delivery resource.

Opening a source revalidates its stored DAV metadata, including persisted
download locators, then probes the actual media representation. A different
delivery host can have a different ETag namespace, so its ETag is not compared
to the DAV ETag. The actual GET validator is pinned for the source lease.
Same-origin comparable DAV/GET validators and all declared sizes must agree.
The probe retains Last-Modified even when a stronger GET ETag is selected for
reads, so a date-based locator cannot skip its modification-time comparison.

Last-Modified is **change-detecting, not immutable**: it has one-second
precision and cannot detect a server replacing bytes while preserving both
timestamp and size. Strong ETags remain preferred. The metadata recheck adds
a PROPFIND per open; missing DAV validators add a one-byte GET during locator preparation.
No full-file download or mandatory HEAD is introduced. Each playback window
uses one validated range, up to 32 MiB. The transport reader can overlap
consumption with one bounded next window rather than doubling HTTP requests.
HTTP 429 establishes a session-local `Retry-After` cooldown (delta-seconds or
HTTP date, five-second fallback). Calls during it fail before starting another
request; there is no automatic retry or waiting-task queue. See
[disc playback](../../docs/playback-engines.md#media-share-disc-images) for the
memory/cancellation contract.

## HTTPS media delivery redirects

The initial GET must be inside the configured DAV root. Same-origin hops
remain root-bound. Only GETs (media probes and bounded sidecars/artwork) may
leave that origin, for an HTTPS DNS-host destination; IP literals, local
hostnames, URL userinfo, fragments and HTTPS downgrades are rejected.
Every hop is checked and the chain is capped at five redirects. Hostname
screening is not DNS-address pinning.

Once a chain leaves the DAV origin, every subsequent request uses an isolated
anonymous session with system TLS trust, even if a hop returns to the DAV
origin. No Authorization, cookies, Referer, shared credential storage or DAV
certificate override follows it. Authentication challenges on delivery
sessions fail instead of consulting account credentials. These sessions remain
owned by the original account/revision/role and are retired with that source.
Browsing never gains this cross-origin permission.

Resolved URLs can contain short-lived signatures. They stay inside the active
byte-source lease, never in persisted locators or diagnostics. Reads remain
bound to that URL and validator; an expired URL or a later redirect fails
rather than silently mixing representations. Retrying playback opens the
stable DAV path afresh. Bounded sidecar reads use the same redirect policy.

## AllDebrid setup and evidence limits

The [official WebDAV guide](https://help.alldebrid.com/en/Alldebrid%20tools/webdav)
and [rclone guide](https://help.alldebrid.com/en/faq/rclone-webdav) specify
`https://webdav.debrid.it/`, a dedicated API key as the username, and any
nonempty password. Use the username/password fields rather than the documented
key-in-path alternative, so the key stays out of URLs. No AllDebrid-specific
User-Agent, CDN allowlist or media-URL lifetime is assumed.

AllDebrid recommends rclone's generic WebDAV backend and conservative read-only
streaming settings. Its API rate limits are not treated as WebDAV/media limits.
The generic [rclone range checks](https://github.com/rclone/rclone/blob/d369079a1448c487d09d85bfe11382e16ea4e345/lib/rest/headers.go#L87-L155)
and [redirect handling](https://github.com/rclone/rclone/blob/d369079a1448c487d09d85bfe11382e16ea4e345/lib/rest/rest.go#L297-L361)
are useful compatibility precedents, not observations of AllDebrid responses.

Regression fixtures are synthetic `URLProtocol` responses. They do not prove
native AllDebrid ETag behavior, its redirect chain, real TLS/Basic/Digest
interoperability, or the original reporter's playback outcome. Those still
require a real-server retest.
