import Foundation

/// Detects Google's Antigravity (Gemini) agent. Its conversation logs live in
/// `~/.gemini/antigravity-cli/conversations/*.db`, but token counts are stored in
/// opaque protobuf blobs that Antigravity does not expose in a readable form. We
/// therefore detect the agent and surface an explanatory note rather than
/// reporting fabricated numbers.
final class AntigravityScanner: AgentScanner {
    let kind: AgentKind = .antigravity

    private var candidates: [URL] {
        [".gemini/antigravity-cli", ".antigravity-ide", ".gemini/antigravity"]
            .map { home.appendingPathComponent($0) }
    }

    func scan() -> ScanResult {
        let installed = candidates.contains { FileManager.default.fileExists(atPath: $0.path) }
        guard installed else {
            return ScanResult(kind: kind, installed: false, records: [], note: nil)
        }
        return ScanResult(
            kind: kind,
            installed: true,
            records: [],
            note: "Detected. Antigravity keeps token usage server-side (Google account) — nothing readable locally."
        )
    }
}
