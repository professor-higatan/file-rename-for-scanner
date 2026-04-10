import Foundation

enum RenameService {
    struct PlanEntry {
        let url: URL
        let newName: String
    }

    struct Result {
        let applied: [URL]
        let failures: [(URL, String)]
    }

    /// 拡張子は元ファイルのまま。衝突時は連番サフィックスを付けない（失敗として返す）。
    static func buildPlan(
        files: [ScannedFile],
        prefix1: String,
        prefix2: String,
        rules: [StructureRangeRule],
        scanSequenceStart: Int,
        displayPageWidth: Int,
        scanSequenceWidth: Int,
        onlySelectedForStructure: Bool
    ) -> [PlanEntry] {
        var plan: [PlanEntry] = []

        for (idx, file) in files.enumerated() {
            let oneBased = idx + 1
            let (p3, p4): (String, String)
            if onlySelectedForStructure {
                if file.isSelected {
                    (p3, p4) = RenameNaming.prefix34(forSortedIndex: oneBased, rules: rules)
                } else {
                    (p3, p4) = ("", "")
                }
            } else {
                (p3, p4) = RenameNaming.prefix34(forSortedIndex: oneBased, rules: rules)
            }

            let scanSequence = scanSequenceStart + idx
            let displayPage = file.displayPage ?? scanSequence

            let stem = RenameNaming.stem(
                prefix1: prefix1,
                prefix2: prefix2,
                prefix3: p3,
                prefix4: p4,
                displayPage: displayPage,
                scanSequence: scanSequence,
                displayPageWidth: displayPageWidth,
                scanSequenceWidth: scanSequenceWidth
            )
            let ext = file.url.pathExtension
            let newName = ext.isEmpty ? stem : "\(stem).\(ext)"
            plan.append(PlanEntry(url: file.url, newName: newName))
        }

        return plan
    }

    /// 確認用: 衝突・重複・変更なしを検出する。
    static func validationIssues(for plan: [PlanEntry]) -> [String] {
        var issues: [String] = []
        var destCounts: [String: Int] = [:]

        for entry in plan {
            let dir = entry.url.deletingLastPathComponent()
            let dest = dir.appendingPathComponent(entry.newName).path
            destCounts[dest, default: 0] += 1
        }

        for (dest, count) in destCounts where count > 1 {
            issues.append("同じ名前に複数ファイルが割り当て: \(URL(fileURLWithPath: dest).lastPathComponent)")
        }

        for entry in plan {
            let dir = entry.url.deletingLastPathComponent()
            let dest = dir.appendingPathComponent(entry.newName)
            if entry.url.lastPathComponent == entry.newName {
                continue
            }
            if FileManager.default.fileExists(atPath: dest.path), dest.standardizedFileURL != entry.url.standardizedFileURL {
                issues.append("既存ファイルと衝突: \(entry.newName)")
            }
        }

        return issues
    }

    static func apply(plan: [PlanEntry]) -> Result {
        var applied: [URL] = []
        var failures: [(URL, String)] = []

        for entry in plan {
            let dir = entry.url.deletingLastPathComponent()
            var dest = dir.appendingPathComponent(entry.newName)
            if dest == entry.url {
                applied.append(entry.url)
                continue
            }
            if FileManager.default.fileExists(atPath: dest.path) {
                failures.append((entry.url, "既に存在: \(entry.newName)"))
                continue
            }
            do {
                try FileManager.default.moveItem(at: entry.url, to: dest)
                applied.append(dest)
            } catch {
                failures.append((entry.url, error.localizedDescription))
            }
        }

        return Result(applied: applied, failures: failures)
    }
}
