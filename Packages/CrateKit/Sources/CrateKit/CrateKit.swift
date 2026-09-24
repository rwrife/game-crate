/// CrateKit — pure-domain core for Game Crate.
///
/// Issue #1 ships only the skeleton namespace so CI has a real, testable
/// target. Issue #2 (domain) lands the shelf/people/play-ledger models, the
/// explainable fit engine (ranked shortlist with named exclusion reasons and
/// an `unspecified` count for unknown fields), the count-based derivations
/// (plays-per-game, DST-safe days-since-last, per-player rating/category
/// counts, shelf coverage holes), and the versioned backup codec here. The
/// GRDB store is issue #3 (`Packages/CrateStore`).
public enum CrateKit {
    /// Namespace marker for the domain layer.
    public static let domain = "CrateKit"

    /// Current build/CI milestone marker consumed by the app's debug surface.
    public static let milestone = "M0-skeleton"
}
