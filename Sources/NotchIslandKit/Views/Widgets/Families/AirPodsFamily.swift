import SwiftUI

/// The AirPods' widget (`AirPodsSpecs`): their batteries as last reported.
struct AirPodsFamily: View, WidgetFamilyElements {
    let widget: IslandWidget
    let size: CGSize

    var body: some View {
        AirPodsBatteryWidget(widget: widget, size: size)
    }

    func demands(_ input: PlanInput) -> [ElementDemand] { ReadingWidget.demands(input) }

    func element(_ id: ElementID) -> some View {
        AirPodsReadingSource { ReadingElement(id: id, reading: $0) }
    }
}
