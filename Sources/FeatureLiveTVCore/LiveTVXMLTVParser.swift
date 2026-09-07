#if DEBUG
import CryptoKit
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import zlib

public struct LiveTVGuideImport: Sendable {
    public let programs: [LiveTVPrototypeProgram]
    public let matchedChannelCount: Int
    public let guideChannelCount: Int
    public let programCount: Int
    public let coverageStart: Date?
    public let coverageEnd: Date?

    public init(
        programs: [LiveTVPrototypeProgram],
        matchedChannelCount: Int,
        guideChannelCount: Int,
        programCount: Int,
        coverageStart: Date?,
        coverageEnd: Date?
    ) {
        self.programs = programs
        self.matchedChannelCount = matchedChannelCount
        self.guideChannelCount = guideChannelCount
        self.programCount = programCount
        self.coverageStart = coverageStart
        self.coverageEnd = coverageEnd
    }
}

public struct LiveTVXMLTVParser: Sendable {
    public static let maximumCompressedBytes = 32 * 1_024 * 1_024
    public static let maximumExpandedBytes = 256 * 1_024 * 1_024
    public static let maximumGuideChannels = 20_000
    public static let maximumPrograms = 2_000_000
    public static let maximumTextLength = 16_384
    public static let maximumRetainedPrograms = 250_000
    public static let maximumRetainedTextBytes = 32 * 1_024 * 1_024

    private let maximumExpandedBytes: Int

    public init(maximumExpandedBytes: Int = Self.maximumExpandedBytes) {
        self.maximumExpandedBytes = maximumExpandedBytes
    }

    public func parse(
        gzipData: Data,
        channels: [LiveTVPrototypeChannel],
        now: Date
    ) throws -> LiveTVGuideImport {
        guard gzipData.count <= Self.maximumCompressedBytes else {
            throw LiveTVSourceImportError.guideTooLarge
        }
        let stream = InputStream(data: gzipData)
        stream.open()
        defer { stream.close() }
        let inflated = try BoundedGzipInputStream(
            compressedStream: stream,
            maximumExpandedBytes: maximumExpandedBytes
        )
        return try parseXML(stream: inflated, channels: channels, now: now)
    }

    public func parseXML(
        data: Data,
        channels: [LiveTVPrototypeChannel],
        now: Date
    ) throws -> LiveTVGuideImport {
        guard data.count <= maximumExpandedBytes else {
            throw LiveTVSourceImportError.guideTooLarge
        }
        let stream = InputStream(data: data)
        stream.open()
        defer { stream.close() }
        return try parseXML(stream: stream, channels: channels, now: now)
    }

    private func parseXML(
        stream: InputStream,
        channels: [LiveTVPrototypeChannel],
        now: Date
    ) throws -> LiveTVGuideImport {
        let delegate = XMLTVDelegate(channels: channels, now: now)
        let guardedStream = RejectingXMLInputStream(source: stream)
        let parser = XMLParser(stream: guardedStream)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        let parsed = parser.parse()
        if let streamError = guardedStream.streamError as? LiveTVSourceImportError {
            throw streamError
        }
        guard parsed, delegate.error == nil else {
            throw delegate.error ?? LiveTVSourceImportError.invalidGuide
        }
        return try delegate.makeResult()
    }
}

private final class XMLTVDelegate: NSObject, XMLParserDelegate {
    private let channels: [LiveTVPrototypeChannel]
    private let lowerBound: Date
    private let upperBound: Date
    private var guideChannels: [String: [String]] = [:]
    private var matches: [String: [LiveTVPrototypeChannel]]?
    private var retainedTextBytes = 0
    private var pendingPrograms: [PendingProgram] = []
    private var currentChannelID: String?
    private var currentChannelNames: [String] = []
    private var currentProgram: PendingProgram?
    private var currentElement: String?
    private var text = ""
    private var sawTV = false
    private var sourceProgramCount = 0
    private(set) var error: LiveTVSourceImportError?
    private(set) var coverageStart: Date?
    private(set) var coverageEnd: Date?

    init(channels: [LiveTVPrototypeChannel], now: Date) {
        self.channels = channels
        lowerBound = now.addingTimeInterval(-86_400)
        upperBound = now.addingTimeInterval(7 * 86_400)
    }

    func makeResult() throws -> LiveTVGuideImport {
        let matches = matches ?? LiveTVGuideMatcher().match(
            channels: channels,
            guideChannels: guideChannels
        )
        var seenProgramIDs = Set<String>()
        var programs: [LiveTVPrototypeProgram] = []
        for pending in pendingPrograms {
            try Task.checkCancellation()
            for channel in matches[pending.guideChannelID] ?? [] {
                let identifier = stableProgramID(
                    channelID: channel.id,
                    guideChannelID: pending.guideChannelID,
                    title: pending.title,
                    subtitle: pending.subtitle,
                    start: pending.start,
                    end: pending.end
                )
                guard seenProgramIDs.insert(identifier).inserted else { continue }
                guard programs.count < LiveTVXMLTVParser.maximumRetainedPrograms else {
                    throw LiveTVSourceImportError.guideTooLarge
                }
                programs.append(LiveTVPrototypeProgram(
                    id: identifier,
                    channelID: channel.id,
                    title: pending.title,
                    subtitle: pending.subtitle,
                    start: pending.start,
                    end: pending.end
                ))
            }
        }
        programs.sort {
            ($0.channelID, $0.start, $0.end, $0.title, $0.id)
                < ($1.channelID, $1.start, $1.end, $1.title, $1.id)
        }
        let matchedChannelIDs = Set(matches.values.flatMap { $0.map(\.id) })
        return LiveTVGuideImport(
            programs: programs,
            matchedChannelCount: matchedChannelIDs.count,
            guideChannelCount: guideChannels.count,
            programCount: programs.count,
            coverageStart: coverageStart,
            coverageEnd: coverageEnd
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard error == nil else {
            parser.abortParsing()
            return
        }
        if Task.isCancelled {
            error = .cancelled
            parser.abortParsing()
            return
        }
        switch elementName {
        case "tv":
            sawTV = true
        case "channel":
            guard sourceProgramCount == 0 else {
                error = .invalidGuide
                parser.abortParsing()
                return
            }
            guard let identifier = bounded(attributeDict["id"], maximum: 4_096),
                  guideChannels[identifier] != nil
                    || guideChannels.count < LiveTVXMLTVParser.maximumGuideChannels
            else {
                error = .guideTooLarge
                parser.abortParsing()
                return
            }
            currentChannelID = identifier
            currentChannelNames = []
        case "programme":
            if matches == nil {
                // XMLTV declares channels before programmes. Discard unmatched
                // listings while parsing instead of retaining the entire feed.
                matches = LiveTVGuideMatcher().match(channels: channels, guideChannels: guideChannels)
            }
            sourceProgramCount += 1
            guard sourceProgramCount <= LiveTVXMLTVParser.maximumPrograms else {
                error = .guideTooLarge
                parser.abortParsing()
                return
            }
            guard let guideChannelID = bounded(attributeDict["channel"], maximum: 4_096),
                  let startText = bounded(attributeDict["start"], maximum: 64),
                  let endText = bounded(attributeDict["stop"], maximum: 64),
                  let start = XMLTVDateParser.date(from: startText),
                  let end = XMLTVDateParser.date(from: endText),
                  end > start
            else {
                currentProgram = nil
                return
            }
            coverageStart = min(coverageStart ?? start, start)
            coverageEnd = max(coverageEnd ?? end, end)
            guard start < upperBound, end > lowerBound, matches?[guideChannelID] != nil else {
                currentProgram = nil
                return
            }
            currentProgram = PendingProgram(
                guideChannelID: guideChannelID,
                title: "",
                subtitle: "",
                start: start,
                end: end
            )
        case "display-name", "title", "sub-title":
            currentElement = elementName
            text = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentElement != nil else { return }
        guard text.count + string.count <= LiveTVXMLTVParser.maximumTextLength else {
            error = .guideTooLarge
            parser.abortParsing()
            return
        }
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else {
            error = .invalidGuide
            parser.abortParsing()
            return
        }
        self.parser(parser, foundCharacters: string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "display-name":
            if currentChannelID != nil, let value = normalizedText(text) {
                retainedTextBytes += value.utf8.count
                currentChannelNames.append(value)
            }
        case "channel":
            if let identifier = currentChannelID {
                guideChannels[identifier] = currentChannelNames
            }
            currentChannelID = nil
            currentChannelNames = []
        case "title":
            if let value = normalizedText(text) {
                currentProgram?.title = value
            }
        case "sub-title":
            if let value = normalizedText(text) {
                currentProgram?.subtitle = value
            }
        case "programme":
            if let program = currentProgram, !program.title.isEmpty {
                retainedTextBytes += program.title.utf8.count + program.subtitle.utf8.count
                pendingPrograms.append(program)
            }
            currentProgram = nil
        default:
            break
        }
        if currentElement == elementName {
            currentElement = nil
            text = ""
        }
        if retainedTextBytes > LiveTVXMLTVParser.maximumRetainedTextBytes
            || pendingPrograms.count > LiveTVXMLTVParser.maximumRetainedPrograms {
            error = .guideTooLarge
            parser.abortParsing()
        }
    }

    func parser(
        _ parser: XMLParser,
        resolveExternalEntityName name: String,
        systemID: String?
    ) -> Data? {
        nil
    }

    func parser(
        _ parser: XMLParser,
        foundInternalEntityDeclarationWithName name: String,
        value: String?
    ) {
        error = .invalidGuide
        parser.abortParsing()
    }

    func parser(
        _ parser: XMLParser,
        foundExternalEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?
    ) {
        error = .invalidGuide
        parser.abortParsing()
    }

    func parser(
        _ parser: XMLParser,
        foundUnparsedEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?,
        notationName: String?
    ) {
        error = .invalidGuide
        parser.abortParsing()
    }

    func parser(
        _ parser: XMLParser,
        foundNotationDeclarationWithName name: String,
        publicID: String?,
        systemID: String?
    ) {
        error = .invalidGuide
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if error == nil {
            error = Task.isCancelled ? .cancelled : .invalidGuide
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        if !sawTV, error == nil {
            error = .invalidGuide
        }
    }

    private func stableProgramID(
        channelID: String,
        guideChannelID: String,
        title: String,
        subtitle: String,
        start: Date,
        end: Date
    ) -> String {
        let components = [
            channelID,
            guideChannelID,
            title,
            subtitle,
            String(Int64(start.timeIntervalSince1970)),
            String(Int64(end.timeIntervalSince1970)),
        ]
        let digest = SHA256.hash(
            data: Data(components.joined(separator: "\u{1F}").utf8)
        )
        return "xmltv-" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private func normalizedText(_ text: String) -> String? {
        let result = text.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return result.isEmpty ? nil : result
    }

    private func bounded(_ text: String?, maximum: Int) -> String? {
        guard let text, !text.isEmpty, text.count <= maximum else { return nil }
        return text
    }
}

private struct PendingProgram {
    let guideChannelID: String
    var title: String
    var subtitle: String
    let start: Date
    let end: Date
}

public enum XMLTVDateParser {
    public static func date(from input: String) -> Date? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 14 else { return nil }
        let timestampEnd = trimmed.index(trimmed.startIndex, offsetBy: 14)
        let timestamp = trimmed[..<timestampEnd]
        guard timestamp.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        let remainder = trimmed[timestampEnd...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let offsetText: String
        if remainder.isEmpty {
            offsetText = "+0000"
        } else if remainder == "Z" {
            offsetText = "+0000"
        } else {
            guard remainder.count == 5,
                  ["+", "-"].contains(String(remainder.prefix(1))),
                  remainder.dropFirst().allSatisfy(\.isNumber)
            else { return nil }
            offsetText = remainder
        }
        let digits = Array(timestamp.utf8)
        func integer(_ start: Int, _ count: Int) -> Int {
            digits[start..<(start + count)].reduce(0) {
                $0 * 10 + Int($1 - 48)
            }
        }
        let year = integer(0, 4)
        let month = integer(4, 2)
        let day = integer(6, 2)
        let hour = integer(8, 2)
        let minute = integer(10, 2)
        let second = integer(12, 2)
        guard (1...9_999).contains(year),
              (1...12).contains(month),
              (1...daysInMonth(month, year: year)).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...60).contains(second),
              let offsetHours = Int(offsetText.dropFirst().prefix(2)),
              let offsetMinutes = Int(offsetText.suffix(2)),
              offsetHours <= 23,
              offsetMinutes <= 59
        else { return nil }
        let direction = offsetText.first == "-" ? -1 : 1
        let offset = direction * ((offsetHours * 60 + offsetMinutes) * 60)
        let seconds = daysFromCivil(year: year, month: month, day: day) * 86_400
            + hour * 3_600
            + minute * 60
            + second
            - offset
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 2:
            let leap = year.isMultiple(of: 4)
                && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let adjustedYear = year - (month <= 2 ? 1 : 0)
        let era = adjustedYear / 400
        let yearOfEra = adjustedYear - era * 400
        let adjustedMonth = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * adjustedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}

private final class BoundedGzipInputStream: InputStream {
    private let compressedStream: InputStream
    private let maximumExpandedBytes: Int
    private var zstream = z_stream()
    private let input = UnsafeMutablePointer<UInt8>.allocate(capacity: 64 * 1_024)
    private var output = [UInt8]()
    private var outputIndex = 0
    private var expandedBytes = 0
    private var reachedEnd = false
    private var failure: LiveTVSourceImportError?

    init(compressedStream: InputStream, maximumExpandedBytes: Int) throws {
        self.compressedStream = compressedStream
        self.maximumExpandedBytes = maximumExpandedBytes
        super.init(data: Data())
        let status = inflateInit2_(
            &zstream,
            15 + 32,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard status == Z_OK else {
            throw LiveTVSourceImportError.invalidGuide
        }
    }

    deinit {
        inflateEnd(&zstream)
        input.deallocate()
    }

    override var hasBytesAvailable: Bool {
        failure == nil && (outputIndex < output.count || !reachedEnd)
    }

    override var streamStatus: Stream.Status {
        if failure != nil { return .error }
        if reachedEnd && outputIndex >= output.count { return .atEnd }
        return .open
    }

    override var streamError: Error? {
        failure
    }

    override func open() {}
    override func close() {}

    override func read(
        _ buffer: UnsafeMutablePointer<UInt8>,
        maxLength len: Int
    ) -> Int {
        guard failure == nil else { return -1 }
        if Task.isCancelled {
            failure = .cancelled
            return -1
        }
        if outputIndex >= output.count, !fillOutput() {
            return failure == nil ? 0 : -1
        }
        let count = min(len, output.count - outputIndex)
        output.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            buffer.update(
                from: base.assumingMemoryBound(to: UInt8.self)
                    .advanced(by: outputIndex),
                count: count
            )
        }
        outputIndex += count
        return count
    }

    override func getBuffer(
        _ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
        length len: UnsafeMutablePointer<Int>
    ) -> Bool {
        false
    }

    private func fillOutput() -> Bool {
        output = []
        outputIndex = 0
        guard !reachedEnd else { return false }

        while output.isEmpty && !reachedEnd && failure == nil {
            if zstream.avail_in == 0 {
                let count = compressedStream.read(input, maxLength: 64 * 1_024)
                guard count > 0 else {
                    failure = .invalidGuide
                    break
                }
                zstream.next_in = input
                zstream.avail_in = uInt(count)
            }

            var chunk = [UInt8](repeating: 0, count: 64 * 1_024)
            let status: Int32 = chunk.withUnsafeMutableBytes {
                zstream.next_out = $0.baseAddress!
                    .assumingMemoryBound(to: Bytef.self)
                zstream.avail_out = uInt($0.count)
                return inflate(&zstream, Z_NO_FLUSH)
            }
            let produced = chunk.count - Int(zstream.avail_out)
            if produced > 0 {
                expandedBytes += produced
                guard expandedBytes <= maximumExpandedBytes else {
                    failure = .guideTooLarge
                    break
                }
                output = Array(chunk.prefix(produced))
            }
            if status == Z_STREAM_END {
                reachedEnd = true
            } else if status != Z_OK {
                failure = .invalidGuide
            }
        }
        return !output.isEmpty
    }
}

private final class RejectingXMLInputStream: InputStream {
    private static let forbidden = [
        Array("<!DOCTYPE".utf8),
        Array("<!ENTITY".utf8),
    ]

    private let source: InputStream
    private var carry: [UInt8] = []
    private var failure: LiveTVSourceImportError?

    init(source: InputStream) {
        self.source = source
        super.init(data: Data())
    }

    override var hasBytesAvailable: Bool {
        failure == nil && source.hasBytesAvailable
    }

    override var streamStatus: Stream.Status {
        failure == nil ? source.streamStatus : .error
    }

    override var streamError: Error? {
        failure ?? source.streamError
    }

    override func open() {}
    override func close() {}

    override func read(
        _ buffer: UnsafeMutablePointer<UInt8>,
        maxLength len: Int
    ) -> Int {
        guard failure == nil else { return -1 }
        let count = source.read(buffer, maxLength: len)
        guard count > 0 else { return count }
        var scanned = carry
        scanned.append(contentsOf: UnsafeBufferPointer(start: buffer, count: count))
        let uppercase = scanned.map { byte -> UInt8 in
            byte >= 97 && byte <= 122 ? byte - 32 : byte
        }
        if Self.forbidden.contains(where: { contains(uppercase, sequence: $0) }) {
            failure = .invalidGuide
            return -1
        }
        carry = Array(scanned.suffix(8))
        return count
    }

    override func getBuffer(
        _ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
        length len: UnsafeMutablePointer<Int>
    ) -> Bool {
        false
    }

    private func contains(_ bytes: [UInt8], sequence: [UInt8]) -> Bool {
        guard bytes.count >= sequence.count else { return false }
        for start in 0...(bytes.count - sequence.count) {
            if bytes[start..<(start + sequence.count)].elementsEqual(sequence) {
                return true
            }
        }
        return false
    }
}
#endif
