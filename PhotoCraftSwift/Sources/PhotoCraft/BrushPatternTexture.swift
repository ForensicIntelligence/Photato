import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

enum BrushTextureSelectionError: LocalizedError {
  case stale
  var errorDescription: String? { "The document, brush or pattern library changed. Choose the texture again." }
}

@MainActor extension EditorStore {
  var canChooseBrushTexture: Bool {
    canUseBrush && brushGesture == nil && !patterns.busy
  }

  /// Capture library/settings before preparation; publish one complete tool state
  /// only after cancellation, source and optional API authorization checks pass.
  func chooseBrushTexture(_ patternID: String, configured: Brush? = nil,
    prepare: (@Sendable (RasterPattern) throws -> BrushBitmap)? = nil,
    authorize: @MainActor () throws -> Void = {}) async throws {
    guard canChooseBrushTexture else {
      throw CraftError.invalid("Finish the current edit or pattern load before choosing a brush texture.")
    }
    guard let pattern = patterns.items.first(where: { $0.id == patternID }) else {
      throw CraftError.invalid("The brush texture pattern no longer exists.")
    }
    let source = PatternDialogSource(self), revision = brushRevision
    let session = sessionGeneration, generation = layerPanelGeneration
    var next = configured ?? brush
    try BrushPainter.validate(next, points: [])
    let prepare = prepare ?? brushTexturePreparation
    var published = false
    geometryBusy = true; brushTextureLoading = true
    status = "Preparing brush texture"
    defer {
      brushTextureLoading = false
      if sessionGeneration == session && layerPanelGeneration == generation {
        geometryBusy = false; geometryTask = nil
        if !published { status = "Brush texture unchanged" }
      }
    }
    let worker = Task.detached(priority: .userInitiated) { try prepare(pattern) }
    geometryTask = Task {
      await withTaskCancellationHandler(operation: { _ = try? await worker.value }, onCancel: { worker.cancel() })
    }
    let bitmap = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    try Task.checkCancellation()
    if geometryTask?.isCancelled == true { throw CancellationError() }
    guard source.matches(self), brushRevision == revision else {
      throw BrushTextureSelectionError.stale
    }
    next.settings = next.settings ?? .init()
    next.settings!.texture.bitmap = bitmap
    next.settings!.texture.enabled = true
    try BrushPainter.validate(next, points: [])
    try authorize()
    brush = next
    backgroundColor = next.backgroundColor ?? backgroundColor
    published = true
    status = "Brush texture ready"
  }
}

@MainActor struct BrushPatternTexturePicker: View {
  @Bindable var store: EditorStore
  @State private var warning: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Menu("Choose Pattern…") {
        BrushPatternTextureMenu(store: store, parent: nil) { id in
          store.geometryTask = Task {
            do { try await store.chooseBrushTexture(id); warning = nil }
            catch is CancellationError { warning = "Texture selection cancelled." }
            catch { warning = error.localizedDescription }
          }
        }
      }.accessibilityIdentifier("brush.texture.choosePattern")
        .disabled(!store.canChooseBrushTexture)
      if let bitmap = store.brushOptions.texture.bitmap {
        Text("Embedded pattern: \(bitmap.width) × \(bitmap.height) px").foregroundStyle(.secondary)
      }
      Text("Define or import patterns in the Patterns panel.").font(.caption).foregroundStyle(.secondary)
      if let warning { Text(warning).foregroundStyle(.secondary).textSelection(.enabled) }
    }
  }
}

@MainActor private struct BrushPatternTextureMenu: View {
  @Bindable var store: EditorStore
  let parent: UUID?
  let choose: (String) -> Void
  var body: some View {
    ForEach(store.patterns.state.nodes.filter { $0.parentID == parent }) { node in
      if node.isGroup {
        Menu(node.name) { BrushPatternTextureMenu(store: store, parent: node.id, choose: choose) }
      } else if let id = node.patternID, let pattern = store.patterns.items.first(where: { $0.id == id }) {
        Button("\(pattern.displayName) (\(pattern.surface.width) × \(pattern.surface.height))") { choose(id) }
          .disabled(pattern.surface.width > 2500 || pattern.surface.height > 2500)
          .help("Embed this pattern in the brush. Textures support up to 2500 × 2500 pixels.")
      }
    }
  }
}
