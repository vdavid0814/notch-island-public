import Foundation
import Testing
@testable import NotchIslandKit

/// Spotlight's quick keys, `kind:` filters and quick actions.
struct AssistantQuickTests {
    @Test func quickKeysAreTheWordsFirstLetters() {
        #expect(AssistantMatch.matches("Visual Studio Code", "vsc"))
        #expect(AssistantMatch.matches("System Settings", "ss"))
        #expect(AssistantMatch.matches("DeviceHub", "dh"))
        // All of the words, not a part of them; a space between letters is no quick key.
        #expect(!AssistantMatch.matches("Visual Studio Code", "vs"))
        #expect(!AssistantMatch.matches("Safari", "s f"))
        #expect(AssistantMatch.initials(of: "Send Email") == ["se"])
    }

    @Test func kindFilterKeepsTheRestOfTheQuery() {
        let (rest, types) = AssistantSearch.kindFilter("invoice kind:pdf 2026")
        #expect(rest == "invoice 2026")
        #expect(types == ["com.adobe.pdf"])
        #expect(AssistantSearch.kindFilter("kind:kép").types == ["public.image"])
        // An unknown kind stays a word of the query.
        #expect(AssistantSearch.kindFilter("kind:banana").rest == "kind:banana")
    }

    @Test func quickActionsTakeWhatFollows() {
        let email = AssistantCompose.parse("se lunch at one")
        #expect(email?.kind == .email && email?.text == "lunch at one" && email?.isQuickKey == true)
        #expect(AssistantCompose.parse("email anna@example.com")?.isAddress == true)
        #expect(AssistantCompose.parse("sm on my way")?.kind == .message)
        #expect(AssistantCompose.parse("maps")?.kind == nil)
        #expect(AssistantCompose.parse("maps coffee")?.url?.absoluteString == "maps:?q=coffee")
        #expect(AssistantCompose.parse("safari") == nil)
    }
}
