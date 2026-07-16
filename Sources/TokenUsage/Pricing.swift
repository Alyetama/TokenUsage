import Foundation

/// Rough public list prices, in US dollars per **million** tokens, used to
/// estimate spend for agents that don't record a cost themselves (Claude, Codex,
/// Kimi, Antigravity). opencode and MiniMax report real costs, which are always
/// preferred over these estimates.
///
/// Prices are approximate and matched by a substring of the model id. They exist
/// to give a sense of relative spend, not an invoice — hence costs are always
/// shown with a "≈".
enum Pricing {
    struct Rate {
        var input: Double
        var output: Double
        var cacheRead: Double
        var cacheWrite: Double
    }

    /// Ordered so the most specific model substrings are matched first.
    private static let table: [(match: String, rate: Rate)] = [
        // Anthropic Claude (cache read ≈ 0.1× input, cache write ≈ 1.25× input)
        ("fable",   Rate(input: 10,   output: 50,  cacheRead: 1.0,  cacheWrite: 12.5)),
        ("mythos",  Rate(input: 10,   output: 50,  cacheRead: 1.0,  cacheWrite: 12.5)),
        ("opus",    Rate(input: 5,    output: 25,  cacheRead: 0.50, cacheWrite: 6.25)),
        ("sonnet",  Rate(input: 3,    output: 15,  cacheRead: 0.30, cacheWrite: 3.75)),
        ("haiku",   Rate(input: 1.0,  output: 5,   cacheRead: 0.10, cacheWrite: 1.25)),
        // OpenAI Codex / GPT-5 family
        ("gpt-5",   Rate(input: 1.25, output: 10,  cacheRead: 0.125, cacheWrite: 1.25)),
        ("codex",   Rate(input: 1.25, output: 10,  cacheRead: 0.125, cacheWrite: 1.25)),
        ("o4",      Rate(input: 1.10, output: 4.4, cacheRead: 0.275, cacheWrite: 1.10)),
        ("o3",      Rate(input: 2.0,  output: 8,   cacheRead: 0.5,   cacheWrite: 2.0)),
        // Google Gemini (Antigravity)
        ("gemini",  Rate(input: 2.5,  output: 15,  cacheRead: 0.25,  cacheWrite: 2.5)),
        // Moonshot Kimi
        ("kimi",    Rate(input: 0.60, output: 2.5, cacheRead: 0.15,  cacheWrite: 0.60)),
        // MiniMax (fallback; real cost usually available)
        ("minimax", Rate(input: 0.30, output: 1.2, cacheRead: 0.03,  cacheWrite: 0.30)),
    ]

    static func estimatedCost(for counts: TokenCounts, model: String) -> Double {
        let m = model.lowercased()
        guard let rate = table.first(where: { m.contains($0.match) })?.rate else { return 0 }
        return (Double(counts.input) * rate.input
                + Double(counts.output) * rate.output
                + Double(counts.cacheRead) * rate.cacheRead
                + Double(counts.cacheWrite) * rate.cacheWrite) / 1_000_000
    }
}
