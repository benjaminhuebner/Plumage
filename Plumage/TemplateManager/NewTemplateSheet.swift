import SwiftUI
import UniformTypeIdentifiers

// The image the user picked for a new template: an SF Symbol, or an image file to
// import into the override store.
enum NewTemplateImageChoice {
    case symbol(String)
    case importedFile(URL)
}

// A validated request to author a custom template. The model turns it into a
// descriptor, an own layer file and (for `.importedFile`) a copied image.
struct NewTemplateRequest {
    let name: String
    let imageChoice: NewTemplateImageChoice
    let categoryID: String
    let startingPoint: TemplateStartingPoint
}

// Authoring sheet for a custom template. Name and an image are required (Add stays
// disabled until both are present); the user also picks a category and a starting
// point (empty or a copy of an existing template).
struct NewTemplateSheet: View {
    let catalog: TemplateCatalog
    let onAdd: (NewTemplateRequest) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var imageMode: ImageMode = .symbol
    @State private var selectedSymbol = "doc"
    @State private var importedImageURL: URL?
    @State private var startingPoint: TemplateStartingPoint = .empty
    @State private var categoryID: String
    @State private var isImportingImage = false

    enum ImageMode: String, CaseIterable, Identifiable {
        case symbol = "Symbol"
        case file = "Image File"
        var id: String { rawValue }
    }

    private static let symbols = [
        "doc", "doc.text", "folder", "hammer", "wrench.and.screwdriver", "terminal",
        "server.rack", "globe", "macwindow", "iphone", "ipad", "applewatch",
        "cpu", "memorychip", "cube", "shippingbox", "gearshape", "bolt",
        "star", "flag", "tag", "paintbrush", "sparkles", "swift",
        "leaf", "bird", "ant", "tortoise", "network", "cloud",
    ]

    init(catalog: TemplateCatalog, onAdd: @escaping (NewTemplateRequest) -> Bool) {
        self.catalog = catalog
        self.onAdd = onAdd
        _categoryID = State(initialValue: catalog.sortedCategories.first?.id ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var imageProvided: Bool {
        switch imageMode {
        case .symbol: true
        case .file: importedImageURL != nil
        }
    }

    private var canAdd: Bool { !trimmedName.isEmpty && imageProvided && !categoryID.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Template").font(.headline)

            Form {
                TextField("Name", text: $name)
                Picker("Category", selection: $categoryID) {
                    ForEach(catalog.sortedCategories) { category in
                        Text(category.name).tag(category.id)
                    }
                }
                Picker("Start from", selection: $startingPoint) {
                    Text("Empty").tag(TemplateStartingPoint.empty)
                    ForEach(catalog.templatesSortedByName) { template in
                        Text("Copy of \(template.name)").tag(TemplateStartingPoint.copy(template.id))
                    }
                }
            }
            .formStyle(.grouped)

            imageSection

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { if onAdd(request) { dismiss() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder
    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Image", selection: $imageMode) {
                ForEach(ImageMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch imageMode {
            case .symbol: symbolGrid
            case .file: fileChooser
            }
        }
    }

    private var symbolGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 8)], spacing: 8) {
                // Buttons, not tap gestures: a tap-only grid is invisible to
                // VoiceOver and unreachable by keyboard, blocking the whole
                // create flow.
                ForEach(Self.symbols, id: \.self) { symbol in
                    Button {
                        selectedSymbol = symbol
                    } label: {
                        Image(systemName: symbol)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        symbol == selectedSymbol
                                            ? Color.accentColor.opacity(0.25) : .clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        symbol == selectedSymbol ? Color.accentColor : .clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                    .accessibilityAddTraits(symbol == selectedSymbol ? .isSelected : [])
                }
            }
            .padding(2)
        }
        .frame(height: 120)
    }

    private var fileChooser: some View {
        HStack(spacing: 12) {
            Group {
                if let url = importedImageURL, let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage).resizable().scaledToFit()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)

            Button("Choose Image…") { isImportingImage = true }
            if let url = importedImageURL {
                Text(url.lastPathComponent).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .fileImporter(isPresented: $isImportingImage, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { importedImageURL = url }
        }
    }

    private var request: NewTemplateRequest {
        let imageChoice: NewTemplateImageChoice
        switch imageMode {
        case .symbol: imageChoice = .symbol(selectedSymbol)
        case .file: imageChoice = importedImageURL.map { .importedFile($0) } ?? .symbol(selectedSymbol)
        }
        return NewTemplateRequest(
            name: trimmedName, imageChoice: imageChoice,
            categoryID: categoryID, startingPoint: startingPoint)
    }
}
