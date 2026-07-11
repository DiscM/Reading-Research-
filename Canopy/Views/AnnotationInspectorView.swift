import SwiftUI

struct AnnotationInspectorView: View {
    let hasSelection: Bool

    var body: some View {
        Group {
            if hasSelection {
                ContentUnavailableView("No Annotations", systemImage: "highlighter", description: Text("Highlights and optional notes will appear here in page order."))
            } else {
                ContentUnavailableView("Annotations", systemImage: "sidebar.right", description: Text("Choose a paper to inspect its highlights and notes."))
            }
        }
        .navigationTitle("Annotations")
    }
}

