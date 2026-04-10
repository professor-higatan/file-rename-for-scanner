import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var vm = FolderRenameViewModel()
    @State private var showRenameConfirm = false
    @State private var confirmPlan: [RenameService.PlanEntry] = []
    @State private var confirmIssues: [String] = []
    @State private var unchangedCount: Int = 0

    var body: some View {
        NavigationSplitView {
            fileSidebar
        } detail: {
            HSplitView {
                previewColumn
                    .frame(minWidth: 320, idealWidth: 420)
                controlsColumn
                    .frame(minWidth: 380, idealWidth: 520)
            }
            .frame(minWidth: 960, minHeight: 560)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("フォルダを開く") { vm.chooseFolder() }
            }
            ToolbarItem(placement: .automatic) {
                Button("再読込") { vm.refresh() }
                    .disabled(vm.folderURL == nil)
            }
        }
        .sheet(isPresented: $showRenameConfirm) {
            RenameConfirmPlanSheet(
                plan: confirmPlan,
                issues: confirmIssues,
                unchangedCount: unchangedCount,
                onCancel: { showRenameConfirm = false },
                onConfirm: {
                    vm.applyRename(plan: confirmPlan)
                    showRenameConfirm = false
                }
            )
        }
        .overlay {
            if vm.isRunningOCR {
                OCRProgressOverlay(vm: vm)
            }
        }
    }

    private func presentRenameConfirmation() {
        let plan = vm.buildCurrentPlan()
        confirmPlan = plan
        confirmIssues = RenameService.validationIssues(for: plan)
        unchangedCount = plan.filter { $0.url.lastPathComponent == $0.newName }.count
        showRenameConfirm = true
    }

    private var fileSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let folder = vm.folderURL {
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
            }
            HStack {
                Text("画像一覧 (\(vm.files.count))")
                    .font(.headline)
                Spacer()
                Button("全選択") { vm.selectAll(true) }
                Button("全解除") { vm.selectAll(false) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Table(vm.files, selection: $vm.selectedFileURL) {
                TableColumn("選択") { (f: ScannedFile) in
                    Toggle("", isOn: Binding(
                        get: { vm.files.first(where: { $0.url == f.url })?.isSelected ?? false },
                        set: { _ in vm.toggleSelection(for: f.url) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                }
                .width(36)

                TableColumn("プレビュー") { (f: ScannedFile) in
                    ThumbnailView(url: f.url, size: CGSize(width: 44, height: 56))
                }
                .width(56)

                TableColumn("ファイル名") { (f: ScannedFile) in
                    Text(f.name)
                        .lineLimit(1)
                        .help(f.name)
                }

                TableColumn("#") { (f: ScannedFile) in
                    if let i = vm.files.firstIndex(where: { $0.url == f.url }) {
                        Text("\(i + 1)")
                    }
                }
                .width(32)

                TableColumn("OCR数値") { (f: ScannedFile) in
                    if let s = vm.files.first(where: { $0.url == f.url })?.suggestedPageNumber {
                        Text("\(s)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(52)

                TableColumn("OCRローマ") { (f: ScannedFile) in
                    if let row = vm.files.first(where: { $0.url == f.url }),
                       let rv = row.suggestedRomanValue {
                        let raw = row.suggestedRomanRaw ?? ""
                        Text(raw.isEmpty ? "\(rv)" : "\(raw)→\(rv)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(72)

                TableColumn("通し") { (f: ScannedFile) in
                    if let i = vm.files.firstIndex(where: { $0.url == f.url }) {
                        Text("\(vm.scanOrdinal(atIndex: i))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .width(40)

                TableColumn("表示") { (f: ScannedFile) in
                    TextField(
                        "＝通し",
                        text: Binding(
                            get: {
                                if let v = vm.files.first(where: { $0.url == f.url })?.displayPage {
                                    return "\(v)"
                                }
                                return ""
                            },
                            set: { s in
                                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                                if t.isEmpty {
                                    vm.setDisplayPage(for: f.url, value: nil)
                                } else if let v = Int(t) {
                                    vm.setDisplayPage(for: f.url, value: v)
                                }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                }
                .width(64)

                TableColumn("リネーム後") { (f: ScannedFile) in
                    Text(vm.previewStem(for: f))
                        .lineLimit(1)
                        .font(.caption.monospaced())
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
        .navigationSplitViewColumnWidth(min: 640, ideal: 780)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("プレビュー")
                .font(.headline)
            if let url = vm.selectedFileURL {
                LargePreviewView(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let idx = vm.selectedIndexOneBased, let u = vm.selectedFileURL,
                   let i = vm.files.firstIndex(where: { $0.url == u }) {
                    let scan = vm.scanOrdinal(atIndex: i)
                    let disp = vm.files[i].displayPage ?? scan
                    Text("一覧 #\(idx)/\(vm.files.count) ・ 通し \(scan) ・ 表示 \(disp)（空欄＝通しと同じ）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("画像を選択", systemImage: "photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }

    private var controlsColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                step1Section
                Divider()
                step2Section
            }
            .padding()
        }
    }

    private var step1Section: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ステップ1: 通し（スキャン順）と表示ページ")
                .font(.headline)

            Text(
                "通しはファイル一覧の並び順で決まります（スキャン時の連番がそのままベース）。ファイル名は「プレフィクス…_表示ページ_通し」です。表示ページの欄が空なら、表示は通しと同じ数字になります。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text(
                "空白ページでは通しだけ 1 つ進み、表示は前の印刷ページのままにしたいことが多いです。その行を選び「直前の表示をコピー」するか、表示列を手で揃えてください。OCR は主に表示ページの候補入力に使います。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text(
                "ローマ数字の前書きは「OCRローマ→表示」で数値化できます。誤読が多いときは手入力が確実です。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("全件を OCR") {
                    vm.runOCRAll()
                }
                .disabled(vm.isRunningOCR || vm.files.isEmpty)

                Button("選択のみ OCR") {
                    vm.runOCROnSelection()
                }
                .disabled(vm.isRunningOCR || vm.files.filter(\.isSelected).isEmpty)
            }

            HStack(spacing: 8) {
                Button("OCR数値→表示") { vm.applyArabicOCRToDisplayPage(selectionOnly: false) }
                Button("選択のみ") { vm.applyArabicOCRToDisplayPage(selectionOnly: true) }
            }
            .font(.caption)

            HStack(spacing: 8) {
                Button("OCRローマ→表示") { vm.applyRomanOCRToDisplayPage(selectionOnly: false) }
                Button("選択のみ") { vm.applyRomanOCRToDisplayPage(selectionOnly: true) }
            }
            .font(.caption)

            HStack(spacing: 8) {
                Button("表示をクリア（全件）") { vm.clearDisplayPages(selectionOnly: false) }
                Button("選択のみ") { vm.clearDisplayPages(selectionOnly: true) }
            }
            .font(.caption)

            Button("選択行に直前の表示をコピー（空白ページ向け）") {
                vm.copyPreviousEffectiveDisplayToSelection()
            }
            .font(.caption)
            .disabled(vm.files.filter(\.isSelected).isEmpty)

            HStack(alignment: .firstTextBaseline) {
                Text("通しの開始番号（先頭ファイルの通し）")
                    .font(.subheadline)
                Spacer()
                Stepper("\(vm.scanSequenceStart)", value: $vm.scanSequenceStart, in: 0...99999)
            }

            Stepper("表示ページの桁: \(vm.displayPageWidth)", value: $vm.displayPageWidth, in: 1...6)
            Stepper("通しの桁: \(vm.scanSequenceWidth)", value: $vm.scanSequenceWidth, in: 1...6)
        }
    }

    private var step2Section: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ステップ2: プレフィクスと構造ルール")
                .font(.headline)

            Group {
                labeledField("プレフィクス1（著者・タイトルなど）", text: $vm.prefix1)
                labeledField("プレフィクス2（発行年など）", text: $vm.prefix2)
            }

            Toggle("構造（3・4）はチェックしたファイルだけに適用", isOn: $vm.structureOnlyForSelectedFiles)
                .font(.subheadline)

            Text("一覧の #（スキャン順の並び）の範囲に 第n部・第m章 を割り当て。上から順に最初に一致したルールを使います。ファイル名の並びは常に …_表示_通し です。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(vm.structureRules) { rule in
                StructureRuleEditor(
                    rule: Binding(
                        get: { vm.structureRules.first(where: { $0.id == rule.id }) ?? rule },
                        set: { newValue in
                            if let i = vm.structureRules.firstIndex(where: { $0.id == rule.id }) {
                                vm.structureRules[i] = newValue
                            }
                        }
                    ),
                    onDelete: { vm.removeRule(id: rule.id) },
                    onFillFromSelection: { vm.applySelectionRangeToRule(ruleID: rule.id) }
                )
            }

            HStack {
                Button("ルールを追加") { vm.addRule() }
                Spacer()
            }

            if !vm.lastResultMessage.isEmpty {
                Text(vm.lastResultMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("リネーム内容を確認…") {
                presentRenameConfirmation()
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.files.isEmpty)
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - OCR 進捗

private struct OCRProgressOverlay: View {
    @ObservedObject var vm: FolderRenameViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.15)
                Text("OCR 実行中")
                    .font(.headline)
                Text("\(vm.ocrProgressCurrent) / \(vm.ocrProgressTotal)")
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.primary)
                Text(vm.ocrCurrentFileName.isEmpty ? "準備中…" : vm.ocrCurrentFileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .textSelection(.enabled)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        }
        .allowsHitTesting(true)
    }
}

// MARK: - リネーム確認（必須）

private struct RenameConfirmPlanSheet: View {
    let plan: [RenameService.PlanEntry]
    let issues: [String]
    let unchangedCount: Int
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var changeCount: Int {
        plan.filter { $0.url.lastPathComponent != $0.newName }.count
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("変更 \(changeCount) 件・名前そのまま \(unchangedCount) 件")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !issues.isEmpty {
                    Text("次を解消するまで実行できません。")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(issues, id: \.self) { issue in
                                Text("・ \(issue)")
                                    .font(.caption)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }

                List {
                    ForEach(plan, id: \.url) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.url.lastPathComponent)
                                .font(.caption.monospaced())
                                .foregroundStyle(entry.url.lastPathComponent == entry.newName ? .secondary : .primary)
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .imageScale(.small)
                                Text(entry.newName)
                                    .font(.caption.monospaced())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
            .navigationTitle("リネームの確認")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("リネーム実行") {
                        onConfirm()
                    }
                    .disabled(!issues.isEmpty)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 440)
    }
}

private struct StructureRuleEditor: View {
    @Binding var rule: StructureRangeRule
    var onDelete: () -> Void
    var onFillFromSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("一覧 # の範囲")
                    .font(.subheadline)
                Spacer()
                Button("選択に合わせる", action: onFillFromSelection)
                    .font(.caption)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            HStack {
                TextField("開始", value: $rule.startIndex, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                Text("〜")
                TextField("終了", value: $rule.endIndex, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
            }
            TextField("プレフィクス3（例: 第0部）", text: $rule.prefix3)
                .textFieldStyle(.roundedBorder)
            TextField("プレフィクス4（例: 第1章）", text: $rule.prefix4)
                .textFieldStyle(.roundedBorder)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct ThumbnailView: View {
    let url: URL
    var size: CGSize

    var body: some View {
        Group {
            if let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct LargePreviewView: View {
    let url: URL

    var body: some View {
        Group {
            if let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ContentUnavailableView("読み込めません", systemImage: "exclamationmark.triangle")
            }
        }
    }
}

#Preview {
    ContentView()
}
