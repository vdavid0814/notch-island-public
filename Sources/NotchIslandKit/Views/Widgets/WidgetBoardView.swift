import SwiftUI

/// A page of the panel: the user's widgets, each on its own cells of the board grid. A widget in a
/// bottom corner of the board is concentric with the panel's (`WidgetBoardShape`).
struct WidgetBoardView: View {
    let board: WidgetBoard

    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let geometry = WidgetBoardGeometry(size: proxy.size, grid: board.grid)
            ZStack(alignment: .topLeading) {
                ForEach(board.widgets) { widget in
                    let frame = geometry.frame(for: widget.frame)
                    IslandWidgetView(widget: widget, size: frame.size)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .environment(\.widgetBoard, WidgetBoardShape(grid: board.grid, cornerRadius: ConcentricGeometry.boardCornerRadius(model.layout)))
    }
}
