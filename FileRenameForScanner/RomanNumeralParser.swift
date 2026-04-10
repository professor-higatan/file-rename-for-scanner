import Foundation

/// 印刷ページのローマ数字（例: xvii, XVII）をアラブ数字に変換する。IV / IX など減算記法に対応。
enum RomanNumeralParser {
    private static let values: [(Character, Int)] = [
        ("M", 1000), ("D", 500), ("C", 100), ("L", 50),
        ("X", 10), ("V", 5), ("I", 1)
    ]

    /// 文字列全体がローマ数字として解釈できるとき、その値を返す。
    static func parseIsolatedRoman(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let stripped = trimmed
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "・", with: "")
            .uppercased()

        let letters = stripped.filter { "IVXLCDM".contains($0) }
        guard !letters.isEmpty, letters.count == stripped.filter({ $0.isLetter }).count else { return nil }
        guard letters.count <= 15 else { return nil }

        return parseRomanLetters(String(letters))
    }

    /// OCR の断片から、ローマ数字っぽい部分を抜き出して解析する（例: "— xvii —"）。
    static func parseRomanFragment(_ raw: String) -> (value: Int, raw: String)? {
        let upper = raw.uppercased()
        let pattern = "[IVXLCDM]{1,15}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(upper.startIndex..., in: upper)
        guard let m = regex.firstMatch(in: upper, options: [], range: range),
              let r = Range(m.range, in: upper)
        else { return nil }
        let slice = String(upper[r])
        guard let v = parseRomanLetters(slice) else { return nil }
        return (v, slice.lowercased())
    }

    private static func parseRomanLetters(_ s: String) -> Int? {
        var i = s.startIndex
        var total = 0
        let str = String(s)

        while i < str.endIndex {
            let c = str[i]
            guard let current = value(of: c) else { return nil }
            let nextIndex = str.index(after: i)
            if nextIndex < str.endIndex {
                let n = str[nextIndex]
                if let nextVal = value(of: n), nextVal > current {
                    guard let pair = subtractivePair(c, n) else { return nil }
                    total += pair
                    i = str.index(after: nextIndex)
                    continue
                }
            }
            total += current
            i = nextIndex
        }

        guard total > 0, total <= 3999 else { return nil }
        return total
    }

    private static func value(of c: Character) -> Int? {
        values.first { $0.0 == c }?.1
    }

    private static func subtractivePair(_ a: Character, _ b: Character) -> Int? {
        let pairs: [String: Int] = [
            "IV": 4, "IX": 9, "XL": 40, "XC": 90, "CD": 400, "CM": 900
        ]
        return pairs[String([a, b])]
    }
}
