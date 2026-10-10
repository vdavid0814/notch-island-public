import Foundation

/// Everything the app knows about one kind of widget, as data: what the gallery shows, the sizes it
/// takes, the elements inside it and the looks it offers.
nonisolated struct WidgetKindSpec: Sendable {
    var title: String
    /// One line for the gallery.
    var summary: String
    var symbol: String
    /// The gallery icon's gradient, top to bottom (`WidgetIcon`).
    var iconColors: [IslandTheme.RGB]
    var category: WidgetCategory
    /// In reference cells (the 12 × 3 board); `BoardGrid` converts them.
    var minimumSize: GridSize
    var defaultSize: GridSize
    var maximumSize: GridSize
    /// In the order they are drawn.
    var elements: [ElementSpec]
    /// The parts Customize can move (`IslandWidget.offsets`), each by itself: a switch may cover
    /// two of them (previous and next).
    var movable: [ElementID] = []
    /// The movable parts that are text: Customize's inspector sets their type, colour, lines and
    /// background (`TextStyle`), and resizing gives them a larger box, not larger letters.
    var texts: [ElementID] = []
    /// The movable parts that are buttons: Customize sets what each is made of, its shape, its fill
    /// and its symbol (`ButtonLook`).
    var buttons: [ElementID] = []
    /// The movable parts that are playback lines: Customize sets their colours, ends and knob
    /// (`ProgressLook`).
    var progressBars: [ElementID] = []
    /// Buttons with a ring round them (the battery's): the ring is drawn as a line is, by a
    /// `ProgressLook` of its own, set from the button's inspector.
    var rings: [ElementID] = []
    /// The texts whose box of their own hangs from their top-trailing corner, not their top-leading
    /// one (`WidgetLabel.hangsFromTrailing`): at a row's end (the timer's time), as the box grows it
    /// grows to the left. Customize's editor sizes them so.
    var trailingTexts: [ElementID] = []
    /// Texts inside a part (the times under a playback line): styled like a text part
    /// (`TextStyle`), from the part's inspector, never moved by themselves.
    var innerTexts: [ElementID] = []
    /// The movable parts that are pictures (Now Playing's artwork): Customize sets whether resizing
    /// keeps their shape, and whether they grow to the widget's edges or over all of it (`ImageLook`).
    var images: [ElementID] = []
    /// The movable parts that are charts: Customize sets their bars' corners, colours and the
    /// percentages beside them (`ChartLook`).
    var charts: [ElementID] = []
    /// The movable parts that are rulers (the timer's): Customize sets their colour, their ticks'
    /// ends and what is behind them (`RulerLook`).
    var rulers: [ElementID] = []
    /// The movable parts that are grids of days (the calendar's): Customize sets a background
    /// behind each day and one behind the grid (`DayGridLook`).
    var dayGrids: [ElementID] = []
    /// What each widget of the kind can be set to show, in Customize's panel (`WidgetConfig`).
    var settings: [WidgetSetting] = []
    /// Whether it works on this Mac: the gallery hides it when not.
    var isAvailable: @Sendable () -> Bool = { true }

    func element(_ id: ElementID) -> ElementSpec? { elements.first { $0.id == id } }
}

/// One element of a kind: its row in the editor, and whether it can be switched off.
nonisolated struct ElementSpec: Sendable, Hashable {
    var id: ElementID
    var title: String
    var symbol: String
    /// Switched on in a new widget.
    var defaultVisible: Bool
    /// Always drawn (the slider, the button): it has no switch.
    var isRequired: Bool

    init(_ id: ElementID, _ title: String, symbol: String, defaultVisible: Bool = true, isRequired: Bool = false) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.defaultVisible = defaultVisible
        self.isRequired = isRequired
    }
}

nonisolated extension IslandTheme.RGB {
    /// Short, for the specs' icon colours.
    static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> IslandTheme.RGB {
        IslandTheme.RGB(red: red, green: green, blue: blue)
    }
}
