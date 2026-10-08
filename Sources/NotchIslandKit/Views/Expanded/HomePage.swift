import SwiftUI

/// A page of widgets: home's board, the timer's, the battery's or one the user added (`WidgetPages`),
/// arranged in Settings ▸ Widgets.
struct HomePage: View {
    var page: ExpandedPage = .home

    @Environment(AppModel.self) private var model

    var body: some View {
        WidgetBoardView(board: model.boards.store(for: page).board)
            .contextMenu {
                Button("Customize Island…", systemImage: "square.grid.3x2") {
                    model.studio.page = page
                    model.showCustomize()
                }
            }
    }
}
