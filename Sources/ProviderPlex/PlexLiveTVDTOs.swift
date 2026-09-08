import Foundation

struct PlexLiveTVScalar: Decodable, Sendable {
    let string: String

    var integer: Int? { Int(string) }
    var number: Double? { Double(string).flatMap { $0.isFinite ? $0 : nil } }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let text = try? value.decode(String.self) { string = text }
        else if let integer = try? value.decode(Int64.self) { string = String(integer) }
        else if let number = try? value.decode(Double.self), number.isFinite { string = String(number) }
        else if let flag = try? value.decode(Bool.self) { string = flag ? "1" : "0" }
        else {
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Expected scalar")
        }
    }
}

struct PlexLiveTVResponse: Decodable, Sendable {
    let MediaContainer: PlexLiveTVContainer
}

struct PlexLiveTVContainer: Decodable, Sendable {
    let size: PlexLiveTVScalar?
    let totalSize: PlexLiveTVScalar?
    let MediaProvider: [PlexLiveTVMediaProviderDTO]?
    let DVR: [PlexLiveTVDVRDTO]?
    let Dvr: [PlexLiveTVDVRDTO]?
    let Channel: [PlexLiveTVChannelDTO]?
    let Metadata: [PlexLiveTVProgrammeDTO]?
}

struct PlexLiveTVMediaProviderDTO: Decodable, Sendable {
    struct FeatureDTO: Decodable, Sendable {
        let type: String?
        let key: String?
    }
    let identifier: String?
    let providerIdentifier: String?
    let protocols: String?
    let Feature: [FeatureDTO]?
}

struct PlexLiveTVDVRDTO: Decodable, Sendable {
    let key: PlexLiveTVScalar?
    let uuid: String?
    let lineup: String?
}

struct PlexLiveTVChannelDTO: Decodable, Sendable {
    let id: PlexLiveTVScalar?
    let gridKey: String?
    let vcn: PlexLiveTVScalar?
    let title: String?
    let callSign: String?
    let thumb: String?
}

struct PlexLiveTVProgrammeDTO: Decodable, Sendable {
    struct GenreDTO: Decodable, Sendable {
        let tag: String?
    }
    let ratingKey: PlexLiveTVScalar?
    let key: String?
    let guid: String?
    let title: String?
    let grandparentTitle: String?
    let summary: String?
    let thumb: String?
    let Genre: [GenreDTO]?
    let Media: [PlexLiveTVAiringDTO]?
}

struct PlexLiveTVAiringDTO: Decodable, Sendable {
    let beginsAt: PlexLiveTVScalar?
    let endsAt: PlexLiveTVScalar?
    let duration: PlexLiveTVScalar?
    let channelIdentifier: PlexLiveTVScalar?
    let gridKey: String?
    let `protocol`: String?
}
