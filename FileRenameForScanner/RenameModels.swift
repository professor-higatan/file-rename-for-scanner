import Foundation

struct ScannedFile: Identifiable, Hashable {
    var id: URL { url }
    var url: URL
    var isSelected: Bool
    /// OCR: アラブ数字のページ候補
    var suggestedPageNumber: Int?
    /// OCR: ローマ数字から変換した数値候補
    var suggestedRomanValue: Int?
    /// OCR: 解釈したローマ数字の表記（小文字）
    var suggestedRomanRaw: String?
    /// ファイル名に使う「表示ページ」（印刷ページ相当）。nil のときは通し（スキャン順の番号）と同じ値を使う。
    var displayPage: Int?

    init(
        url: URL,
        isSelected: Bool = true,
        suggestedPageNumber: Int? = nil,
        suggestedRomanValue: Int? = nil,
        suggestedRomanRaw: String? = nil,
        displayPage: Int? = nil
    ) {
        self.url = url
        self.isSelected = isSelected
        self.suggestedPageNumber = suggestedPageNumber
        self.suggestedRomanValue = suggestedRomanValue
        self.suggestedRomanRaw = suggestedRomanRaw
        self.displayPage = displayPage
    }

    var name: String { url.lastPathComponent }
}

/// 通し番号（1始まり）の範囲に 第n部・第n章 などを割り当てる。先頭から最初に一致したルールを採用する。
struct StructureRangeRule: Identifiable, Hashable {
    let id: UUID
    var startIndex: Int
    var endIndex: Int
    var prefix3: String
    var prefix4: String

    init(
        id: UUID = UUID(),
        startIndex: Int,
        endIndex: Int,
        prefix3: String,
        prefix4: String
    ) {
        self.id = id
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.prefix3 = prefix3
        self.prefix4 = prefix4
    }
}

enum RenameNaming {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "heic", "webp"]

    static func naturalSortedFiles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let images = urls.filter { url in
            guard let isFile = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile == true else {
                return false
            }
            let ext = url.pathExtension.lowercased()
            return imageExtensions.contains(ext)
        }

        return images.sorted { a, b in
            a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
    }

    /// プレフィクス1〜4・表示ページ・通し（スキャン順）を `_` でつないだファイル名（拡張子除く）。プレフィクスで空の段は省略する。
    static func stem(
        prefix1: String,
        prefix2: String,
        prefix3: String,
        prefix4: String,
        displayPage: Int,
        scanSequence: Int,
        displayPageWidth: Int,
        scanSequenceWidth: Int
    ) -> String {
        let parts = [prefix1, prefix2, prefix3, prefix4].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let dw = max(1, displayPageWidth)
        let sw = max(1, scanSequenceWidth)
        let d = String(format: "%0\(dw)d", displayPage)
        let s = String(format: "%0\(sw)d", scanSequence)
        if parts.isEmpty { return "\(d)_\(s)" }
        return parts.joined(separator: "_") + "_" + d + "_" + s
    }

    static func prefix34(forSortedIndex oneBasedIndex: Int, rules: [StructureRangeRule]) -> (String, String) {
        for rule in rules {
            if oneBasedIndex >= rule.startIndex && oneBasedIndex <= rule.endIndex {
                return (rule.prefix3, rule.prefix4)
            }
        }
        return ("", "")
    }
}
