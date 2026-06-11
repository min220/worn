//
//  ContentView.swift
//  worn
//

import SwiftUI
import SwiftData
import PhotosUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    
    // Controls the action sheet ("Photo Library" / "Take Picture" / "Choose from Files")
    @State private var showingSourceMenu = false
    
    // Controls each individual picker
    @State private var showingPhotosPicker = false
    @State private var showingCamera = false
    @State private var showingFilesPicker = false
    
    // Holds the picked image before we save it
    @State private var pickedImage: UIImage?
    @State private var photosPickerItem: PhotosPickerItem?
    // Vibe search
    @State private var searchQuery: String = ""
    @State private var isSearching: Bool = false
    @State private var searchResults: [Item] = []
    @State private var searchReasoning: String = ""
    @State private var hasSearched: Bool = false
    
    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("describe a vibe... (e.g. \"warm night dinner date\")", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .submitLabel(.search)
                        .onSubmit { runVibeSearch() }
                    if !searchQuery.isEmpty {
                        Button {
                            clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.wornSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 4)
                // Item count
                HStack {
                    Text("^[\(items.count) item](inflect: true) in closet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Loading / results explanation
                if isSearching {
                    HStack {
                        ProgressView()
                        Text("finding pieces for that vibe...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else if hasSearched && !searchReasoning.isEmpty {
                    Text(searchReasoning)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Grid — shows either all items, or search results
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(itemsToDisplay) { item in
                        gridCell(for: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // Empty state for searches that found nothing
                if hasSearched && searchResults.isEmpty && !isSearching {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("no matches for that vibe")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("try a different description, or add more items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.wornBackground)
            .navigationTitle("My Closet")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSourceMenu = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .confirmationDialog("Add a clothing item", isPresented: $showingSourceMenu, titleVisibility: .visible) {
                Button("Photo Library") { showingPhotosPicker = true }
                Button("Take Picture") { showingCamera = true }
                Button("Choose from Files") { showingFilesPicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showingPhotosPicker, selection: $photosPickerItem, matching: .images)
            .onChange(of: photosPickerItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            saveNewItem(image: uiImage)
                        }
                    }
                    photosPickerItem = nil
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(image: $pickedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: pickedImage) { _, newImage in
                if let image = newImage {
                    saveNewItem(image: image)
                    pickedImage = nil
                }
            }
            .fileImporter(
                isPresented: $showingFilesPicker,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
                            saveNewItem(image: uiImage)
                        }
                    }
                }
            }
        }
    }

    // Returns either filtered search results, or all items if not searching
    private var itemsToDisplay: [Item] {
        hasSearched ? searchResults : items
    }
    private func saveNewItem(image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        
        // Create the item with the original photo first (so UI is instant)
        let newItem = Item(
            name: "Tagging…",
            imageData: data
        )
        
        withAnimation {
            modelContext.insert(newItem)
        }
        
        // Run background removal + AI tagging in parallel
        Task {
            // Background removal happens on-device, usually <1s
            async let processedImage = BackgroundRemover.removeBackground(from: image)
            async let tags = AIService.tagImage(image)
            
            // Wait for both
            let removedBg = await processedImage
            
            // Update the image with the cutout if it worked
            if let cleanImage = removedBg,
               let pngData = cleanImage.pngData() {
                await MainActor.run {
                    newItem.imageData = pngData
                }
            }
            
            // Apply AI tags
            do {
                let result = try await tags
                await MainActor.run {
                    newItem.name = result.name
                    newItem.category = result.category
                    newItem.colors = result.colors
                    newItem.formality = result.formality
                    newItem.vibeTags = result.vibeTags
                    newItem.occasionTags = result.occasionTags
                    newItem.weatherTags = result.weatherTags
                }
            } catch {
                print("AI tagging failed: \(error)")
                await MainActor.run {
                    newItem.name = "Untitled item"
                }
            }
        }
    }
    @ViewBuilder
    private func gridCell(for item: Item) -> some View {
        NavigationLink {
            ItemDetailView(item: item)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let data = item.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.wornSurface)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "tshirt")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        )
                }
                
                Text(item.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                Text("worn \(item.wearCount)x")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                deleteItem(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    private func deleteItem(_ item: Item) {
        withAnimation {
            modelContext.delete(item)
        }
    }
    private func runVibeSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearSearch()
            return
        }
        
        isSearching = true
        hasSearched = true
        
        Task {
            do {
                let result = try await AIService.searchByVibe(query: trimmed, items: items)
                await MainActor.run {
                    // Match returned IDs back to actual items
                    let idToItem = Dictionary(uniqueKeysWithValues: items.map { ($0.persistentModelID.hashValue.description, $0) })
                    searchResults = result.itemIds.compactMap { idToItem[$0] }
                    searchReasoning = result.reasoning
                    isSearching = false
                }
            } catch {
                print("Vibe search failed: \(error)")
                await MainActor.run {
                    searchResults = []
                    searchReasoning = "search failed — try again"
                    isSearching = false
                }
            }
        }
    }

    private func clearSearch() {
        searchQuery = ""
        searchResults = []
        searchReasoning = ""
        hasSearched = false
    }
}

// MARK: - Item Detail View

struct ItemDetailView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingDeleteAlert = false
    @State private var isEditingName = false
    @State private var editedName = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Image
                if let data = item.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .background(Color.wornSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                // Name (with inline edit)
                HStack(spacing: 8) {
                    if isEditingName {
                        TextField("Name", text: $editedName)
                            .font(.title2)
                            .bold()
                            .textFieldStyle(.plain)
                            .submitLabel(.done)
                            .onSubmit {
                                commitNameEdit()
                            }
                        
                        Button {
                            commitNameEdit()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        
                        Button {
                            cancelNameEdit()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(item.name)
                            .font(.title2)
                            .bold()
                        
                        Button {
                            startNameEdit()
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Basic info
                VStack(alignment: .leading, spacing: 10) {
                    DetailRow(label: "Category", value: item.category.isEmpty ? "untagged" : item.category)
                    DetailRow(label: "Formality", value: formalityLabel(item.formality))
                    DetailRow(label: "Worn", value: "\(item.wearCount) \(item.wearCount == 1 ? "time" : "times")")
                    
                    HStack(alignment: .top) {
                        Text("Last worn")
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .leading)
                        if let lastWorn = item.lastWorn {
                            Text(formattedDate(lastWorn))
                        } else {
                            Text("Never worn yet").foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.subheadline)
                
                // Tag sections
                if !item.colors.isEmpty {
                    TagSection(title: "Colors", tags: item.colors)
                }
                if !item.vibeTags.isEmpty {
                    TagSection(title: "Vibe", tags: item.vibeTags)
                }
                if !item.occasionTags.isEmpty {
                    TagSection(title: "Occasion", tags: item.occasionTags)
                }
                if !item.weatherTags.isEmpty {
                    TagSection(title: "Weather", tags: item.weatherTags)
                }
                
                // Mark as worn
                Button {
                    item.markWorn()
                } label: {
                    Label("Mark as worn", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
                
                // Delete
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete item", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Color.wornBackground)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete this item?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                modelContext.delete(item)
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
    }
    
    private func formalityLabel(_ value: Int) -> String {
        switch value {
        case 1: return "lounge"
        case 2: return "casual"
        case 3: return "dressy"
        case 4: return "business"
        case 5: return "formal"
        default: return "untagged"
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func startNameEdit() {
        editedName = item.name
        isEditingName = true
    }

    private func commitNameEdit() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            item.name = trimmed
        }
        isEditingName = false
    }

    private func cancelNameEdit() {
        editedName = ""
        isEditingName = false
    }
}

// MARK: - Detail Row (label + value)

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
            Spacer()
        }
    }
}

// MARK: - Tag Section (a label + a wrap of pill tags)

struct TagSection: View {
    let title: String
    let tags: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.wornTagBg)
                        .foregroundStyle(Color.wornAccent)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Flow layout for tag pills that wrap to next line

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var currentLineWidth: CGFloat = 0
        var currentLineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentLineWidth + size.width > maxWidth {
                totalHeight += currentLineHeight + spacing
                currentLineWidth = size.width + spacing
                currentLineHeight = size.height
            } else {
                currentLineWidth += size.width + spacing
                currentLineHeight = max(currentLineHeight, size.height)
            }
        }
        totalHeight += currentLineHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var currentLineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += currentLineHeight + spacing
                currentLineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            currentLineHeight = max(currentLineHeight, size.height)
        }
    }
}
