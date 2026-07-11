import SwiftUI

struct ContentView: View {
    @State private var selectedPaperID: UUID?
    @State private var inspectorPresented = true

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(selection: $selectedPaperID)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            ReaderPlaceholderView(hasSelection: selectedPaperID != nil)
                .inspector(isPresented: $inspectorPresented) {
                    AnnotationInspectorView(hasSelection: selectedPaperID != nil)
                        .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
                }
                .toolbar {
                    ToolbarItem {
                        Button {
                            inspectorPresented.toggle()
                        } label: {
                            Label("Annotations", systemImage: "sidebar.right")
                        }
                    }
                }
        }
    }
}

