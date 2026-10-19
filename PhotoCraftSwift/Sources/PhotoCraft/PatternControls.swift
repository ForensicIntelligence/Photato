import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

struct PatternNameDraft: Identifiable {
  enum Purpose {
    case define
    case rename(String)
  }
  let id = UUID()
  let purpose: Purpose
  var name: String
}

extension EditorStore {
  func beginDefinePattern() {
    guard !geometryBusy, !hasToneDraft, transformDraft == nil, !patterns.busy else { return }
    patternNameDraft = .init(purpose: .define, name: document.name)
  }
  func definePattern(name: String) {
    guard !geometryBusy, !hasToneDraft, transformDraft == nil, !patterns.busy else { return }
    let original = document
    geometryBusy = true
    status = "Define Pattern"
    geometryTask = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) {
        try PatternDefinition.make(in: original, name: name)
      }
      do {
        let pattern = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        guard let self else { return }
        try await self.patterns.install([pattern])
        self.bucketUsesPattern = true
        self.colorTab = .patterns
        self.status = "Pattern saved: \(pattern.displayName)"
      } catch is CancellationError { self?.status = "Pattern creation cancelled" } catch {
        self?.error = error.localizedDescription
      }
      self?.geometryBusy = false
    }
  }
  func patternAction(_ operation: @escaping @MainActor () async throws -> Void) {
    Task { [weak self] in
      do { try await operation() } catch { self?.error = error.localizedDescription }
    }
  }
  func importPatterns() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "pat") ?? .data]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    patternAction { [weak self] in
      let worker = Task.detached(priority: .userInitiated) {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= PatternArchive.maxBytes else {
          throw CraftError.invalid("PAT file is too large.")
        }
        return try PATCodec.readLibrary(Data(contentsOf: url, options: .mappedIfSafe))
      }
      let incoming = try await worker.value
      try await self?.patterns.install(incoming.patterns)
      self?.colorTab = .patterns
      self?.status =
        incoming.foldersFlattened
        ? "Imported \(incoming.patterns.count) patterns into a flat list; preset folders are not retained."
        : "Imported \(incoming.patterns.count) patterns"
      if incoming.duplicateRecordsMerged > 0 {
        self?.status += " Merged \(incoming.duplicateRecordsMerged) identical presets."
      }
    }
  }
  func exportPatterns(all: Bool) {
    let items = all ? patterns.items : patterns.selected.map { [$0] } ?? []
    guard !items.isEmpty else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "pat") ?? .data]
    panel.nameFieldStringValue = all ? "Photato Patterns.pat" : "\(items[0].displayName).pat"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    patternAction {
      try await Task.detached(priority: .userInitiated) {
        let data = try PATCodec.write(items)
        try data.write(to: url, options: .atomic)
      }.value
    }
  }
}

struct PatternNameSheet: View {
  @Bindable var store: EditorStore
  let draft: PatternNameDraft
  @State private var name: String
  init(store: EditorStore, draft: PatternNameDraft) {
    self.store = store
    self.draft = draft
    _name = State(initialValue: draft.name)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Pattern Name").font(.headline)
      TextField("Name", text: $name).textFieldStyle(.roundedBorder)
      if case .define = draft.purpose {
        Text(
          "Uses the visible image within the selection bounds, or the full canvas when no selection is active."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button("Cancel") { store.patternNameDraft = nil }.keyboardShortcut(.cancelAction)
        Button("OK") {
          store.patternNameDraft = nil
          switch draft.purpose {
          case .define: store.definePattern(name: name)
          case .rename(let id):
            store.patternAction { try await store.patterns.rename(id, to: name) }
          }
        }.keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(24).frame(width: 350)
  }
}

struct PatternSwatch: View {
  let pattern: RasterPattern
  @State private var image: CGImage?
  var body: some View {
    ZStack {
      Color(white: 0.65)
      Canvas { context, size in
        for y in 0..<8 {
          for x in 0..<8 where (x + y) % 2 == 0 {
            context.fill(
              Path(
                CGRect(
                  x: CGFloat(x) * size.width / 8, y: CGFloat(y) * size.height / 8,
                  width: size.width / 8, height: size.height / 8)),
              with: .color(.white.opacity(0.5)))
          }
        }
      }
      if let image { Image(decorative: image, scale: 1).resizable().interpolation(.none) }
    }.task(id: pattern) {
      let worker = Task.detached(priority: .utility) {
        let sampler = try PatternSampler(pattern)
        let step = max(1, Double(max(pattern.surface.width, pattern.surface.height)) / 64)
        var pixels = try Surface(width: 64, height: 64)
        for y in 0..<64 {
          try Task.checkCancellation()
          for x in 0..<64 {
            pixels.setPixel(
              x: x, y: y, sampler.tile(u: Double(x) * step + 0.5, v: Double(y) * step + 0.5))
          }
        }
        return try RasterIO.displayImage(pixels)
      }
      do {
        let result = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        image = result
      } catch {}
    }
  }
}

struct PatternsPanel: View {
  @Bindable var store: EditorStore
  @State private var search = ""
  var body: some View {
    VStack(spacing: 8) {
      HStack {
        TextField("Search patterns", text: $search).textFieldStyle(.roundedBorder)
        Menu {
          Button("Import Patterns…") { store.importPatterns() }
          Button("Export Selected Pattern…") { store.exportPatterns(all: false) }.disabled(
            store.patterns.selected == nil)
          Button("Export All Patterns…") { store.exportPatterns(all: true) }.disabled(
            store.patterns.items.isEmpty)
          Divider()
          Button("Restore Built-in Patterns") {
            store.patternAction { try await store.patterns.resetBuiltins() }
          }
        } label: {
          Image(systemName: "line.3.horizontal")
        }.menuStyle(.borderlessButton).frame(width: 22)
      }
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 7)], spacing: 7) {
          ForEach(
            store.patterns.items.filter {
              search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search)
            }
          ) { pattern in
            Button {
              store.choosePattern(pattern)
            } label: {
              PatternSwatch(pattern: pattern).frame(height: 44)
                .overlay(
                  Rectangle().stroke(
                    store.patterns.selected?.id == pattern.id
                      ? StudioTheme.accent : .white.opacity(0.2), lineWidth: 2))
            }.buttonStyle(.plain).help(
              "\(pattern.displayName) · \(pattern.surface.width) × \(pattern.surface.height)"
            )
            .accessibilityLabel(pattern.displayName)
          }
        }.padding(2)
      }
      if let selected = store.patterns.selected {
        Text("\(selected.displayName) · \(selected.surface.width) × \(selected.surface.height)")
          .lineLimit(1).font(.caption).foregroundStyle(.secondary)
      } else {
        Text("Define or import a pattern to get started.").foregroundStyle(.secondary)
      }
      if let error = store.patterns.error { Text(error).font(.caption).foregroundStyle(.orange) }
      HStack {
        Text("Paint Bucket patterns").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button {
          store.beginDefinePattern()
        } label: {
          Image(systemName: "plus.square")
        }.help("Define Pattern from this document")
        Button {
          if let pattern = store.patterns.selected {
            store.patternNameDraft = .init(purpose: .rename(pattern.id), name: pattern.displayName)
          }
        } label: {
          Image(systemName: "pencil")
        }.disabled(store.patterns.selected == nil).help("Rename Pattern")
        Button {
          if let id = store.patterns.selected?.id {
            store.patternAction { try await store.patterns.remove(id) }
          }
        } label: {
          Image(systemName: "trash")
        }.disabled(store.patterns.selected == nil).help("Delete Pattern")
      }.buttonStyle(.plain)
      if store.patterns.busy { ProgressView().controlSize(.small) }
    }.padding(9).disabled(store.patterns.busy || store.geometryBusy)
  }
}

extension WorkspaceView {
  var bucketPatternPicker: some View {
    HStack(spacing: 4) {
      if let pattern = store.patterns.selected {
        PatternSwatch(pattern: pattern).frame(width: 24, height: 24)
      }
      Menu {
        ForEach(store.patterns.items) { pattern in
          Button(pattern.displayName) { store.patterns.selectedID = pattern.id }
        }
        Divider()
        Button("Open Patterns Panel") { store.colorTab = .patterns }
        Button("Import Patterns…") { store.importPatterns() }
      } label: {
        Text(store.patterns.selected?.displayName ?? "Choose Pattern").lineLimit(1).frame(
          maxWidth: 120)
      }.menuStyle(.borderlessButton)
    }.frame(width: 150).disabled(store.patterns.busy)
  }
}
