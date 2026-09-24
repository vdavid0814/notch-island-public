import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct AirPodsTests {
    static let profile = Data("""
    {"SPBluetoothDataType":[{"device_connected":[{"Anna’s AirPods Pro":{"device_batteryLevelCase":"86%","device_batteryLevelLeft":"80%","device_batteryLevelRight":"79%","device_productID":"0x2027"}}],
      "device_not_connected":[{"SRS-XB30":{"device_minorType":"Speaker"}},{"Studio":{"device_batteryLevelMain":"55%"}}]}]}
    """.utf8)

    @Test func readsEachBatteryOfConnectedAirPods() throws {
        let info = try #require(AirPodsMonitor.parse(Self.profile, name: "Anna’s AirPods Pro"))
        #expect(info.model == .airPodsPro)
        #expect(info.left == 80 && info.right == 79 && info.chargingCase == 86 && info.single == nil)
        #expect(info.leftSymbol == "airpodpro.left")
    }

    @Test func oneBatteryHeadphonesAndUnknownDevices() {
        #expect(AirPodsMonitor.parse(Self.profile, name: "Studio")?.single == 55)
        #expect(AirPodsMonitor.parse(Self.profile, name: "SRS-XB30")?.hasBattery == false)
        #expect(AirPodsMonitor.parse(Self.profile, name: "Nothing") == nil)
        #expect(AirPodsMonitor.parse(Data("junk".utf8), name: "Studio") == nil)
    }

    @Test func modelFromNameAndProduct() {
        #expect(AirPodsInfo.Model(name: "AirPods Max", productID: nil) == .airPodsMax)
        #expect(AirPodsInfo.Model(name: "Kati AirPodsa", productID: "0x2013") == .airPods3)
        #expect(AirPodsInfo.Model(name: "Powerbeats Pro", productID: nil) == .beats)
        #expect(AirPodsInfo.Model(name: "Beats Studio", productID: nil) == .beats)
    }

    @Test func demoRoute() {
        #expect(AppCommand.parse(URL(string: "notchisland://demo/airpods")!) == .demo(.airPods))
    }
}

@Suite struct TopEdgeOverlayTests {
    @Test func systemCardShapesCountButTheMenuBarDoesNot() {
        #expect(TopEdgeOverlays.isOverlay(CGRect(x: 530, y: 40, width: 230, height: 52)))   // AirPods card
        #expect(!TopEdgeOverlays.isOverlay(CGRect(x: 0, y: 0, width: 1280, height: 29)))    // menu bar
        #expect(!TopEdgeOverlays.isOverlay(CGRect(x: 0, y: 38, width: 1280, height: 800)))   // a window
    }

    @Test func noticeDurationsAreClampedAndStored() {
        let defaults = UserDefaults(suiteName: "NoticeDurations.\(UUID().uuidString)")!
        defaults.set(99.0, forKey: Preferences.Key.levelDuration)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.levelDuration == Preferences.noticeDurationRange.upperBound)
        #expect(preferences.airPodsDuration == 5 && preferences.powerDuration == 3 && preferences.airPodsSystemCard == .cover)
    }
}
