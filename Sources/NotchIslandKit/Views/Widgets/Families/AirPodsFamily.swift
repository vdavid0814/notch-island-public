import SwiftUI

/// The AirPods' widget (`AirPodsSpecs`): a placeholder until it is built.
struct AirPodsFamily: View {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        WidgetPlaceholder(kind: widget.kind, size: size)
    }
}
