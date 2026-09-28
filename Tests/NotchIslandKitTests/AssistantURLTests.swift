import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct AssistantURLTests {
    @Test func webAddressesOpen() {
        #expect(AssistantURL.url(from: "github.com")?.absoluteString == "https://github.com")
        #expect(AssistantURL.url(from: "github.com/apple/swift")?.absoluteString == "https://github.com/apple/swift")
        #expect(AssistantURL.url(from: "index.hu")?.absoluteString == "https://index.hu")
        #expect(AssistantURL.url(from: "https://example.org/a?b=c")?.absoluteString == "https://example.org/a?b=c")
        #expect(AssistantURL.url(from: "localhost:3000")?.absoluteString == "http://localhost:3000")
        #expect(AssistantURL.url(from: "192.168.1.1/admin")?.absoluteString == "http://192.168.1.1/admin")
        #expect(AssistantURL.url(from: "  apple.com  ")?.absoluteString == "https://apple.com")
    }

    @Test func fileNamesSumsAndWordsDoNot() {
        for text in ["notes.md", "report.pdf", "main.swift", "index.html", "setup.py", "1.2.3.4", "3.14", "e.g.",
                     "hello world.com", "stb.", "v1.2", "a@b.com", "12 + 30", "notch", ""] {
            #expect(AssistantURL.url(from: text) == nil, "\(text)")
        }
    }

    @Test func displayDropsTheScheme() throws {
        #expect(AssistantURL.display(try #require(URL(string: "https://github.com/"))) == "github.com")
        #expect(AssistantURL.display(try #require(URL(string: "http://localhost:3000/x"))) == "localhost:3000/x")
    }

    @Test func buriedFoldersAreLeftOut() {
        #expect(AssistantSearch.isBuried("/Users/a/Documents/app/node_modules/react"))
        #expect(AssistantSearch.isBuried("/Users/a/Documents/.git/objects"))
        #expect(AssistantSearch.isBuried("/Users/a/Downloads/Foo.app/Contents"))
        #expect(!AssistantSearch.isBuried("/Users/a/Documents/Projects"))
        // The folder named like one is still found; only what is inside it is not.
        #expect(!AssistantSearch.isBuried("/Users/a/Documents/node_modules"))
    }
}
