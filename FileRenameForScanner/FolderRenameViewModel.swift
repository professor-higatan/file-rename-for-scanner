import AppKit
import Combine
import Foundation

@MainActor
final class FolderRenameViewModel: ObservableObject {
    private var securityScopedFolder: URL?

    @Published var folderURL: URL?
    @Published var files: [ScannedFile] = []
    @Published var selectedFileURL: URL?
    @Published var prefix1: String = ""
    @Published var prefix2: String = ""
    @Published var structureRules: [StructureRangeRule] = []
    /// 通し番号（スキャン順）の先頭値。各行は「この値 + 一覧上の位置（0始まり）」。
    @Published var scanSequenceStart: Int = 1
    /// 表示ページのゼロ埋め桁数
    @Published var displayPageWidth: Int = 3
    /// 通し番号のゼロ埋め桁数
    @Published var scanSequenceWidth: Int = 3
    /// オンのとき、プレフィクス3・4（構造ルール）はチェック済みファイルにのみ適用。未選択は空。
    @Published var structureOnlyForSelectedFiles: Bool = false
    @Published var lastResultMessage: String = ""
    @Published var isRunningOCR: Bool = false
    /// OCR 進捗（1〜total）。順次処理で更新する。
    @Published var ocrProgressCurrent: Int = 0
    @Published var ocrProgressTotal: Int = 0
    @Published var ocrCurrentFileName: String = ""

    var selectedFile: ScannedFile? {
        guard let u = selectedFileURL else { return nil }
        return files.first { $0.url == u }
    }

    var selectedIndexOneBased: Int? {
        guard let u = selectedFileURL,
              let i = files.firstIndex(where: { $0.url == u }) else { return nil }
        return i + 1
    }

    func scanOrdinal(atIndex idx: Int) -> Int {
        scanSequenceStart + idx
    }

    func effectiveDisplay(for file: ScannedFile) -> Int? {
        guard let idx = files.firstIndex(where: { $0.url == file.url }) else { return nil }
        let scan = scanOrdinal(atIndex: idx)
        return file.displayPage ?? scan
    }

    func loadFolder(_ url: URL) {
        securityScopedFolder?.stopAccessingSecurityScopedResource()
        securityScopedFolder = url
        _ = url.startAccessingSecurityScopedResource()
        folderURL = url
        let urls = RenameNaming.naturalSortedFiles(in: url)
        files = urls.map { ScannedFile(url: $0) }
        selectedFileURL = files.first?.url
        lastResultMessage = "\(files.count) 件の画像を読み込みました。"
    }

    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let url = p.url {
            loadFolder(url)
        }
    }

    func refresh() {
        guard let f = folderURL else { return }
        let urls = RenameNaming.naturalSortedFiles(in: f)
        let selected = Set(files.filter(\.isSelected).map(\.url))
        let old = Dictionary(uniqueKeysWithValues: files.map { ($0.url, $0) })
        files = urls.map { u in
            let prev = old[u]
            return ScannedFile(
                url: u,
                isSelected: selected.contains(u),
                suggestedPageNumber: prev?.suggestedPageNumber,
                suggestedRomanValue: prev?.suggestedRomanValue,
                suggestedRomanRaw: prev?.suggestedRomanRaw,
                displayPage: prev?.displayPage
            )
        }
        if let s = selectedFileURL, !files.contains(where: { $0.url == s }) {
            selectedFileURL = files.first?.url
        }
    }

    func toggleSelection(for url: URL) {
        guard let i = files.firstIndex(where: { $0.url == url }) else { return }
        files[i].isSelected.toggle()
    }

    func selectAll(_ on: Bool) {
        for i in files.indices {
            files[i].isSelected = on
        }
    }

    /// 現在の選択ファイルの一覧順（1始まり）をルール行にコピー
    func applySelectionRangeToRule(ruleID: UUID) {
        guard let idx = structureRules.firstIndex(where: { $0.id == ruleID }) else { return }
        let selectedIndices = files.enumerated().filter { $0.element.isSelected }.map { $0.offset + 1 }
        guard let mn = selectedIndices.min(), let mx = selectedIndices.max() else { return }
        structureRules[idx].startIndex = mn
        structureRules[idx].endIndex = mx
    }

    func addRule() {
        let n = files.count
        let end = max(1, n)
        structureRules.append(StructureRangeRule(startIndex: 1, endIndex: end, prefix3: "", prefix4: ""))
    }

    func removeRule(id: UUID) {
        structureRules.removeAll { $0.id == id }
    }

    func previewStem(for file: ScannedFile) -> String {
        guard let idx = files.firstIndex(where: { $0.url == file.url }) else { return "" }
        let oneBased = idx + 1
        let scanSequence = scanOrdinal(atIndex: idx)
        let displayPage = file.displayPage ?? scanSequence
        let (p3, p4): (String, String)
        if structureOnlyForSelectedFiles {
            if file.isSelected {
                (p3, p4) = RenameNaming.prefix34(forSortedIndex: oneBased, rules: structureRules)
            } else {
                (p3, p4) = ("", "")
            }
        } else {
            (p3, p4) = RenameNaming.prefix34(forSortedIndex: oneBased, rules: structureRules)
        }
        return RenameNaming.stem(
            prefix1: prefix1,
            prefix2: prefix2,
            prefix3: p3,
            prefix4: p4,
            displayPage: displayPage,
            scanSequence: scanSequence,
            displayPageWidth: displayPageWidth,
            scanSequenceWidth: scanSequenceWidth
        )
    }

    func buildCurrentPlan() -> [RenameService.PlanEntry] {
        RenameService.buildPlan(
            files: files,
            prefix1: prefix1,
            prefix2: prefix2,
            rules: structureRules,
            scanSequenceStart: scanSequenceStart,
            displayPageWidth: displayPageWidth,
            scanSequenceWidth: scanSequenceWidth,
            onlySelectedForStructure: structureOnlyForSelectedFiles
        )
    }

    func applyRename(plan: [RenameService.PlanEntry]) {
        let result = RenameService.apply(plan: plan)
        if result.failures.isEmpty {
            lastResultMessage = "\(result.applied.count) 件をリネームしました。"
        } else {
            lastResultMessage = "成功 \(result.applied.count) / 失敗 \(result.failures.count)\n" +
                result.failures.prefix(5).map { "\($0.0.lastPathComponent): \($0.1)" }.joined(separator: "\n")
        }
        refresh()
    }

    func setDisplayPage(for url: URL, value: Int?) {
        guard let i = files.firstIndex(where: { $0.url == url }) else { return }
        files[i].displayPage = value
    }

    func clearDisplayPages(selectionOnly: Bool) {
        for i in files.indices {
            if selectionOnly && !files[i].isSelected { continue }
            files[i].displayPage = nil
        }
        lastResultMessage = selectionOnly ? "選択行の表示ページをクリアしました（通しに追従）。"
            : "表示ページをすべてクリアしました（通しに追従）。"
    }

    /// 空白ページ用: 選択された行について、ひとつ前の行の実効表示ページをコピーする（通しはそのまま）。
    func copyPreviousEffectiveDisplayToSelection() {
        let indices = files.enumerated()
            .filter { $0.element.isSelected }
            .map(\.offset)
            .sorted()
        var n = 0
        for idx in indices {
            guard idx > 0 else { continue }
            let prev = files[idx - 1]
            let prevScan = scanOrdinal(atIndex: idx - 1)
            let prevDisplay = prev.displayPage ?? prevScan
            files[idx].displayPage = prevDisplay
            n += 1
        }
        lastResultMessage = "選択行に直前行の表示ページ（実効）を設定: \(n) 件。"
    }

    func applyArabicOCRToDisplayPage(selectionOnly: Bool) {
        var count = 0
        for i in files.indices {
            if selectionOnly && !files[i].isSelected { continue }
            if let a = files[i].suggestedPageNumber {
                files[i].displayPage = a
                count += 1
            }
        }
        lastResultMessage = "OCR（アラビア）を表示ページに反映: \(count) 件。"
    }

    func applyRomanOCRToDisplayPage(selectionOnly: Bool) {
        var count = 0
        for i in files.indices {
            if selectionOnly && !files[i].isSelected { continue }
            if let r = files[i].suggestedRomanValue {
                files[i].displayPage = r
                count += 1
            }
        }
        lastResultMessage = "OCR（ローマ→数値）を表示ページに反映: \(count) 件。"
    }

    func runOCROnSelection() {
        let targets = files.filter(\.isSelected)
        guard !targets.isEmpty else {
            lastResultMessage = "OCR 対象を選択してください。"
            return
        }
        runOCR(urls: targets.map(\.url))
    }

    func runOCRAll() {
        guard !files.isEmpty else {
            lastResultMessage = "フォルダに画像がありません。"
            return
        }
        runOCR(urls: files.map(\.url))
    }

    private func runOCR(urls: [URL]) {
        guard !urls.isEmpty else { return }
        ocrProgressTotal = urls.count
        ocrProgressCurrent = 0
        ocrCurrentFileName = ""
        isRunningOCR = true

        Task { @MainActor in
            defer {
                isRunningOCR = false
                ocrCurrentFileName = ""
                ocrProgressCurrent = 0
                ocrProgressTotal = 0
            }

            for (idx, u) in urls.enumerated() {
                ocrProgressCurrent = idx + 1
                ocrCurrentFileName = u.lastPathComponent
                let hints = await fetchPageHints(from: u)
                if let i = files.firstIndex(where: { $0.url == u }) {
                    files[i].suggestedPageNumber = hints.arabic
                    files[i].suggestedRomanValue = hints.romanValue
                    files[i].suggestedRomanRaw = hints.romanRaw
                }
            }

            lastResultMessage =
                "OCR 完了（\(urls.count) 件）。通しはスキャン順で固定。表示ページは OCR または手入力で調整してください。"
        }
    }

    private func fetchPageHints(from url: URL) async -> PageOCRHints {
        await withCheckedContinuation { continuation in
            VisionPageNumberService.suggestPageHints(from: url) { hints in
                continuation.resume(returning: hints)
            }
        }
    }
}
