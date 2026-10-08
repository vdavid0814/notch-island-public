import Observation
import SwiftUI

/// How a widget is drawn: `live` on the island, or `canvas` — Settings' stage — where it is a
/// picture: its glass buttons and sliders drawn as plain shapes (`GlassButtonPicture`,
/// `SliderPicture`), no clock or line ticking, nothing read from the system, nothing clickable.
nonisolated enum WidgetRenderMode: Sendable {
    case live, canvas
}

extension EnvironmentValues {
    @Entry var widgetRenderMode = WidgetRenderMode.live
    /// Drawn as a picture (the gallery, the stage): nothing is read from the system that could ask
    /// for a permission, and switches show as on.
    @Entry var isWidgetPreview = false
    /// A moment the widgets show in place of their ticking clock (the snapshots); nil is now.
    @Entry var widgetDate: Date?
    @Entry var widgetBoard: WidgetBoardShape?
    /// In Customize's editor: every part that can be moved reports where the layout puts it
    /// (`ElementFramesKey`), and Now Playing shows a track while none plays, so all its parts are
    /// there to move.
    @Entry var isElementEditing = false
    /// How far the part drawn here is moved from where its layout puts it (`movableElement`):
    /// what keeps itself inside its widget measures from its own place, so a move still moves it.
    @Entry var elementMove: CGSize = .zero
    /// False: the widget without its background, only its parts (`ElementInk` reads where they
    /// are drawn).
    @Entry var drawsWidgetSurface = true
    /// Where the editor reads one text part's ink: the others drawn unseen (taking their room), so
    /// a text reaching over another's box is not read as part of it.
    @Entry var inkText: ElementID?
    /// Where the editor reads one part's ink alone: every other movable part drawn unseen (taking
    /// its room), so a symbol grown over a neighbour's text is not read with that text.
    @Entry var inkPart: ElementID?
    /// In Customize's editor: the text shown as it would be set on more lines (`LabelFit.preview`) —
    /// its letters at the size such a text gets, the room left in stronger dots.
    @Entry var linePreview: ElementID?
    /// In Customize's editor, where parts overlap: which are on top, and what of the others is
    /// under them.
    @Entry var elementOverlaps = ElementOverlaps()
    /// The widget a part is drawn in: its size and its corners, in the coordinate space
    /// `WidgetShape.space` (from its top-leading corner). A part's own background that reaches the
    /// widget's edges takes its corners there (`WidgetLabel`).
    @Entry var widgetShape: WidgetShape?
    /// Which of a widget's layers is drawn here (`SharpZoom`).
    @Entry var widgetLayerPass = WidgetLayerPass.all
    /// The island's Quick Look thumbnails (the shelf page's), so the Shelf widget's files are not
    /// made again; nil where there is none (a widget makes its own).
    @Entry var shelfThumbnails: ThumbnailCache?
}

/// A widget drawn in two passes where Customize zooms it (`SharpZoom`): `underlay`, its
/// background and its buttons' Liquid Glass alone; `overlay`, everything else (as one sharp
/// picture). `all`: everything at once.
nonisolated enum WidgetLayerPass: Sendable {
    case all, underlay, overlay
}

/// A widget zoomed in Customize, as sharp as it is shown. Zoomed on its own, its texts and symbols
/// were drawn at the widget's own pixels and enlarged (blurred), so it is drawn as one picture at
/// the size it is shown at — but Liquid Glass draws nothing in such a picture: where the widget has
/// glass buttons, its background and the glass are drawn under the picture as they are, and the
/// picture holds the rest. `content` is the widget for a pass, already zoomed and framed.
struct SharpZoom<Content: View>: View {
    let widget: IslandWidget
    @ViewBuilder let content: (WidgetLayerPass) -> Content

    var body: some View {
        if Self.hasGlass(widget) {
            ZStack {
                content(.underlay)
                    .environment(\.widgetLayerPass, .underlay)
                content(.overlay)
                    .environment(\.widgetLayerPass, .overlay)
                    .drawingGroup()
            }
        } else {
            content(.all).drawingGroup()
        }
    }

    /// A button, a ruler or a grid of days drawn on Liquid Glass.
    static func hasGlass(_ widget: IslandWidget) -> Bool {
        (widget.kind.spec.buttons + widget.kind.spec.rulers + widget.kind.spec.dayGrids).contains { widget.isGlass($0) }
    }
}

struct WidgetShape: Equatable {
    static let space = "widgetSurface"

    var size: CGSize
    var corners: RectangleCornerRadii
}

/// Where parts overlap, for the editor to make plain which is over which: a part on top of another
/// is lifted (a shadow), and what of a part is under another is faded.
struct ElementOverlaps: Equatable {
    /// The parts drawn over another.
    var lifted: Set<ElementID> = []
    /// For each part under another, the rectangles covered, in its own layout box's points.
    var covered: [ElementID: [CGRect]] = [:]
}

/// Where the widgets are drawn on the panel's board: its grid, and its bottom corners' radius
/// (`ConcentricGeometry.boardCornerRadius`), so a widget in a bottom corner is concentric with the
/// panel. Without it (a picture in Settings) every corner is the standard one.
nonisolated struct WidgetBoardShape: Equatable, Sendable {
    var grid: BoardGrid
    var cornerRadius: CGFloat
}

nonisolated extension RectangleCornerRadii {
    static func uniform(_ radius: CGFloat) -> RectangleCornerRadii {
        RectangleCornerRadii(topLeading: radius, bottomLeading: radius, bottomTrailing: radius, topTrailing: radius)
    }

    /// The one radius of all four corners, if they share one.
    var uniformRadius: CGFloat? {
        topLeading == bottomLeading && topLeading == bottomTrailing && topLeading == topTrailing ? topLeading : nil
    }
}

extension View {
    /// On Settings' stage: a picture — nothing read from the system, and nothing in it answers a
    /// click, so no click there sets the volume or sends a command. On the island, the view itself.
    @ViewBuilder func canvasPicture(_ isCanvas: Bool) -> some View {
        if isCanvas {
            environment(\.isWidgetPreview, true).allowsHitTesting(false)
        } else {
            self
        }
    }
}

/// What a picture of a widget (Settings' gallery and stage) reads of the levels: live while Settings
/// is on screen; while it is closed, the reading it last showed. Settings is kept (`SettingsWindow`),
/// and its pictures followed every volume change unseen: their sliders were redrawn each time (a
/// volume change cost ~70 ms more of main thread, measured).
@MainActor enum PictureReadings {
    private static var levels: [LevelKind: LevelReading] = [:]

    static func level(_ kind: LevelKind, model: AppModel) -> LevelReading {
        if SettingsPresence.shared.isShown {
            let reading = model.levels.reading(kind)
            levels[kind] = reading
            return reading
        }
        return levels[kind] ?? model.levels.reading(kind)
    }
}

/// Whether Settings is on screen (`SettingsWindow`), for what only Settings shows.
@Observable final class SettingsPresence {
    static let shared = SettingsPresence()
    nonisolated static let didChange = Notification.Name("NotchIsland.settingsPresenceChanged")
    var isShown = false {
        didSet { if isShown != oldValue { NotificationCenter.default.post(name: Self.didChange, object: nil) } }
    }
}
