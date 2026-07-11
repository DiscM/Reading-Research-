import SwiftUI

struct ReaderPlaceholderView: View {
    let hasSelection: Bool

    var body: some View {
        if hasSelection {
            ContentUnavailableView("Reader Foundation", systemImage: "doc.richtext", description: Text("PDFKit integration is the next implementation slice."))
        } else {
            ContentUnavailableView("Choose a Paper", systemImage: "book.pages", description: Text("Select a recent or library paper to begin reading."))
        }
    }
}

