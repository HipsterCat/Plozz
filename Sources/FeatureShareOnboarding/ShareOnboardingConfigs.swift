import Foundation
import AppRuntime
import CoreModels
import FeatureAuthCore

// Completed add-a-share configurations handed back from the unified onboarding
// flow to each platform's persistence layer. Extracted from the tvOS shell so the
// shared `UnifiedAddShareModel` (and both the tvOS + iOS views) can use them.

/// The values collected when adding an SMB media share.
public struct ShareDraft: Equatable {
    public var host: String
    public var port: Int?
    public var share: String
    public var subpath: String
    public var username: String
    public var password: String
    public var displayName: String
    public var libraryConfiguration: MediaShareLibraryConfiguration?

    public init(
        host: String,
        port: Int?,
        share: String,
        username: String,
        password: String,
        displayName: String,
        subpath: String = "",
        libraryConfiguration: MediaShareLibraryConfiguration? = nil
    ) {
        self.host = host
        self.port = port
        self.share = share
        self.subpath = subpath
        self.username = username
        self.password = password
        self.displayName = displayName
        self.libraryConfiguration = libraryConfiguration
    }
}

/// The finished configuration for a WebDAV share.
public struct WebDAVShareConfiguration: Equatable {
    public let baseURL: URL
    public let auth: MediaShareWebDAVAuth
    public let trustPin: SHA256Fingerprint?
    public let displayName: String
    public let libraryConfiguration: MediaShareLibraryConfiguration?

    public init(
        baseURL: URL,
        auth: MediaShareWebDAVAuth,
        trustPin: SHA256Fingerprint?,
        displayName: String,
        libraryConfiguration: MediaShareLibraryConfiguration? = nil
    ) {
        self.baseURL = baseURL
        self.auth = auth
        self.trustPin = trustPin
        self.displayName = displayName
        self.libraryConfiguration = libraryConfiguration
    }
}
