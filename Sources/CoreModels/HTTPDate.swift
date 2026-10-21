import Foundation

public enum HTTPDate {
    private static let formatters: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
        "EEEE, dd-MMM-yy HH:mm:ss 'GMT'",
        "EEE MMM d HH:mm:ss yyyy"
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    public static func parse(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return formatters.lazy.compactMap { $0.date(from: trimmed) }.first
    }

    public static func string(from date: Date) -> String {
        formatters[0].string(from: date)
    }

    public static func retryAfter(_ value: String?, now: Date = .now) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.utf8.allSatisfy({ (48...57).contains($0) }) {
            guard let seconds = TimeInterval(value), seconds.isFinite else { return nil }
            return seconds
        }
        return parse(value).map { max(0, $0.timeIntervalSince(now)) }
    }
}
