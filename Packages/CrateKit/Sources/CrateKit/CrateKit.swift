/// CrateKit — pure-domain core for Game Crate.
///
/// Issue #2 landed the domain layer: shelf/people models with unknown-safe
/// fit fields, the append-only play ledger (corrections are compensating
/// events), the explainable fit engine (ranked shortlist + named exclusion
/// reasons + distinct `unspecified` count), and the count-based derivations
/// (plays-per-game, DST-safe days-since-last, per-player rating/category
/// counts, shelf coverage holes). The versioned backup codec ships with
/// issue #6; the GRDB store is issue #3 (`Packages/CrateStore`).
public enum CrateKit {
    /// Namespace marker for the domain layer.
    public static let domain = "CrateKit"

    /// Current build/CI milestone marker consumed by the app's debug surface.
    public static let milestone = "M1-domain"
}
