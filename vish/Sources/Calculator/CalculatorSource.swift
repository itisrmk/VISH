import Foundation

struct CalculatorSource: SearchSource {
    func search(_ query: String) -> [SearchResult] {
        guard query.contains(where: { "+-*/%^()".contains($0) }) else { return [] }

        var parser = ExpressionParser(query)
        guard let value = parser.parse(), value.isFinite else { return [] }

        let rendered = value.rounded() == value ? String(Int64(value)) : String(value)
        return [SearchResult(
            id: "calculator:\(query)",
            kind: .calculator,
            title: rendered,
            subtitle: "Copy result",
            score: 0.8,
            action: .copy(rendered)
        )]
    }
}

private struct ExpressionParser {
    private let text: String
    private var index: String.Index

    init(_ text: String) {
        self.text = text
        index = text.startIndex
    }

    mutating func parse() -> Double? {
        guard let value = expression() else { return nil }
        skipSpaces()
        return index == text.endIndex ? value : nil
    }

    private mutating func expression() -> Double? {
        guard var value = term() else { return nil }

        while true {
            skipSpaces()
            if consume("+") {
                guard let rhs = term() else { return nil }
                value += rhs
            } else if consume("-") {
                guard let rhs = term() else { return nil }
                value -= rhs
            } else {
                return value
            }
        }
    }

    private mutating func term() -> Double? {
        guard var value = power() else { return nil }

        while true {
            skipSpaces()
            if consume("*") {
                guard let rhs = power() else { return nil }
                value *= rhs
            } else if consume("/") {
                guard let rhs = power(), rhs != 0 else { return nil }
                value /= rhs
            } else if consume("%") {
                guard let rhs = power(), rhs != 0 else { return nil }
                value.formTruncatingRemainder(dividingBy: rhs)
            } else {
                return value
            }
        }
    }

    private mutating func power() -> Double? {
        guard let base = unary() else { return nil }
        skipSpaces()
        guard consume("^") else { return base }
        guard let exponent = power() else { return nil }
        return pow(base, exponent)
    }

    private mutating func unary() -> Double? {
        skipSpaces()
        if consume("+") { return unary() }
        if consume("-") { return unary().map { -$0 } }
        return primary()
    }

    private mutating func primary() -> Double? {
        skipSpaces()
        if consume("(") {
            guard let value = expression() else { return nil }
            skipSpaces()
            return consume(")") ? value : nil
        }
        return number()
    }

    private mutating func number() -> Double? {
        skipSpaces()
        let start = index
        var hasDigit = false
        var hasDot = false

        while index < text.endIndex {
            let character = text[index]
            if character.isNumber {
                hasDigit = true
                text.formIndex(after: &index)
            } else if character == ".", !hasDot {
                hasDot = true
                text.formIndex(after: &index)
            } else {
                break
            }
        }

        guard hasDigit else { return nil }
        return Double(text[start..<index])
    }

    private mutating func consume(_ character: Character) -> Bool {
        guard index < text.endIndex, text[index] == character else { return false }
        text.formIndex(after: &index)
        return true
    }

    private mutating func skipSpaces() {
        while index < text.endIndex, text[index].isWhitespace {
            text.formIndex(after: &index)
        }
    }
}
