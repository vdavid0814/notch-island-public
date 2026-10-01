import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

/// A QA sweep over every offered widget kind and every option its Customize editor offers, at the
/// extremes: what changes nothing on screen, what spills out of its frame or the widget, what
/// overlaps what it did not, what vanishes, what a drag on the canvas does at its limits, and
/// whether the editor's commands (reset, undo, flip, decorations…) come back where they started.
///
/// It records, it does not judge: findings go to `$TMPDIR/WidgetQA/<kind>.json` (with before and
/// after pictures of what it flags), to be read and triaged by hand. Minutes of drawing: only with
/// `NI_QA` set, in a process of its own (`NI_QA=1 Scripts/test.sh --filter WidgetQASweepTests`).
@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["NI_QA"] != nil, "QA sweep: NI_QA=1"))
struct WidgetQASweepTests {
    nonisolated struct Finding: Codable, Sendable {
        var kind: String
        var size: String
        var mode: String
        var element: String
        var option: String
        var issue: String
        var detail: String
        var pictures: [String] = []
    }

    /// Every offered kind, or those named in `NI_QA_KIND` (comma separated).
    nonisolated static let kinds: [IslandWidgetKind] = {
        let offered = IslandWidgetKind.allCases.filter(\.isOffered)
        guard let names = ProcessInfo.processInfo.environment["NI_QA_KIND"] else { return offered }
        let picked = Set(names.split(separator: ",").map(String.init))
        return offered.filter { picked.contains($0.rawValue) }
    }()

    static let output = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetQA")

    // MARK: Drawing

    /// Room around the widget in the picture: whatever is drawn there spilled out of it.
    static let margin: CGFloat = 24
    static let scale: CGFloat = 2

    struct Picture {
        var pixels: [UInt8]
        var width: Int
        var height: Int
        var frames: [ElementID: CGRect]
        var drawn: [ElementID: WidgetFrameProbe.Drawn]
        var inks: [ElementID: TextLetters]
        var unlocked: LayoutConversion.Unlocked
        var size: CGSize
        var image: CGImage?

        /// Lit pixels outside the widget's own rectangle.
        var spilled: Int {
            let inset = Int(WidgetQASweepTests.margin * WidgetQASweepTests.scale)
            let inner = (x: inset..<(width - inset), y: inset..<(height - inset))
            var count = 0
            for y in 0..<height {
                for x in 0..<width where !(inner.x.contains(x) && inner.y.contains(y)) {
                    let i = (y * width + x) * 4
                    if Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]) > 60 { count += 1 }
                }
            }
            return count
        }
    }

    static let model: AppModel = {
        let model = AppModel()
        model.media.injectDemo(NowPlayingItem(title: "An Unusually Long Song Title That Keeps Going On And On",
                                              artist: "A Remarkably Long Artist Name Featuring Several Others",
                                              album: "A", duration: 272, artworkData: nil, bundleIdentifier: "com.apple.Music"),
                               playing: true)
        return model
    }()

    static func widgetSize(_ grid: GridSize) -> CGSize {
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard)
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(layout), grid: .standard)
        return geometry.frame(for: GridRect(column: 0, row: 0, width: grid.width, height: grid.height)).size
    }

    static func draw(_ widget: IslandWidget) -> Picture {
        draw(widget, size: widgetSize(GridSize(width: widget.frame.width, height: widget.frame.height)), model: model)
    }

    static func draw(_ widget: IslandWidget, size: CGSize, model: AppModel) -> Picture {
        let probe = WidgetFrameProbe()
        let view = IslandWidgetView(widget: widget, size: size, thumbnails: ThumbnailCache())
            .frame(width: size.width, height: size.height)
            .coordinateSpace(.named(WidgetFrameProbe.space))
            .padding(margin)
            .background(.black)
            .environment(model)
            .environment(\.widgetRenderMode, .canvas)
            .environment(\.widgetFrameProbe, probe)
            .environment(\.widgetReadsLive, true)
            .environment(\.widgetDate, WidgetSnapshotTests.date)
            .environment(\.locale, Locale(identifier: "en_US@hours=h23"))
            .environment(\.timeZone, TimeZone(identifier: "Europe/Budapest")!)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = renderer.cgImage
        var pixels: [UInt8] = []
        var (width, height) = (0, 0)
        if let image {
            (width, height) = (image.width, image.height)
            pixels = [UInt8](repeating: 0, count: width * height * 4)
            pixels.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        return withExtendedLifetime(renderer) {
            Picture(pixels: pixels, width: width, height: height, frames: probe.frames, drawn: probe.drawn, inks: probe.inks,
                    unlocked: probe.unlock(size: size, padding: WidgetMetrics.padding(for: widget), scale: model.layout.scale.factor),
                    size: size, image: image)
        }
    }

    /// Bytes that differ by more than a shade.
    static func difference(_ a: Picture, _ b: Picture) -> Int {
        guard a.pixels.count == b.pixels.count else { return Int.max }
        var count = 0
        for i in 0..<a.pixels.count where abs(Int(a.pixels[i]) - Int(b.pixels[i])) > 2 { count += 1 }
        return count
    }

    // MARK: Recording

    final class Recorder {
        let kind: IslandWidgetKind
        var findings: [Finding] = []
        private var pictures = 0

        init(_ kind: IslandWidgetKind) { self.kind = kind }

        func add(_ size: GridSize, _ mode: String, _ element: String, _ option: String, _ issue: String, _ detail: String = "",
                 before: Picture? = nil, after: Picture? = nil) {
            var finding = Finding(kind: kind.rawValue, size: "\(size.width)x\(size.height)", mode: mode, element: element,
                                  option: option, issue: issue, detail: detail)
            // Pictures for the first findings of a kind only: enough to see, not gigabytes.
            if pictures < 60 {
                for (label, picture) in [("before", before), ("after", after)] {
                    guard let image = picture?.image else { continue }
                    let name = "\(kind.rawValue)-\(pictures)-\(label).png"
                    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                    try? data?.write(to: WidgetQASweepTests.output.appendingPathComponent(name))
                    finding.pictures.append(name)
                }
                pictures += 1
            }
            findings.append(finding)
        }

        func write() {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = WidgetQASweepTests.output.appendingPathComponent("\(kind.rawValue).json")
            try? encoder.encode(findings).write(to: url)
        }
    }

    // MARK: Variants

    struct Variant {
        var element: String
        var option: String
        /// Expected to change the picture (an option the editor shows).
        var visible = true
        /// What it is compared with, when not the widget as it is (an option that needs another set first).
        var base: ((inout IslandWidget) -> Void)?
        var apply: (inout IslandWidget) -> Void
    }

    static let magenta = StyleColor.rgb(IslandTheme.RGB(red: 1, green: 0, blue: 1), alpha: 1)
    static let cyan = StyleColor.rgb(IslandTheme.RGB(red: 0, green: 1, blue: 1), alpha: 1)

    /// Every option the editor offers for this widget in this state, each at its extremes.
    static func variants(_ widget: IslandWidget, custom: Bool) -> [Variant] {
        let kind = widget.kind
        var all: [Variant] = []
        func element(_ id: ElementID, _ name: String, base: ((inout ElementStyle) -> Void)? = nil,
                     _ edit: @escaping (inout ElementStyle) -> Void) -> Variant {
            Variant(element: id.rawValue, option: name,
                    base: base.map { base in { widget in base(&widget.style.elements[id, default: ElementStyle()]) } }) { widget in
                base?(&widget.style.elements[id, default: ElementStyle()])
                edit(&widget.style.elements[id, default: ElementStyle()])
            }
        }
        for spec in kind.spec.elements {
            let id = spec.id
            if !spec.isRequired, kind.options.contains(id) {
                let shown = widget.shows(id)
                all.append(Variant(element: id.rawValue, option: shown ? "Shown=off" : "Shown=on") { widget in
                    if shown { widget.options.remove(id) } else { widget.options.insert(id) }
                    LayoutEdit.setShown(id, !shown, role: spec.role, parts: spec.parts, in: &widget.style.layout.arrangement)
                })
                // The outline's eye: the options alone.
                all.append(Variant(element: id.rawValue, option: shown ? "Eye=off" : "Eye=on") { widget in
                    if shown { widget.options.remove(id) } else { widget.options.insert(id) }
                })
            }
            guard widget.shows(id) else { continue }
            switch spec.role {
            case .text:
                all += [
                    element(id, "Text.points=6") { $0.text.points = 6 },
                    element(id, "Text.points=96") { $0.text.points = 96 },
                    element(id, "Font.design=serif") { $0.text.design = .serif },
                    element(id, "Font.design=monospaced") { $0.text.design = .monospaced },
                    element(id, "Font.design=rounded") { $0.text.design = .rounded },
                    element(id, "Font.weight=ultraLight") { $0.text.weight = .ultraLight },
                    element(id, "Font.weight=black") { $0.text.weight = .black },
                    element(id, "Font.width=compressed") { $0.text.width = .compressed },
                    element(id, "Font.width=expanded") { $0.text.width = .expanded },
                    element(id, "Font.italic=on") { $0.text.italic = true },
                    element(id, "Font.italic=off") { $0.text.italic = false },
                    element(id, "Font.digits=monospaced") { $0.text.monospacedDigits = true },
                    element(id, "Font.digits=proportional") { $0.text.monospacedDigits = false },
                    element(id, "Text.colour") { $0.colors[.primary] = magenta },
                    element(id, "Text.opacity=0.1") { $0.text.opacity = 0.1 },
                    element(id, "Text.letters=-2") { $0.text.tracking = -2 },
                    element(id, "Text.letters=10") { $0.text.tracking = 10 },
                    element(id, "Text.case=uppercase") { $0.text.textCase = .uppercase },
                    element(id, "Text.case=lowercase") { $0.text.textCase = .lowercase },
                    element(id, "Text.alignment=leading") { $0.text.alignment = .leading },
                    element(id, "Text.alignment=center") { $0.text.alignment = .center },
                    element(id, "Text.alignment=trailing") { $0.text.alignment = .trailing },
                    element(id, "Text.lines=1") { $0.text.lineLimit = 1 },
                    element(id, "Text.lines=2") { $0.text.lineLimit = 2 },
                    element(id, "Text.lines=3") { $0.text.lineLimit = 3 },
                    element(id, "Text.tooLong=head") { $0.text.truncation = .head },
                    element(id, "Text.tooLong=middle") { $0.text.truncation = .middle },
                    element(id, "Text.tooLong=tail") { $0.text.truncation = .tail },
                    element(id, "Text.tooLong=shrink") { $0.text.truncation = .shrink },
                ]
                if spec.acceptsLabel {
                    all.append(element(id, "Text.wording") { $0.text.labelOverride = "QA Wording" })
                }
                if !custom {
                    all.append(Variant(element: id.rawValue, option: "Size=S") { $0.sizes[id] = .small })
                    all.append(Variant(element: id.rawValue, option: "Size=L") { $0.sizes[id] = .large })
                }
            case .symbol:
                all += [
                    element(id, "Symbol.points=6") { $0.symbol.points = 6 },
                    element(id, "Symbol.points=96") { $0.symbol.points = 96 },
                    element(id, "Symbol.weight=ultraLight") { $0.symbol.weight = .ultraLight },
                    element(id, "Symbol.weight=black") { $0.symbol.weight = .black },
                    element(id, "Symbol.rendering=hierarchical") { $0.symbol.rendering = .hierarchical },
                    element(id, "Symbol.rendering=palette") { $0.symbol.rendering = .palette },
                    element(id, "Symbol.rendering=multicolor") { $0.symbol.rendering = .multicolor },
                    element(id, "Symbol.filled=on") { $0.symbol.filled = true },
                    element(id, "Symbol.filled=off") { $0.symbol.filled = false },
                    element(id, "Symbol.backing=circle") { $0.symbol.backing = .circle },
                    element(id, "Symbol.backing=roundedSquare") { $0.symbol.backing = .roundedSquare },
                    element(id, "Symbol.backing=capsule") { $0.symbol.backing = .capsule },
                ]
                if !custom {
                    all.append(Variant(element: id.rawValue, option: "Size=S") { $0.sizes[id] = .small })
                    all.append(Variant(element: id.rawValue, option: "Size=L") { $0.sizes[id] = .large })
                }
            case .image:
                all += [
                    element(id, "Picture.corners=circle") { $0.image.corners = .circle },
                    element(id, "Picture.corners=0") { $0.image.corners = .custom(0) },
                    element(id, "Picture.corners=40") { $0.image.corners = .custom(40) },
                    element(id, "Picture.border=6") { $0.image.borderWidth = 6 },
                    element(id, "Picture.opacity=0.1") { $0.image.opacity = 0.1 },
                    element(id, "Picture.fill=fit") { $0.image.contentMode = .fit },
                    element(id, "Picture.fill=fill") { $0.image.contentMode = .fill },
                ]
                if !custom {
                    all.append(element(id, "Picture.nudgeX=40") { $0.image.offsetX = 40 })
                    all.append(element(id, "Picture.nudgeY=40") { $0.image.offsetY = 40 })
                }
            case .line, .chart:
                all += [
                    element(id, "Line.thickness=1") { $0.line.thickness = 1 },
                    element(id, "Line.thickness=16") { $0.line.thickness = 16 },
                    element(id, "Line.ends=butt") { $0.line.cap = .butt },
                    element(id, "Line.ends=square") { $0.line.cap = .square },
                    element(id, "Line.fillStyle=gradient", base: { $0.colors[.fill] = magenta }) { $0.line.fill = .gradient; $0.colors[.fillEnd] = cyan },
                    element(id, "Line.fillEnd colour", base: { $0.line.fill = .gradient; $0.colors[.fill] = magenta }) { $0.colors[.fillEnd] = cyan },
                    element(id, "Line.fillStyle=valueScale") { $0.line.fill = .valueScale; $0.colors[.fill] = .valueScale(.falling) },
                    element(id, "Line.track=0") { $0.line.trackOpacity = 0 },
                    element(id, "Line.track=1") { $0.line.trackOpacity = 1 },
                ]
            case .button:
                all += ButtonLookChoice.allCases.map { look in element(id, "Button.look=\(look.rawValue)") { $0.button.look = look } }
                all += ButtonShapeChoice.allCases.map { shape in element(id, "Button.shape=\(shape.rawValue)") { $0.button.shape = shape } }
                all += [
                    element(id, "Button.label=iconOnly") { $0.button.iconOnly = true },
                    element(id, "Button.label=withTitle") { $0.button.iconOnly = false },
                    element(id, "Button.tintStrength=0.1", base: { $0.colors[.tint] = magenta }) { $0.button.tintStrength = 0.1 },
                ]
                if !custom {
                    all += ControlSizeChoice.allCases.map { size in element(id, "Button.size=\(size.rawValue)") { $0.button.size = size } }
                }
            case .feature:
                break
            }
            // Colours, by the slots the inspector shows.
            for slot in spec.colorSlots where !(spec.role == .text && slot == .primary) {
                if slot == .fillEnd || slot == .backing || slot == .border { continue }
                all.append(element(id, "Colour.\(slot.rawValue)") { $0.colors[slot] = magenta })
            }
            if spec.colorSlots.contains(.backing) {
                all.append(element(id, "Colour.backing", base: { $0.symbol.backing = .circle }) { $0.colors[.backing] = magenta })
            }
            if spec.colorSlots.contains(.border) {
                all.append(element(id, "Colour.border", base: { $0.image.borderWidth = 6 }) { $0.colors[.border] = magenta })
            }
            if spec.isSizable, spec.role != .text, spec.role != .symbol, !custom {
                all.append(Variant(element: id.rawValue, option: "Size=S") { $0.sizes[id] = .small })
                all.append(Variant(element: id.rawValue, option: "Size=L") { $0.sizes[id] = .large })
            }
        }
        // The widget's own.
        all.append(Variant(element: "widget", option: "Accent=red") { $0.tint = .red })
        for background in kind.backgrounds where background != widget.background {
            all.append(Variant(element: "widget", option: "Background=\(background.rawValue)") { $0.background = background })
        }
        if widget.background.hasOpacity {
            all.append(Variant(element: "widget", option: "Background.strength=0.05") { $0.backgroundOpacity = 0.05 })
            all.append(Variant(element: "widget", option: "Background.strength=1") { $0.backgroundOpacity = 1 })
        }
        if kind.backgrounds.contains(.gradient) {
            all.append(Variant(element: "widget", option: "Gradient.from", base: { $0.background = .gradient }) {
                $0.background = .gradient; $0.style.surface.fill = magenta
            })
            all.append(Variant(element: "widget", option: "Gradient.to", base: { $0.background = .gradient }) {
                $0.background = .gradient; $0.style.surface.fillEnd = magenta
            })
        }
        if kind.backgrounds.contains(.artwork) {
            all.append(Variant(element: "widget", option: "Artwork.dim=1", base: { $0.background = .artwork }) {
                $0.background = .artwork; $0.style.surface.artworkDim = 1
            })
        }
        all += [
            Variant(element: "widget", option: "Background.border=4") { $0.style.surface.borderWidth = 4 },
            Variant(element: "widget", option: "Background.border colour", base: { $0.style.surface.borderWidth = 4 }) {
                $0.style.surface.borderWidth = 4; $0.style.surface.border = magenta
            },
            Variant(element: "widget", option: "Background.corners=0") { $0.style.surface.cornerRadius = 0 },
            Variant(element: "widget", option: "Background.corners=40") { $0.style.surface.cornerRadius = 40 },
            Variant(element: "widget", option: "Layout.padding=0") { $0.style.layout.padding = 0 },
            Variant(element: "widget", option: "Layout.padding=24") { $0.style.layout.padding = 24 },
            Variant(element: "widget", option: "Layout.scale=0.5") { $0.style.layout.contentScale = 0.5 },
            Variant(element: "widget", option: "Layout.scale=1.5") { $0.style.layout.contentScale = 1.5 },
        ]
        if !custom {
            for layout in kind.layouts where layout != widget.layout {
                all.append(Variant(element: "widget", option: "Layout=\(layout.rawValue)") { $0.layout = layout })
            }
            if kind.canMirror {
                all.append(Variant(element: "widget", option: "SwapSides") { $0.mirrored = true })
            }
            if kind.spec.stacksElements {
                all += [
                    Variant(element: "widget", option: "Stack.spacing=0") { $0.style.layout.spacing = 0 },
                    Variant(element: "widget", option: "Stack.spacing=24") { $0.style.layout.spacing = 24 },
                    Variant(element: "widget", option: "Stack.direction=horizontal") { $0.style.layout.axis = .horizontal },
                    Variant(element: "widget", option: "Stack.direction=vertical") { $0.style.layout.axis = .vertical },
                    Variant(element: "widget", option: "Stack.alignment=topLeading") { $0.style.layout.alignment = .topLeading },
                    Variant(element: "widget", option: "Stack.alignment=bottomTrailing") { $0.style.layout.alignment = .bottomTrailing },
                ]
            }
        }
        let formats = kind.formatOptions
        if formats.contains(.clock) {
            all.append(Variant(element: "widget", option: "Format.clock=12h") { $0.style.format.clock24Hour = false })
        }
        if formats.contains(.date) {
            all.append(Variant(element: "widget", option: "Format.date=d") { $0.style.format.dateTemplate = "d" })
        }
        if formats.contains(.percent) {
            all.append(Variant(element: "widget", option: "Format.percentDecimals=2") { $0.style.format.percentDecimals = 2 })
        }
        if formats.contains(.duration) {
            for style in DurationStyleChoice.allCases {
                all.append(Variant(element: "widget", option: "Format.duration=\(style.rawValue)") { $0.style.format.durationStyle = style })
            }
        }
        if formats.contains(.temperature) {
            all.append(Variant(element: "widget", option: "Format.temperature=fahrenheit") { $0.style.format.temperature = .fahrenheit })
        }
        all.append(Variant(element: "widget", option: "Behaviour.dimInactive", visible: false) { $0.style.behaviour.dimsWhenInactive = true })
        return all
    }

    // MARK: Checks on one picture against its base

    static func compare(_ base: Picture, _ picture: Picture, variant: String, element: String, size: GridSize, mode: String,
                        visible: Bool, recorder: Recorder) {
        let changed = difference(base, picture)
        if visible, changed < 12 {
            recorder.add(size, mode, element, variant, "noVisibleEffect", "\(changed) bytes differ", before: base, after: picture)
        }
        let spill = picture.spilled - base.spilled
        if spill > 40 {
            recorder.add(size, mode, element, variant, "spillsOutsideWidget", "\(spill) more lit pixels outside the widget",
                         before: base, after: picture)
        }
        for (id, frame) in picture.frames {
            let bounds = CGRect(origin: .zero, size: picture.size).insetBy(dx: -1, dy: -1)
            if !bounds.contains(frame), base.frames[id].map({ bounds.contains($0) }) ?? true {
                recorder.add(size, mode, id.rawValue, variant, "frameOutsideWidget", "\(rect(frame)) in \(rect(bounds))")
            }
            if let ink = picture.inks[id]?.ink, !frame.insetBy(dx: -1.5, dy: -1.5).contains(ink),
               base.inks[id].map({ frame.insetBy(dx: -1.5, dy: -1.5).contains($0.ink) }) ?? true {
                recorder.add(size, mode, id.rawValue, variant, "textInkOutsideItsFrame", "ink \(rect(ink)) frame \(rect(frame))",
                             before: base, after: picture)
            }
        }
        // Elements that overlap only because of the option.
        let ids = picture.frames.keys.sorted { $0.rawValue < $1.rawValue }
        for (i, a) in ids.enumerated() {
            for b in ids[(i + 1)...] {
                guard let fa = visibleBox(picture, a), let fb = visibleBox(picture, b) else { continue }
                let overlap = fa.intersection(fb)
                guard !overlap.isNull, overlap.width > 1.5, overlap.height > 1.5 else { continue }
                if let ba = visibleBox(base, a), let bb = visibleBox(base, b) {
                    let was = ba.intersection(bb)
                    if !was.isNull, was.width > 1.5, was.height > 1.5 { continue }
                }
                recorder.add(size, mode, "\(a.rawValue)+\(b.rawValue)", variant, "overlap", "\(rect(overlap))",
                             before: base, after: picture)
            }
        }
        // Elements gone (an option that hides one says so in its name).
        if !variant.hasPrefix("Shown=off"), !variant.hasPrefix("Eye=off") {
            for id in base.frames.keys where picture.frames[id] == nil {
                recorder.add(size, mode, id.rawValue, variant, "elementVanished", "", before: base, after: picture)
            }
        }
    }

    /// What an element shows: its letters for text, its frame otherwise (blocks that are backgrounds,
    /// like a cover's artwork, are left out of overlaps).
    static func visibleBox(_ picture: Picture, _ id: ElementID) -> CGRect? {
        if let ink = picture.inks[id] { return ink.ink }
        guard let frame = picture.frames[id] else { return nil }
        if frame.width >= picture.size.width - 1 && frame.height >= picture.size.height - 1 { return nil }
        return frame
    }

    static func rect(_ r: CGRect) -> String { String(format: "(%.1f,%.1f %.1f×%.1f)", r.minX, r.minY, r.width, r.height) }

    static func representative(_ kind: IslandWidgetKind) -> GridSize {
        kind.sizePresets.max { $0.width * $0.height < $1.width * $1.height } ?? kind.defaultSize
    }

    static func base(_ kind: IslandWidgetKind, _ size: GridSize) -> IslandWidget {
        IslandWidget(kind: kind, frame: GridRect(column: 0, row: 0, width: size.width, height: size.height),
                     options: kind.defaultOptions, id: WidgetID())
    }

    static func unlocked(_ widget: IslandWidget, from picture: Picture) -> IslandWidget? {
        guard widget.kind.spec.supportsCustomLayout, !picture.frames.isEmpty else { return nil }
        var unlocked = widget
        picture.unlocked.apply(to: &unlocked.style, size: picture.size, scale: model.layout.scale.factor)
        guard unlocked.style.layout.arrangement.isCustom else { return nil }
        return unlocked
    }

    /// For the live pass in the app: a board holding only this kind, at its size with the most room
    /// (`$TMPDIR/WidgetQA/boards/<kind>.json`, what `WidgetStore` keeps under its key).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NI_QA_BOARDS"] != nil)) func boards() throws {
        let folder = Self.output.appendingPathComponent("boards")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for kind in IslandWidgetKind.allCases.filter(\.isOffered) {
            let widget = Self.base(kind, Self.representative(kind))
            try JSONEncoder().encode(WidgetBoard(widgets: [widget])).write(to: folder.appendingPathComponent("\(kind.rawValue).json"))
            let elements = kind.spec.elements.map { "\($0.id.rawValue)\t\($0.role)\t\(widget.shows($0.id) ? "shown" : "hidden")" }
            try elements.joined(separator: "\n").write(to: folder.appendingPathComponent("\(kind.rawValue).elements.txt"),
                                                    atomically: true, encoding: .utf8)
            let size = Self.representative(kind)
            try "\(size.width)x\(size.height)".write(to: folder.appendingPathComponent("\(kind.rawValue).size.txt"), atomically: true, encoding: .utf8)
        }
    }

    /// One picture, to find what traps: `NI_QA_PROBE=kind:WxH:padding:scale`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NI_QA_PROBE"] != nil)) func probe() {
        let parts = ProcessInfo.processInfo.environment["NI_QA_PROBE"]!.split(separator: ":").map(String.init)
        let kind = IslandWidgetKind(rawValue: parts[0])!
        let wh = parts[1].split(separator: "x").map { Int($0)! }
        var widget = Self.base(kind, GridSize(width: wh[0], height: wh[1]))
        widget.style.layout.padding = Double(parts[2])
        widget.style.layout.contentScale = Double(parts[3])
        print("QA-PROBE drawing", parts)
        _ = Self.draw(widget)
        print("QA-PROBE survived", parts)
    }

    /// `NI_QA_SAFE`: leaves out the options known to trap (padding 24 on a one-row list widget).
    static func skips(_ option: String) -> Bool {
        ProcessInfo.processInfo.environment["NI_QA_SAFE"] != nil && option.contains("padding=24")
    }

    /// Unlocking (Custom) draws what the automatic layout drew, at the island sizes people use
    /// (`NI_QA_UNLOCK`): every scale, a 156 pt and a 185 pt notch. Records what differs.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NI_QA_UNLOCK"] != nil)) func unlockFidelity() throws {
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        var lines: [String] = []
        let model = AppModel()
        let saved = model.preferences.scale
        defer { model.preferences.scale = saved }
        for scale in IslandScale.allCases {
            model.preferences.scale = scale
            for notch in [CGSize(width: 156, height: 28), CGSize(width: 185, height: 32)] {
                let layout = IslandLayout(notch: notch, scale: scale)
                let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(layout), grid: .standard)
                for kind in Self.kinds where kind.spec.supportsCustomLayout {
                    for grid in kind.sizePresets {
                        let rect = GridRect(column: 0, row: 0, width: grid.width, height: grid.height)
                        let size = geometry.frame(for: rect).size
                        let widget = IslandWidget(kind: kind, frame: rect, options: kind.defaultOptions)
                        let automatic = Self.draw(widget, size: size, model: model)
                        guard !automatic.frames.isEmpty else { continue }
                        var custom = widget
                        automatic.unlocked.apply(to: &custom.style, size: automatic.size, scale: scale.factor)
                        guard custom.style.layout.arrangement.isCustom else { continue }
                        let unlocked = Self.draw(custom, size: size, model: model)
                        let changed = Self.difference(automatic, unlocked)
                        let lost = automatic.frames.keys.filter { unlocked.frames[$0] == nil }.map(\.rawValue)
                        if changed > 400 || !lost.isEmpty {
                            let name = "unlock-\(kind.rawValue)-\(grid.width)x\(grid.height)-\(scale.rawValue)-\(Int(notch.width))"
                            for (label, picture) in [("auto", automatic), ("custom", unlocked)] {
                                if let image = picture.image {
                                    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                                        .write(to: Self.output.appendingPathComponent("\(name)-\(label).png"))
                                }
                            }
                            lines.append("\(name)\t\(changed)\tlost=\(lost.sorted().joined(separator: ","))")
                        }
                    }
                }
            }
        }
        try lines.joined(separator: "\n").write(to: Self.output.appendingPathComponent("unlock.txt"), atomically: true, encoding: .utf8)
        print("QA-UNLOCK \(lines.count) differ")
    }

    /// The drags of the user's video, on the title: `NI_QA_DRAG`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NI_QA_DRAG"] != nil)) func artistDrag() {
        let harness = CanvasHarness(.nowPlaying, 5, 2)
        harness.session.setCustomLayout(true)
        harness.render()
        if case .text(let t, _, _)? = harness.session.drawn[.artist] { print("QA-ART before \(t.points) \(Self.rect(harness.frame(.artist)!))") }
        let landed = harness.resize(.artist, .bottom, by: CGSize(width: 0, height: -3))
        if case .text(let t, _, _)? = harness.session.drawn[.artist] { print("QA-ART after \(t.points) \(Self.rect(harness.frame(.artist)!)) landed \(Self.rect(landed!))") }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["NI_QA_DRAG"] != nil)) func titleDrags() {
        for (handle, delta) in [(ResizeHandle.bottom, CGSize(width: 0, height: -1000)), (.top, CGSize(width: 0, height: 1000)),
                                (.bottomTrailing, CGSize(width: -1000, height: -1000)), (.trailing, CGSize(width: -1000, height: 0)),
                                (.bottom, CGSize(width: 0, height: 1000))] {
            let harness = CanvasHarness(.nowPlaying, 7, 3)
            harness.session.setCustomLayout(true)
            harness.render()
            let before = harness.frame(.trackInfo)!
            harness.resize(.trackInfo, handle, by: delta)
            let after = harness.frame(.trackInfo)!
            let drawn = harness.session.drawn[.trackInfo]
            print("QA-DRAG \(handle) \(delta): \(Self.rect(before)) -> \(Self.rect(after)) drawn \(String(describing: drawn))")
        }
    }

    /// Pictures of one kind at every size: `NI_QA_PICTURES=kind`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NI_QA_PICTURES"] != nil)) func pictures() throws {
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        let kind = IslandWidgetKind(rawValue: ProcessInfo.processInfo.environment["NI_QA_PICTURES"]!)!
        for grid in kind.sizePresets {
            let picture = Self.draw(Self.base(kind, grid))
            if let image = picture.image {
                try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: Self.output.appendingPathComponent("pic-\(kind.rawValue)-\(grid.width)x\(grid.height).png"))
            }
        }
    }

    // MARK: The sweep

    @Test(arguments: kinds) func sweep(_ kind: IslandWidgetKind) throws {
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        let recorder = Recorder(kind)
        defer { recorder.write() }

        // (A) Every option, at the size with the most room: automatic, then laid out freely.
        let size = Self.representative(kind)
        let automatic = Self.base(kind, size)
        let automaticPicture = Self.draw(automatic)
        if automaticPicture.frames.isEmpty {
            recorder.add(size, "automatic", "widget", "-", "nothingMeasured", "no element reported a frame")
        }
        var modes: [(String, IslandWidget, Picture)] = [("automatic", automatic, automaticPicture)]
        if let custom = Self.unlocked(automatic, from: automaticPicture) {
            let picture = Self.draw(custom)
            let shift = Self.difference(automaticPicture, picture)
            if shift > 400 {
                recorder.add(size, "custom", "widget", "unlock", "unlockChangesPicture", "\(shift) bytes differ",
                             before: automaticPicture, after: picture)
            }
            modes.append(("custom", custom, picture))
        } else if kind.spec.supportsCustomLayout {
            recorder.add(size, "custom", "widget", "unlock", "cannotUnlock", "supportsCustomLayout but nothing to unlock")
        }
        for (mode, widget, picture) in modes {
            for variant in Self.variants(widget, custom: mode == "custom") where !Self.skips(variant.option) {
                var basePicture = picture
                if let base = variant.base {
                    var based = widget
                    base(&based)
                    based.style.sanitize(for: kind)
                    basePicture = Self.draw(based)
                }
                var changed = widget
                variant.apply(&changed)
                // As the editor changes it (`EditorSession.change`).
                LayoutEdit.remeasureButtons(changedFrom: widget.style, in: &changed.style)
                changed.style.sanitize(for: kind)
                let after = Self.draw(changed)
                Self.compare(basePicture, after, variant: variant.option, element: variant.element, size: size, mode: mode,
                             visible: variant.visible, recorder: recorder)
            }
        }

        // (B) Every size, every text and symbol at its largest and widest: what spills, overlaps, vanishes.
        for grid in kind.sizePresets {
            let widget = Self.base(kind, grid)
            let picture = Self.draw(widget)
            var forms: [(String, IslandWidget, Picture)] = [("automatic", widget, picture)]
            if let custom = Self.unlocked(widget, from: picture) { forms.append(("custom", custom, Self.draw(custom))) }
            for (mode, form, formPicture) in forms {
                for (label, edit) in Self.extremes(kind) where !Self.skips(label) {
                    var stressed = form
                    edit(&stressed)
                    stressed.style.sanitize(for: kind)
                    Self.compare(formPicture, Self.draw(stressed), variant: label, element: "all", size: grid, mode: mode,
                                 visible: false, recorder: recorder)
                }
            }
        }

        // (C, D) On the canvas, laid out freely: drags at their limits, the editor's commands.
        if kind.spec.supportsCustomLayout {
            Self.canvas(kind, size, recorder)
        }
    }

    static func extremes(_ kind: IslandWidgetKind) -> [(String, (inout IslandWidget) -> Void)] {
        let texts = kind.spec.elements.filter { $0.role == .text }
        let symbols = kind.spec.elements.filter { $0.role == .symbol }
        return [
            ("ALL largest+widest", { widget in
                for spec in texts {
                    var text = widget.style.elements[spec.id, default: ElementStyle()].text
                    text.points = 96; text.width = .expanded; text.tracking = 10; text.textCase = .uppercase; text.weight = .black
                    if spec.acceptsLabel { text.labelOverride = "A Much Longer Wording Than Fits" }
                    widget.style.elements[spec.id, default: ElementStyle()].text = text
                }
                for spec in symbols { widget.style.elements[spec.id, default: ElementStyle()].symbol.points = 96 }
            }),
            ("ALL 3 lines", { widget in
                for spec in texts { widget.style.elements[spec.id, default: ElementStyle()].text.lineLimit = 3 }
            }),
            ("ALL smallest", { widget in
                for spec in texts {
                    widget.style.elements[spec.id, default: ElementStyle()].text.points = 6
                    widget.style.elements[spec.id, default: ElementStyle()].text.width = .compressed
                }
                for spec in symbols { widget.style.elements[spec.id, default: ElementStyle()].symbol.points = 6 }
            }),
            ("ALL sizes L", { widget in
                for spec in kind.spec.elements where spec.isSizable { widget.sizes[spec.id] = .large }
            }),
            ("Layout.padding=24 + scale 1.5", { widget in
                widget.style.layout.padding = 24; widget.style.layout.contentScale = 1.5
            }),
        ]
    }

    // MARK: The canvas

    static func canvas(_ kind: IslandWidgetKind, _ size: GridSize, _ recorder: Recorder) {
        let harness = CanvasHarness(kind, size.width, size.height)
        let pristine = harness.session.widget
        harness.session.setCustomLayout(true)
        harness.render()
        guard harness.session.layoutState.isCustom else {
            recorder.add(size, "canvas", "widget", "Custom", "customDoesNotUnlock", "\(harness.session.layoutState)")
            return
        }
        let bounds = CGRect(origin: .zero, size: harness.size).insetBy(dx: -0.75, dy: -0.75)
        let ids = harness.session.elementFrames.map(\.id)
        if ids.isEmpty { recorder.add(size, "canvas", "widget", "Custom", "nothingOnCanvas") }
        let start = harness.session.widget

        for id in ids {
            guard let original = harness.frame(id) else { continue }
            let wasDrawn = harness.session.drawn[id] != nil
            // Every handle, far out and far in.
            for handle in ResizeHandle.allCases {
                for far in [CGFloat(1000), -1000] {
                    let delta = CGSize(width: CGFloat(handle.horizontal) * far, height: CGFloat(handle.vertical) * far)
                    let before = harness.session.widget
                    harness.resize(id, handle, by: delta)
                    let changed = harness.session.widget != before
                    let label = "resize \(handle) \(far > 0 ? "out" : "in") 1000pt"
                    if let frame = harness.frame(id) {
                        if !bounds.contains(frame) {
                            recorder.add(size, "canvas", id.rawValue, label, "resizeLeavesWidget", "\(rect(frame)) in \(rect(bounds))")
                        }
                        if frame.width < 6 || frame.height < 4 {
                            recorder.add(size, "canvas", id.rawValue, label, "resizeCollapses", "\(rect(frame))")
                        }
                        if wasDrawn, harness.session.drawn[id] == nil {
                            recorder.add(size, "canvas", id.rawValue, label, "vanishesAfterResize", "\(rect(frame))")
                        }
                    } else {
                        recorder.add(size, "canvas", id.rawValue, label, "elementLostAfterResize")
                    }
                    guard changed else { continue }
                    harness.session.undo()
                    harness.render()
                    if harness.session.widget != before {
                        recorder.add(size, "canvas", id.rawValue, label, "undoDoesNotRestore",
                                     "\(harness.frame(id).map(rect) ?? "nil") was \(rect(original))")
                    }
                }
            }
            // Dragged far off every side.
            for delta in [CGSize(width: 1000, height: 0), CGSize(width: -1000, height: 0), CGSize(width: 0, height: 1000),
                          CGSize(width: 0, height: -1000)] {
                let before = harness.session.widget
                harness.move(id, by: delta)
                if let frame = harness.frame(id), !bounds.contains(frame) {
                    recorder.add(size, "canvas", id.rawValue, "move \(delta)", "moveLeavesWidget", "\(rect(frame))")
                }
                if harness.session.widget != before {
                    harness.session.undo()
                    harness.render()
                }
            }
            // Keep Shape and Locked, then the smallest corner drag.
            let unlockedState = harness.session.widget
            harness.session.editLayout { layout in
                if let i = layout.items.firstIndex(where: { $0.id == id }) { layout.items[i].locked = true }
            }
            harness.render()
            let lockedState = harness.session.widget
            harness.move(id, by: CGSize(width: 20, height: 10))
            if harness.session.widget != lockedState {
                recorder.add(size, "canvas", id.rawValue, "move while Locked", "lockedElementMoves", harness.frame(id).map(rect) ?? "")
                harness.session.undo()
            }
            harness.session.undo()
            harness.render()
            if harness.session.widget != unlockedState {
                recorder.add(size, "canvas", id.rawValue, "Locked, then undo", "undoDoesNotRestore", "")
            }
        }
        if harness.session.widget != start {
            recorder.add(size, "canvas", "widget", "undo after every drag", "undoLeavesChanges", "")
        }

        // Flip twice.
        let before = harness.session.style.layout.arrangement
        harness.session.editLayout { LayoutEdit.flipHorizontally(&$0) }
        harness.render()
        harness.session.editLayout { LayoutEdit.flipHorizontally(&$0) }
        harness.render()
        if let difference = rectDifference(harness.session.style.layout.arrangement, before) {
            recorder.add(size, "canvas", "widget", "Flip twice", "flipTwiceIsNotOriginal", difference)
        }

        // Decorations: each lands inside the widget, is drawn, duplicates and deletes.
        let decorations: [Decoration] = [.label("Label"), .symbol("star.fill"), .divider(.horizontal), .divider(.vertical)]
            + DecorationShape.allCases.map { .shape($0) }
        for decoration in decorations {
            harness.session.addDecoration(decoration)
            harness.render()
            guard let added = harness.session.selectedElement else {
                recorder.add(size, "canvas", "decoration", "+Add \(decoration.title)", "decorationNotAdded")
                continue
            }
            if let frame = harness.frame(added) {
                if !bounds.contains(frame) { recorder.add(size, "canvas", added.rawValue, "+Add \(decoration.title)", "decorationOutside", rect(frame)) }
            } else {
                recorder.add(size, "canvas", added.rawValue, "+Add \(decoration.title)", "decorationNotDrawn")
            }
            harness.session.duplicateSelection()
            harness.render()
            let copies = harness.session.selection
            if copies.count != 1 || copies.contains(added) {
                recorder.add(size, "canvas", added.rawValue, "⌘D \(decoration.title)", "duplicateFailed", "\(copies)")
            }
            harness.session.selection = copies.union([added])
            harness.session.hideSelection()
            harness.render()
            if harness.frame(added) != nil {
                recorder.add(size, "canvas", added.rawValue, "Delete \(decoration.title)", "decorationNotRemoved")
            }
        }

        // The eye against Shown, laid out freely.
        for spec in kind.spec.elements where !spec.isRequired && kind.options.contains(spec.id) {
            guard let widget = harness.session.widget, widget.shows(spec.id), harness.frame(spec.id) != nil else { continue }
            harness.store.update(widget.id) { $0.options.remove(spec.id) }
            harness.render()
            let probeFrames = harness.probe.frames
            if probeFrames[spec.id] != nil {
                recorder.add(size, "canvas", spec.id.rawValue, "Eye=off (custom)", "hiddenElementStillDrawn", "")
            }
            harness.store.update(widget.id) { $0.options.insert(spec.id) }
            harness.render()
        }

        // Undo all the way back, then redo.
        let edited = harness.session.widget
        for _ in 0..<200 { harness.session.undo() }
        harness.render()
        if let now = harness.session.widget, let pristine, now.style != pristine.style {
            recorder.add(size, "canvas", "widget", "Undo ×200", "undoDoesNotReachStart", "")
        }
        for _ in 0..<200 { harness.session.redo() }
        harness.render()
        if let now = harness.session.widget, let edited, now.style != edited.style {
            recorder.add(size, "canvas", "widget", "Redo ×200", "redoDoesNotReachEnd", "")
        }

        // Reset Widget: back to the kind's own look.
        harness.session.resetWidget()
        harness.render()
        if let widget = harness.session.widget, !widget.style.isEmpty || widget.tint != .automatic {
            recorder.add(size, "canvas", "widget", "Reset Widget", "resetLeavesStyle", "")
        }
        if harness.session.layoutState.isCustom {
            recorder.add(size, "canvas", "widget", "Reset Widget", "resetKeepsCustomLayout", "")
        }

        // Laid out at one size, drawn at every other.
        harness.session.setCustomLayout(true)
        harness.render()
        if let authored = harness.session.widget {
            for grid in kind.sizePresets where grid != size {
                var other = authored
                other.frame = GridRect(column: 0, row: 0, width: grid.width, height: grid.height)
                let picture = draw(other)
                let base = draw(base(kind, grid))
                let widgetBounds = CGRect(origin: .zero, size: picture.size).insetBy(dx: -1, dy: -1)
                for (id, frame) in picture.frames where !widgetBounds.contains(frame) {
                    recorder.add(grid, "reflow", id.rawValue, "authored at \(size.width)x\(size.height)", "reflowLeavesWidget", rect(frame))
                }
                for id in base.frames.keys where picture.frames[id] == nil && authored.shows(id) {
                    recorder.add(grid, "reflow", id.rawValue, "authored at \(size.width)x\(size.height)", "reflowDropsElement", "",
                                 before: base, after: picture)
                }
                compare(base, picture, variant: "reflowed from \(size.width)x\(size.height)", element: "all", size: grid,
                        mode: "reflow", visible: false, recorder: recorder)
            }
        }

        // Copied onto another kind and back: nothing breaks.
        if let widget = harness.session.widget {
            let copied = CopiedStyle(widget)
            var other = base(.nowPlaying, representative(.nowPlaying))
            copied.apply(to: &other)
            other.style.sanitize(for: .nowPlaying)
            if draw(other).frames.isEmpty {
                recorder.add(size, "canvas", "widget", "Paste onto Now Playing", "pasteBreaksTarget")
            }
        }
    }

    static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }

    /// The first rectangle that differs between two arrangements, nil when none does.
    static func rectDifference(_ a: ElementArrangement?, _ b: ElementArrangement?) -> String? {
        guard case .custom(let la)? = a, case .custom(let lb)? = b else { return a == b ? nil : "arrangement \(a == nil) vs \(b == nil)" }
        func rects(_ layouts: CustomLayouts) -> [String: [Double]] {
            var out: [String: [Double]] = [:]
            for (sizeClass, variant) in layouts.variants {
                guard case .custom(let layout) = variant else { continue }
                for item in layout.items {
                    out["\(sizeClass)-\(item.id.rawValue)"] = [item.rect.x, item.rect.y, item.rect.width, item.rect.height,
                                                                Double(item.pinX.hashValue % 7), Double(item.pinY.hashValue % 7)]
                }
            }
            return out
        }
        let (ra, rb) = (rects(la), rects(lb))
        guard ra.keys == rb.keys else { return "items \(Set(ra.keys).symmetricDifference(rb.keys))" }
        for (key, value) in ra where !zip(value, rb[key]!).allSatisfy({ abs($0 - $1) < 0.0005 }) {
            return "\(key): \(value.prefix(4).map { String(format: "%.4f", $0) }) vs \(rb[key]!.prefix(4).map { String(format: "%.4f", $0) })"
        }
        return nil
    }
}
