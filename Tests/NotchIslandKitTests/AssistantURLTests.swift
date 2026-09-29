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

@Suite struct AssistantListedAppTests {
    @Test func appsAnywhereAreListedButNotTheIndexsOthers() {
        #expect(AssistantSearch.isListedApp("/Users/g/Downloads/Xcode.app"))
        #expect(AssistantSearch.isListedApp("/Users/g/Documents/curseforge/minecraft/Install/Minecraft.app"))
        #expect(AssistantSearch.isListedApp("/Applications/Safari.app"))
        #expect(AssistantSearch.isListedApp("/System/Applications/Utilities/Terminal.app"))
        #expect(AssistantSearch.isListedApp("/System/Library/CoreServices/Finder.app"))
        #expect(AssistantSearch.isListedApp("/System/Library/CoreServices/Applications/Archive Utility.app"))
        #expect(AssistantSearch.isListedApp("/System/Volumes/Data/Users/g/Desktop/Tool.app"))
        #expect(!AssistantSearch.isListedApp("/System/Library/CoreServices/Dock.app"))
        #expect(!AssistantSearch.isListedApp("/Users/g/Library/Developer/Xcode/DerivedData/A-x/Build/Products/Debug/A.app"))
        #expect(!AssistantSearch.isListedApp("/Users/g/Library/Application Support/Steam/Steam Helper.app"))
        #expect(AssistantSearch.isListedApp("/Applications/Xcode.app/Contents/Applications/Simulator.app"))
        #expect(!AssistantSearch.isListedApp("/Applications/Xcode.app/Contents/MacOS/Helper.app"))
        #expect(!AssistantSearch.isListedApp("/Users/g/Projects/App/build/Release/App.app"))
        #expect(!AssistantSearch.isListedApp("/Volumes/NotchIsland/NotchIsland.app"))
        #expect(!AssistantSearch.isListedApp("/Users/g/.Trash/Old.app"))
    }

    @Test func finderIsAmongTheApps() {
        #expect(AssistantSearch.diskApps().contains { $0.url.path == AssistantSearch.finder && $0.name == "Finder" })
    }
}

@Suite struct AssistantEmbeddedAppTests {
    @Test func toolsInsideAnAppAreListed() {
        #expect(AssistantSearch.isListedApp("/Applications/Xcode-beta.app/Contents/Applications/DeviceHub.app"))
        #expect(AssistantSearch.isListedApp("/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"))
        #expect(!AssistantSearch.isListedApp("/Applications/Xcode.app/Contents/SharedFrameworks/X.framework/Helper.app"))
        #expect(!AssistantSearch.isListedApp("/Users/g/Library/Foo.app/Contents/Applications/Bar.app"))
        #expect(AssistantSearch.embeddingApp("/Applications/Xcode.app/Contents/Applications/DeviceHub.app") == "/Applications/Xcode.app")
        #expect(AssistantSearch.embeddingApp("/Applications/Xcode.app/Contents/Applications/A.app/Contents/Applications/B.app")
                == "/Applications/Xcode.app/Contents/Applications/A.app")
    }

    @Test func camelCaseNamesAreWords() {
        #expect(AssistantMatch.matches("DeviceHub", "device hub"))
        #expect(AssistantMatch.matches("DeviceHub", "hub"))
        #expect(AssistantMatch.matches("FileMerge", "merge", .wordStart))
        #expect(!AssistantMatch.matches("Safari", "ari", .wordStart))
        #expect(AssistantMatch.matches("Visual Studio Code", "stu", .wordStart))
    }
}
