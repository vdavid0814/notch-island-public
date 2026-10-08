import CoreGraphics
import Foundation

/// A widget drawn at another size than the one Customize placed its parts at (`designSize`).
///
/// Where its parts are moved, the texts' boxes and sizes, the playback line's parts: all set in
/// points, at one size. At another size of the same layout they are taken along with it — moves and
/// boxes as far as the widget is wider or taller (the texts as far as the room they are set in is
/// wider: Now Playing's column beside the cover), letters as much smaller (or larger) as the smaller
/// of the two — so the whole shrinks or grows as one. At a size laid out another way (Now
/// Playing on one row, placed on three), where they were set means nothing: the parts are where
/// the layout puts them, set as large as it sets them, their looks (colours, styles, buttons) kept.
extension IslandWidget {
    /// The size its parts were placed at: the one set, or the kind's own.
    var effectiveDesignSize: GridSize { designSize ?? kind.defaultSize }

    /// One cell, where the widget is its one part — a control's button, the battery's ring, the
    /// clock's dial: that part fills it and stays there (it is not moved or sized, in Customize or
    /// as drawn), only styled.
    var isOneElement: Bool {
        frame.width == 1 && frame.height == 1 && (kind.control != nil || kind == .battery || kind == .analogClock)
    }

    /// Its parts as at `frame`'s size, from `effectiveDesignSize`: `keepsPlacement` where the
    /// layout is the same at both. `textWidth`: how much wider the texts' room is (nil: as the widget).
    func adapted(keepsPlacement: Bool, textWidth: Double? = nil) -> IslandWidget {
        let design = effectiveDesignSize
        guard design != frame.size, design.width > 0, design.height > 0 else { return self }
        let x = Double(frame.width) / Double(design.width), y = Double(frame.height) / Double(design.height)
        let textX = textWidth ?? x
        let texts = Set(kind.spec.texts)
        var adapted = self
        adapted.designSize = frame.size
        guard keepsPlacement else {
            adapted.offsets = [:]
            adapted.scales = [:]
            adapted.textStyles = textStyles.compactMapValues { style in
                var style = style
                style.box = nil
                style.size = nil
                style.maximumSize = nil
                style.minimumSize = nil
                style.linesFillBox = false
                style.maxLines = nil
                return style
            }
            adapted.progressLooks = progressLooks.mapValues { look in
                var look = look
                look.barOffset = .zero
                look.elapsedOffset = .zero
                look.remainingOffset = .zero
                return look
            }
            adapted.sanitize()
            return adapted
        }
        let letters = min(textX, y)
        adapted.offsets = Dictionary(uniqueKeysWithValues: offsets.map { id, offset in
            (id, offset.scaled(x: texts.contains(id) ? textX : x, y: y))
        })
        adapted.textStyles = textStyles.mapValues { style in
            var style = style
            style.box = style.box.map {
                TextStyle.BoxSize(width: max($0.width * textX, Double(ElementResize.minimum)),
                                  height: max($0.height * y, Double(ElementResize.minimum)))
            }
            style.size = style.size.map { $0 * letters }
            style.maximumSize = style.maximumSize.map { $0 * letters }
            style.minimumSize = style.minimumSize.map { $0 * letters }
            return style
        }
        adapted.progressLooks = progressLooks.mapValues { look in
            var look = look
            look.barOffset = look.barOffset.scaled(x: x, y: y)
            look.elapsedOffset = look.elapsedOffset.scaled(x: x, y: y)
            look.remainingOffset = look.remainingOffset.scaled(x: x, y: y)
            return look
        }
        adapted.sanitize()
        return adapted
    }
}

extension ElementOffset {
    func scaled(x: Double, y: Double) -> ElementOffset { ElementOffset(x: self.x * x, y: self.y * y) }
}

extension IslandWidget {
    /// The widget with `id`'s text in `design` where Customize left its typeface at Default: the
    /// widget's own (a clock's rounded figures) stays as it was when the text is restyled.
    func withOwnDesign(_ design: TextStyle.Design, for id: ElementID) -> IslandWidget {
        guard var style = textStyles[id], style.design == .standard else { return self }
        var widget = self
        style.design = design
        widget.textStyles[id] = style
        return widget
    }
}
