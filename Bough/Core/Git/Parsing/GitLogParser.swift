import Foundation

/// Parses the single-commit record emitted by GitRepository.lastCommit():
/// `%H%x1f%h%x1f%an%x1f%ae%x1f%at%x1f%s%x1f%b%x1e` (unit separator fields,
/// record separator terminator; body is everything after the 6th field).
enum GitLogParser {
    /// History records: `%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%s%x1e`
    /// (parents are space-separated inside field 3; git joins records with newlines,
    /// so each record is trimmed before splitting).
    static func parseHistory(_ text: String) -> [Commit] {
        text.split(separator: "\u{1e}", omittingEmptySubsequences: true).compactMap { rawRecord in
            let record = String(rawRecord).trimmingCharacters(in: .whitespacesAndNewlines)
            let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard fields.count == 7 else { return nil }
            let parents = fields[2].split(separator: " ").map(String.init)
            return Commit(
                sha: String(fields[0]),
                shortSha: String(fields[1]),
                authorName: String(fields[3]),
                authorEmail: String(fields[4]),
                timestamp: Int(fields[5]) ?? 0,
                subject: String(fields[6]),
                body: "",
                parents: parents
            )
        }
    }

    static func parseSingle(_ text: String) -> Commit? {
        guard let record = text.split(separator: "\u{1e}", omittingEmptySubsequences: true).first else {
            return nil
        }
        let fields = record.split(separator: "\u{1f}", maxSplits: 6, omittingEmptySubsequences: false)
        guard fields.count == 7 else { return nil }
        let timestamp = Int(fields[4]) ?? 0
        return Commit(
            sha: String(fields[0]),
            shortSha: String(fields[1]),
            authorName: String(fields[2]),
            authorEmail: String(fields[3]),
            timestamp: timestamp,
            subject: String(fields[5]),
            body: String(fields[6])
        )
    }
}
