import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct AssistantGalleryTests {
    @Test func listsWhatTheSystemsAppsLists() {
        #expect(AssistantGallery.isListed("/Applications/Steam.app", region: "HU"))
        #expect(AssistantGallery.isListed("/System/Applications/Utilities/Terminal.app", region: "HU"))
        #expect(AssistantGallery.isListed("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app", region: "HU"))
        #expect(!AssistantGallery.isListed("/System/Applications/Apps.app", region: "HU"))
        #expect(!AssistantGallery.isListed("/System/Library/CoreServices/Finder.app", region: "HU"))
        #expect(!AssistantGallery.isListed("/Applications/Xcode.app/Contents/Applications/Instruments.app", region: "HU"))
        #expect(!AssistantGallery.isListed("/Users/someone/Applications/Game.app", region: "HU"))
        #expect(!AssistantGallery.isListed("/System/Applications/News.app", region: "HU"))
        #expect(AssistantGallery.isListed("/System/Applications/News.app", region: "US"))
    }

    @Test func sectionsTheApps() {
        func hit(_ path: String, used: Date? = nil) -> AssistantHit {
            let url = URL(fileURLWithPath: path)
            return AssistantHit(kind: .app, url: url, name: url.deletingPathExtension().lastPathComponent, contentType: nil, lastUsed: used)
        }
        let apps = [hit("/Applications/Zed.app"), hit("/System/Applications/Mail.app", used: Date(timeIntervalSince1970: 2)),
                    hit("/System/Applications/Utilities/Terminal.app", used: Date(timeIntervalSince1970: 3))]
        let gallery = AssistantGallery(apps: apps, sort: .recent, columns: 7, region: "HU")
        #expect(gallery.recent.map(\.name) == ["Terminal", "Mail"])
        #expect(gallery.main.map(\.name) == ["Mail", "Zed"])
        #expect(gallery.other.map(\.name) == ["Terminal"])
        #expect(AssistantGallery(apps: apps, sort: .name, columns: 7, region: "HU").recent.isEmpty)
    }

    @Test func movesByRowsAcrossSections() {
        let counts = [7, 15, 3]
        #expect(AssistantGallery.index(from: 2, rows: 1, counts: counts, columns: 7) == 9)
        #expect(AssistantGallery.index(from: 9, rows: -1, counts: counts, columns: 7) == 2)
        // The main section's short last row (one app) to the next section, and back.
        #expect(AssistantGallery.index(from: 21, rows: 1, counts: counts, columns: 7) == 22)
        #expect(AssistantGallery.index(from: 24, rows: -1, counts: counts, columns: 7) == 21)
        #expect(AssistantGallery.index(from: 24, rows: 1, counts: counts, columns: 7) == 24)
    }
}
