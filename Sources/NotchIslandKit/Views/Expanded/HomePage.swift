import SwiftUI

/// The user's widget board (Customize Island).
struct HomePage: View {
    let thumbnails: ThumbnailCache

    @Environment(AppModel.self) private var model

    var body: some View {
        WidgetBoardView(board: model.widgets.board, thumbnails: thumbnails)
            .contextMenu {
                Button("Customize Island…", systemImage: "square.grid.3x2") { model.showCustomize() }
            }
    }
}
