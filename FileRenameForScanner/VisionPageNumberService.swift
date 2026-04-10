import AppKit
import Vision

/// OCR によるページ番号候補（アラブ数字・ローマ数字→数値）。
struct PageOCRHints: Sendable {
    var arabic: Int?
    var romanValue: Int?
    var romanRaw: String?
}

/// スキャン画像のフッター付近からページ番号らしき表記を推定する（候補提示用）。
enum VisionPageNumberService {
    static func suggestPageHints(from imageURL: URL, completion: @escaping (PageOCRHints) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let img = NSImage(contentsOf: imageURL),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                DispatchQueue.main.async { completion(PageOCRHints()) }
                return
            }

            let height = CGFloat(cg.height)
            let request = VNRecognizeTextRequest { request, error in
                if error != nil {
                    DispatchQueue.main.async { completion(PageOCRHints()) }
                    return
                }
                let hints = extractHints(from: request, imageHeight: height)
                DispatchQueue.main.async { completion(hints) }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion(PageOCRHints()) }
            }
        }
    }

    private struct ScoredArabic {
        let value: Int
        let score: Double
    }

    private struct ScoredRoman {
        let value: Int
        let raw: String
        let score: Double
    }

    private static func extractHints(from request: VNRequest, imageHeight: CGFloat) -> PageOCRHints {
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            return PageOCRHints()
        }

        var arabics: [ScoredArabic] = []
        var romans: [ScoredRoman] = []

        for obs in observations {
            guard let top = obs.topCandidates(1).first else { continue }
            let text = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let box = obs.boundingBox
            let vertical = 1.0 - box.midY
            let confidence = Double(top.confidence)
            let baseScore = confidence * 0.55 + vertical * 0.4

            if let a = parseArabic(from: text) {
                arabics.append(ScoredArabic(value: a, score: baseScore + 0.05))
            }

            if let isolated = RomanNumeralParser.parseIsolatedRoman(text) {
                romans.append(ScoredRoman(value: isolated, raw: text, score: baseScore + 0.08))
            } else if let frag = RomanNumeralParser.parseRomanFragment(text) {
                romans.append(ScoredRoman(value: frag.value, raw: frag.raw, score: baseScore + 0.02))
            }
        }

        let bestArabic = pickBestArabic(arabics)
        let bestRoman = pickBestRoman(romans)

        return PageOCRHints(
            arabic: bestArabic?.value,
            romanValue: bestRoman?.value,
            romanRaw: bestRoman?.raw
        )
    }

    private static func parseArabic(from text: String) -> Int? {
        let normalized = text.replacingOccurrences(of: ",", with: "")
        let digitsOnly = normalized.filter { $0.isNumber }
        guard digitsOnly.count >= 1, digitsOnly.count <= 4,
              let v = Int(digitsOnly), v >= 0, v <= 9999
        else { return nil }
        return v
    }

    private static func pickBestArabic(_ candidates: [ScoredArabic]) -> ScoredArabic? {
        guard !candidates.isEmpty else { return nil }
        let grouped = Dictionary(grouping: candidates, by: \.value)
        let best = grouped.max { a, b in
            let sa = a.value.map(\.score).reduce(0, +)
            let sb = b.value.map(\.score).reduce(0, +)
            return sa < sb
        }
        return best?.value.max(by: { $0.score < $1.score })
    }

    private static func pickBestRoman(_ candidates: [ScoredRoman]) -> ScoredRoman? {
        guard !candidates.isEmpty else { return nil }
        let grouped = Dictionary(grouping: candidates, by: \.value)
        let best = grouped.max { a, b in
            let sa = a.value.map(\.score).reduce(0, +)
            let sb = b.value.map(\.score).reduce(0, +)
            return sa < sb
        }
        return best?.value.max(by: { $0.score < $1.score })
    }
}
