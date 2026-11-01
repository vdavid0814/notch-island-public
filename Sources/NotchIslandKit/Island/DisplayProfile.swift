import Foundation

/// The MacBook screens, recognised by their panel's physical size, and how much larger the open
/// island is drawn on each so it looks the same on all of them: the notched ones, and the Apple
/// silicon MacBooks without a notch — the 13.3-inch MacBook Air M1 (2020) and MacBook Pro M1/M2
/// (2020, 2022), and the MacBook Neo (2026). On those the island hangs from a notch it draws itself
/// (`NotchMetrics.synthesizedWidth`).
///
/// The island is designed on a 13.6-inch MacBook Air at 1280 × 832 pt (the reference Mac): 4.41
/// points per millimetre. A 14-inch MacBook Pro at its default 1512 × 982 pt packs 5.0 points into a
/// millimetre, so the same 600-pt panel is physically 12 % smaller and reads as cramped next to its
/// larger notch. Each profile scales the open island by its points-per-millimetre over the
/// reference's, so it keeps the same physical size (and the same size beside the notch, which is
/// physically alike on every model) at whatever resolution the user picked. Any other screen — an
/// external display, an unknown panel — is left exactly as before (factor 1).
nonisolated enum DisplayProfile: String, Sendable, CaseIterable {
    case air13
    case air15
    case pro14
    case pro16
    /// MacBook Air M1 and 13-inch MacBook Pro M1/M2: 2560 × 1600 at 227 ppi, no notch.
    case flat13
    /// MacBook Neo (A18 Pro): 2408 × 1506 at 219 ppi, no notch.
    case neo13

    var name: String {
        switch self {
        case .air13: "MacBook Air 13.6\""
        case .air15: "MacBook Air 15.3\""
        case .pro14: "MacBook Pro 14.2\""
        case .pro16: "MacBook Pro 16.2\""
        case .flat13: "MacBook Air / Pro 13.3\""
        case .neo13: "MacBook Neo 13\""
        }
    }

    /// The panel's active area in millimetres (pixels over pixel density; what `CGDisplayScreenSize`
    /// reports, measured 290.3 × 188.7 on the 13.6-inch Air).
    var panelSize: CGSize {
        switch self {
        case .air13: CGSize(width: 290.3, height: 188.7)  // 2560 × 1664 at 224 ppi
        case .air15: CGSize(width: 326.6, height: 211.4)  // 2880 × 1864 at 224 ppi
        case .pro14: CGSize(width: 302.4, height: 196.4)  // 3024 × 1964 at 254 ppi
        case .pro16: CGSize(width: 345.6, height: 223.4)  // 3456 × 2234 at 254 ppi
        case .flat13: CGSize(width: 286.4, height: 179.0)  // 2560 × 1600 at 227 ppi
        case .neo13: CGSize(width: 279.3, height: 174.7)   // 2408 × 1506 at 219 ppi
        }
    }

    /// The screen the island was designed on.
    static let reference = DisplayProfile.air13
    /// Its points per millimetre: 1280 pt across the 13.6-inch panel.
    static let referenceDensity: CGFloat = 1280 / 290.3
    /// A panel within this many millimetres of a profile's, both ways, is that profile (the closest
    /// pair, the 13.3-inch Air and the Neo, are 7 mm apart across; the 13.3- and 13.6-inch Airs
    /// 10 mm in height).
    static let tolerance: CGFloat = 5
    /// However far the user's resolution goes, the island stays within these.
    static let factorRange: ClosedRange<CGFloat> = 0.8...1.5
    static let overrideKey = "ni.displayFactor"

    /// The profile of a built-in panel this size, nil for anything else (the closest when two
    /// are within the tolerance).
    static func matching(physicalSize: CGSize, isBuiltin: Bool) -> DisplayProfile? {
        guard isBuiltin, physicalSize.width > 0 else { return nil }
        func distance(_ profile: DisplayProfile) -> CGFloat {
            max(abs(profile.panelSize.width - physicalSize.width), abs(profile.panelSize.height - physicalSize.height))
        }
        return allCases.filter { distance($0) <= tolerance }.min { distance($0) < distance($1) }
    }

    /// How much larger the open island is drawn on this panel at `pointsWide` points across.
    func factor(pointsWide: CGFloat) -> CGFloat {
        let density = pointsWide / panelSize.width
        let factor = density / Self.referenceDensity
        // Within a percent of the reference is the reference: no half-point drift on it.
        if abs(factor - 1) < 0.01 { return 1 }
        return min(max(factor, Self.factorRange.lowerBound), Self.factorRange.upperBound)
    }

    /// The island's screen is one of the profiles (or a factor is forced for trying them).
    static func isKnown(_ metrics: NotchMetrics?) -> Bool {
        if UserDefaults.standard.double(forKey: overrideKey) > 0 { return true }
        guard let metrics else { return false }
        return matching(physicalSize: metrics.physicalSize, isBuiltin: metrics.isBuiltin) != nil
    }

    /// The factor for the island's screen: 1 unless it is a known MacBook panel.
    static func factor(for metrics: NotchMetrics?) -> CGFloat {
        // For trying a profile on another Mac: `defaults write com.davidvarga.notchisland
        // ni.displayFactor 1.134` (delete the key to go back).
        let forced = UserDefaults.standard.double(forKey: overrideKey)
        if forced > 0 { return min(max(forced, factorRange.lowerBound), factorRange.upperBound) }
        guard let metrics, let profile = matching(physicalSize: metrics.physicalSize, isBuiltin: metrics.isBuiltin) else { return 1 }
        return profile.factor(pointsWide: metrics.screenFrame.width)
    }
}
