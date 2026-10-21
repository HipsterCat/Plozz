import Foundation

/// Bounded facts, not redacted free text. No field can hold an address or a header value.
public struct PlaybackFailureEvidence: Codable, Equatable, Sendable {
    public enum Route: String, Codable, Sendable { case none, nativeHLS, localHLS, software, audio }
    public enum NativeCapture: String, Codable, Sendable { case captured, noItem, timedOut, busy }

    public struct ErrorCode: Codable, Equatable, Sendable {
        public let domain: PlaybackFailureDiagnostic.Domain
        public let code: Int

        public init(domain: String?, code: Int) {
            self.domain = .init(domain)
            self.code = code
        }

        public var isValid: Bool { (Int(Int32.min)...Int(Int32.max)).contains(code) }

        public static func chain(_ error: NSError?) -> [Self] {
            var current = error
            var visited = Set<ObjectIdentifier>()
            var result: [Self] = []
            while let error = current, result.count < 8, visited.insert(ObjectIdentifier(error)).inserted {
                let value = Self(domain: error.domain, code: error.code)
                if value.isValid { result.append(value) }
                else { break }
                current = error.userInfo[NSUnderlyingErrorKey] as? NSError
            }
            return result
        }
    }

    public var route: Route?
    public var firstFrameReady: Bool?
    public var nativeCapture: NativeCapture?
    public var nativeErrors: [ErrorCode]
    public var nativeLogErrors: [ErrorCode]
    public var delivery: PlaybackDeliveryEvidence?

    public init(
        route: Route? = nil, firstFrameReady: Bool? = nil, nativeCapture: NativeCapture? = nil,
        nativeErrors: [ErrorCode] = [], nativeLogErrors: [ErrorCode] = [],
        delivery: PlaybackDeliveryEvidence? = nil
    ) {
        self.route = route
        self.firstFrameReady = firstFrameReady
        self.nativeCapture = nativeCapture
        self.nativeErrors = Array(nativeErrors.prefix(8))
        self.nativeLogErrors = Array(nativeLogErrors.suffix(4))
        self.delivery = delivery
    }

    public var isValid: Bool {
        nativeErrors.count <= 8 && nativeErrors.allSatisfy(\.isValid)
            && nativeLogErrors.count <= 4 && nativeLogErrors.allSatisfy(\.isValid)
            && delivery?.isValid != false
    }
}

public struct PlaybackDeliveryEvidence: Codable, Equatable, Sendable {
    public enum Resource: String, Codable, Sendable { case root, child }
    public enum Method: String, Codable, Sendable { case get, head }
    public enum Outcome: String, Codable, Sendable { case pending, receiving, complete, upstreamFailure, consumerClosed }
    public enum RangeResponse: String, Codable, Sendable { case absent, valid, invalid }

    public struct Playlist: Codable, Equatable, Sendable {
        public var hasHeader: Bool
        public var isMaster: Bool
        public var targetDurationMilliseconds: Int?
        public var maximumSegmentMilliseconds: Int?
        public var mediaSequence: Int?
        public var segments: Int
        public var hasEndList: Bool
        public var hasByteRanges: Bool
        public var hasMap: Bool
        public var hasEncryption: Bool

        public init(
            hasHeader: Bool, isMaster: Bool, targetDurationMilliseconds: Int?,
            maximumSegmentMilliseconds: Int?, mediaSequence: Int?, segments: Int,
            hasEndList: Bool, hasByteRanges: Bool, hasMap: Bool, hasEncryption: Bool
        ) {
            self.hasHeader = hasHeader
            self.isMaster = isMaster
            self.targetDurationMilliseconds = targetDurationMilliseconds
            self.maximumSegmentMilliseconds = maximumSegmentMilliseconds
            self.mediaSequence = mediaSequence
            self.segments = segments
            self.hasEndList = hasEndList
            self.hasByteRanges = hasByteRanges
            self.hasMap = hasMap
            self.hasEncryption = hasEncryption
        }

        public var isValid: Bool {
            (0...1_000_000).contains(segments)
                && targetDurationMilliseconds.map { (0...86_400_000).contains($0) } != false
                && maximumSegmentMilliseconds.map { (0...86_400_000).contains($0) } != false
                && mediaSequence.map { (0...9_007_199_254_740_991).contains($0) } != false
        }
    }

    public struct Request: Codable, Equatable, Sendable {
        public var sequence: Int
        public var resource: Resource
        public var method: Method
        public var startedMilliseconds: Int
        public var elapsedMilliseconds: Int = 0
        public var outcome: Outcome = .pending
        public var status: Int?
        public var format: PlaybackFailureDiagnostic.Format = .unknown
        public var redirected: Bool?
        public var crossOrigin: Bool?
        public var rangeRequested = false
        public var rangeResponse: RangeResponse = .absent
        public var expectedBytes: Int?
        public var receivedBytes = 0
        public var networkCode: Int?
        public var playlist: Playlist?

        public init(sequence: Int, resource: Resource, method: Method, startedMilliseconds: Int) {
            self.sequence = sequence
            self.resource = resource
            self.method = method
            self.startedMilliseconds = startedMilliseconds
        }

        public var isValid: Bool {
            (1...1_000_000).contains(sequence)
                && (0...86_400_000).contains(startedMilliseconds)
                && (0...86_400_000).contains(elapsedMilliseconds)
                && status.map { (100...599).contains($0) } != false
                && expectedBytes.map { (0...9_007_199_254_740_991).contains($0) } != false
                && (0...9_007_199_254_740_991).contains(receivedBytes)
                && networkCode.map { (Int(Int32.min)...Int(Int32.max)).contains($0) } != false
                && playlist?.isValid != false
        }
    }

    public var root: Request?
    public var firstFailure: Request?
    public var recent: [Request]

    public init(root: Request? = nil, firstFailure: Request? = nil, recent: [Request] = []) {
        self.root = root
        self.firstFailure = firstFailure
        self.recent = Array(recent.suffix(8))
    }

    public var isValid: Bool {
        root?.isValid != false && firstFailure?.isValid != false
            && recent.count <= 8 && recent.allSatisfy(\.isValid)
    }
}
