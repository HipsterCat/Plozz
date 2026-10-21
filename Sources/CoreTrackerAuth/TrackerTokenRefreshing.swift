public protocol TrackerTokenRefreshing: Sendable {
    func refresh(_ refreshToken: String) async throws -> TrackerTokens
}
