import Foundation

/// The foreground-color subset of WebVTT CSS. Unsupported selectors/properties
/// stay unsupported; they must not accidentally become global color rules.
struct WebVTTColorStyles {
    private struct Selector {
        let isRoot: Bool
        let element: String?
        let classes: [String]

        init?(_ text: String) {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text == "::cue" {
                isRoot = true
                element = nil
                classes = []
                return
            }
            guard text.hasPrefix("::cue("), text.hasSuffix(")") else { return nil }
            let argument = text.dropFirst(6).dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = argument.components(separatedBy: ".")
            let tag = parts[0]
            guard tag.isEmpty || tag == "*" || SubtitleMarkup.webVTTElements.contains(tag) else { return nil }
            let names = Array(parts.dropFirst())
            guard !tag.isEmpty || !names.isEmpty,
                  names.allSatisfy({
                      $0.range(of: #"^-?[_a-zA-Z][_a-zA-Z0-9-]*$"#, options: .regularExpression) != nil
                  }) else { return nil }
            isRoot = false
            element = tag.isEmpty || tag == "*" ? nil : tag
            classes = names
        }

        func matches(element: String?, classes: [String]) -> Bool {
            if isRoot { return element == nil }
            guard let element else { return false }
            return (self.element == nil || self.element == element)
                && self.classes.allSatisfy(classes.contains)
        }
    }

    private enum Value {
        case color(SubtitleColor)
        case inherited

        init?(_ text: String) {
            switch text.lowercased() {
            case "inherit", "unset", "currentcolor": self = .inherited
            default:
                guard let color = SubtitleColor(css: text) else { return nil }
                self = .color(color)
            }
        }
    }

    private struct Rule {
        let selector: Selector
        let value: Value
        let important: Bool
    }

    private var rules: [Rule] = []

    mutating func append(_ css: String) {
        let css = css.replacingOccurrences(
            of: #"(?s)/\*.*?(?:\*/|$)"#, with: "", options: .regularExpression
        )
        var selector = ""
        var body = ""
        var depth = 0
        var quote: Character?
        var escaped = false
        for character in css {
            if let currentQuote = quote {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == currentQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "{" {
                depth += 1
                if depth == 1 { continue }
            } else if character == "}" {
                guard depth > 0 else { selector = ""; continue }
                depth -= 1
                if depth == 0 {
                    appendRule(selector: selector, body: body)
                    selector = ""
                    body = ""
                    continue
                }
            } else if character == ";", depth == 0 {
                // In particular, never load an external @import stylesheet.
                selector = ""
                continue
            }
            if depth == 0 { selector.append(character) }
            else { body.append(character) }
        }
    }

    private mutating func appendRule(selector text: String, body: String) {
        let selectors = text.components(separatedBy: ",").map(Selector.init)
        guard !selectors.isEmpty, selectors.allSatisfy({ $0 != nil }) else { return }
        for declaration in Self.declarations(body) {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "color"
            else { continue }
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let importantRange = value.range(of: #"(?i)!\s*important\s*$"#, options: .regularExpression)
            if let importantRange {
                value = String(value[..<importantRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let parsed = Value(value) else { continue }
            for selector in selectors.compactMap({ $0 }) {
                rules.append(Rule(selector: selector, value: parsed, important: importantRange != nil))
            }
        }
    }

    private static func declarations(_ body: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var parentheses = 0
        for character in body {
            if let currentQuote = quote {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == currentQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "(" {
                parentheses += 1
            } else if character == ")" {
                parentheses = max(0, parentheses - 1)
            } else if character == ";", parentheses == 0 {
                result.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        result.append(current)
        return result
    }

    func color(element: String? = nil, classes: [String] = [], inherited: SubtitleColor? = nil) -> SubtitleColor? {
        // Keep legacy class aliases separate from literal CSS/HTML color names.
        var result = classes.lazy.compactMap {
            $0 == "green" ? SubtitleColor.green : SubtitleColor(markup: $0)
        }.first ?? inherited
        var priority = (-1, -1, -1, -1)
        for (index, rule) in rules.enumerated() where rule.selector.matches(element: element, classes: classes) {
            let candidate = (
                rule.important ? 1 : 0, rule.selector.classes.count,
                rule.selector.element == nil ? 0 : 1, index
            )
            guard candidate > priority else { continue }
            priority = candidate
            switch rule.value {
            case .color(let color): result = color
            case .inherited: result = inherited
            }
        }
        return result
    }
}
