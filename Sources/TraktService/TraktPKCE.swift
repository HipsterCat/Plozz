import CoreTrackerAuth
import Foundation

typealias TraktPKCE = TrackerPKCE

extension TrackerPKCE {
    init(
        config: TraktConfig,
        verifier: String = TrackerPKCE.randomValue(),
        state: String = TrackerPKCE.randomValue()
    ) throws {
        try self.init(
            clientID: config.clientID,
            authorizationEndpoint: config.authBaseURL.appendingPathComponent("oauth/authorize"),
            redirectURI: config.redirectURI,
            verifier: verifier,
            state: state
        )
    }
}
