import Foundation

/// Clipboard's symbols one by one, and the editor's copy and paste.
nonisolated extension IslandWidget {
    // MARK: Clipboard's symbols

    /// Clipboard's rows: as many as set, else one in a widget a row tall and three in a taller one.
    var clipRowCount: Int { config.count ?? (frame.height <= 1 ? 1 : 3) }

    /// The rows with a symbol, in order: none with Symbols off, the first alone until set, only
    /// rows there are.
    var clipSymbolRows: [Int] {
        guard shows(.clipSymbols) else { return [] }
        return (config.symbolRows ?? [1]).filter { $0 <= clipRowCount }
    }

    /// `rows` with a symbol, the first alone stored as nil.
    private mutating func setClipSymbolRows(_ rows: [Int]) {
        let rows = Array(Set(rows)).sorted()
        config.symbolRows = rows == [1] ? nil : rows
    }

    /// One row's symbol gone, how it was styled, moved and sized with it; the last one gone,
    /// Symbols is off (on again, the first row has one).
    mutating func removeClipSymbol(_ row: Int) {
        let id = ElementID.clipSymbol(row)
        buttonLooks[id] = nil
        offsets[id] = nil
        scales[id] = nil
        layers[id] = nil
        let rows = clipSymbolRows.filter { $0 != row }
        if rows.isEmpty {
            options.remove(.clipSymbols)
            config.symbolRows = nil
        } else {
            setClipSymbolRows(rows)
        }
    }

    /// A symbol on the first row without one (Symbols switched on where it was off), as `like` is
    /// styled, moved from its row and sized in `source`; nil where every row has one.
    @discardableResult
    mutating func addClipSymbol(like: ElementID? = nil, in source: IslandWidget? = nil) -> ElementID? {
        var rows = clipSymbolRows
        if !shows(.clipSymbols) {
            options.insert(.clipSymbols)
            rows = []
        }
        guard let row = (1...max(clipRowCount, 1)).first(where: { !rows.contains($0) }) else {
            setClipSymbolRows(rows)
            return nil
        }
        setClipSymbolRows(rows + [row])
        let id = ElementID.clipSymbol(row)
        if let like, let source {
            buttonLooks[id] = source.buttonLooks[like]
            offsets[id] = source.offsets[like]
            scales[id] = source.scales[like]
        }
        return id
    }

    // MARK: Copy and paste

    /// What a paste did: a new part (to pick), the copied look set on the parts picked, or nothing.
    enum Pasted: Equatable {
        case added(ElementID)
        case styled
        case nothing
    }

    /// `copied`, a part of `source`, pasted: a Clipboard symbol on the next row without one, a
    /// shape as a second one beside it; any other part's look set on the parts `picked` of its sort
    /// (a text's style but its box, a button's, a line's, a picture's, a chart's).
    mutating func paste(_ copied: ElementID, from source: IslandWidget, onto picked: Set<ElementID>) -> Pasted {
        if kind == .clipboard, source.kind == .clipboard, let row = copied.clipRow, copied == .clipSymbol(row) {
            return addClipSymbol(like: copied, in: source).map(Pasted.added) ?? .nothing
        }
        if let figure = source.figure(copied) {
            guard figures.count < WidgetFigure.limit else { return .nothing }
            var copy = WidgetFigure.new(figure.kind)
            copy.color = figure.color
            copy.corners = figure.corners
            copy.isFilled = figure.isFilled
            copy.rotation = figure.rotation
            figures.append(copy)
            scales[copy.id] = source.scales[copied]
            layers[copy.id] = source.layers[copied]
            // A little way off, so it is seen as a second one.
            let offset = source.offset(of: copied)
            offsets[copy.id] = ElementOffset(x: offset.x + 6, y: offset.y + 6)
            return .added(copy.id)
        }
        let spec = source.kind.spec
        var styled = false
        for part in picked where part != copied || source.id != id {
            if spec.texts.contains(copied) || spec.innerTexts.contains(copied),
               kind.spec.texts.contains(part) || kind.spec.innerTexts.contains(part) {
                var style = source.textStyle(of: copied)
                style.box = textStyle(of: part).box
                setTextStyle(style, of: part)
                styled = true
            } else if spec.buttons.contains(copied), kind.spec.buttons.contains(part) {
                buttonLooks[part] = source.buttonLooks[copied]
                styled = true
            } else if spec.progressBars.contains(copied), kind.spec.progressBars.contains(part) {
                progressLooks[part] = source.progressLooks[copied]
                styled = true
            } else if spec.images.contains(copied), kind.spec.images.contains(part) {
                imageLooks[part] = source.imageLooks[copied]
                styled = true
            } else if spec.charts.contains(copied), kind.spec.charts.contains(part) {
                chartLooks[part] = source.chartLooks[copied]
                styled = true
            } else if spec.rulers.contains(copied), kind.spec.rulers.contains(part) {
                rulerLooks[part] = source.rulerLooks[copied]
                styled = true
            } else if spec.dayGrids.contains(copied), kind.spec.dayGrids.contains(part) {
                dayGridLooks[part] = source.dayGridLooks[copied]
                styled = true
            }
        }
        if styled { sanitize() }
        return styled ? .styled : .nothing
    }
}
