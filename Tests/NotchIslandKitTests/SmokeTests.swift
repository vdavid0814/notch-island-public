import Testing
@testable import NotchIslandKit

@Test func presentationContentKeyIgnoresData() {
    #expect(IslandPresentation.banner(.power(.connected)).contentKey == IslandPresentation.banner(.power(.low(threshold: 20))).contentKey)
    #expect(IslandPresentation.expanded(.home).isExpanded)
}
