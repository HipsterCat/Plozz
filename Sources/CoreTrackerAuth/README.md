# CoreTrackerAuth

Shared profile-scoped OAuth credential storage, PKCE validation and single-use
refresh coordination for Trakt and WeTrakr. API routes, wire DTOs and user-facing
connection copy remain in each service.

This module contains the existing Trakt coordination implementation, extracted
without changing its persisted formats. Trakt exports compatibility aliases.
Stores must use separate service accounts; WeTrakr uses `wetrakr.oauth`.
PKCE callback failures expose typed, value-free reasons for service-specific
diagnostics. Trakt preserves its existing invalid-response presentation.
A bare trailing `#` is accepted as an empty fragment, as returned by WeTrakr's
Google sign-in. Nonempty fragments, mismatched callback addresses/state, and
missing or duplicate authorization codes remain rejected.

The coordinator combines in-process single-flight ownership, server-acknowledged
conditional refresh claims, a device-local Keychain exchange journal, durable
disconnect tombstones, and profile/iCloud-account fencing. Never fall back to
last-writer-wins synchronization or reuse a refresh token after an uncertain
exchange. See [Trakt's authorization contract](../TraktService/README.md#shared-profile-authorization).
