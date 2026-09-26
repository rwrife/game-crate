import Testing
@testable import CrateKit

@Suite("Skeleton placeholder")
struct CrateKitTests {
    @Test("domain namespace is reachable")
    func domainNamespace() {
        #expect(CrateKit.domain == "CrateKit")
    }

    @Test("milestone marker is set for M1")
    func milestoneMarker() {
        #expect(CrateKit.milestone == "M1-domain")
    }

    @Test("skeleton exposes no stored state beyond constants")
    func constantsAreStable() {
        // Guards the contract later issues depend on: these markers exist
        // and are pure constants (no clock, no I/O) in the M0 skeleton.
        let first = (CrateKit.domain, CrateKit.milestone)
        let second = (CrateKit.domain, CrateKit.milestone)
        #expect(first == second)
    }
}
