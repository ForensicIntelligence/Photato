import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

enum LayerThumbnailSize: String, Codable, CaseIterable, Sendable {
  case none, small, medium, large
  var title: String { rawValue.capitalized }
  var controlHeight: CGFloat {
    switch self {
    case .none: 18
    case .small: 24
    case .medium: 36
    case .large: 64
    }
  }
  var imageWidth: CGFloat { self == .none ? 14 : controlHeight - 1 }
  var imageHeight: CGFloat { self == .none ? 14 : controlHeight - 2 }
  var exampleEdge: CGFloat {
    switch self {
    case .none: 0
    case .small: 33
    case .medium: 58
    case .large: 83
    }
  }
}

struct LayerPanelOptions: Codable, Equatable, Sendable {
  var thumbnailSize = LayerThumbnailSize.medium
  var thumbnailContents = ThumbnailFraming.entireDocument
}

struct LayerRowMetrics {
  let size: LayerThumbnailSize
  let indentation: CGFloat
  let thumbnailWidth: CGFloat
  let thumbnailHeight: CGFloat
  init(size: LayerThumbnailSize, layer: Layer, depth: Int, availableWidth: CGFloat) {
    self.size = size
    let count = 1 + (layer.mask == nil ? 0 : 1) + (layer.vectorMask == nil ? 0 : 1)
    // Reserve native eye/disclosure/link controls, row gaps and a readable name.
    let fixed: CGFloat =
      112 + (layer.mask == nil ? 0 : 25)
      + (layer.vectorMask == nil ? 0 : 10) + (layer.locked ? 24 : 0)
      + (layer.isGroup ? 20 : 0) + (layer.isClipped ? 18 : 0)
    indentation = min(
      CGFloat(min(8, max(0, depth))) * 10,
      max(0, availableWidth - fixed - CGFloat(count) * size.imageWidth))
    thumbnailWidth = min(
      size.imageWidth, max(14, (availableWidth - fixed - indentation) / CGFloat(count)))
    thumbnailHeight = min(size.imageHeight, thumbnailWidth * size.imageHeight / size.imageWidth)
  }
}

@MainActor @Observable final class LayerPanelOptionsDraft: Identifiable {
  let id = UUID()
  let libraryID: UUID
  let generation: UUID
  let original: LayerPanelOptions
  var options: LayerPanelOptions
  var error: String?
  init(store: EditorStore) {
    libraryID = store.workspaceLibrary.identity
    generation = store.layerPanelGeneration
    original = store.workspaceLibrary.layerPanelOptions
    options = original
  }
}

extension EditorStore {
  func beginLayerPanelOptions() {
    finishLayerName()
    guard canBeginLayerCreation else { return }
    layerPanelOptionsDraft = LayerPanelOptionsDraft(store: self)
  }
  func cancelLayerPanelOptions() { layerPanelOptionsDraft = nil }
  func commitLayerPanelOptions(_ draft: LayerPanelOptionsDraft) {
    guard layerPanelOptionsDraft === draft else { return }
    guard workspaceLibrary.identity == draft.libraryID,
      layerPanelGeneration == draft.generation,
      workspaceLibrary.layerPanelOptions == draft.original
    else {
      draft.error = "The panel settings changed. Cancel and reopen Panel Options."
      return
    }
    do {
      try workspaceLibrary.setLayerPanelOptions(draft.options)
      layerPanelOptionsDraft = nil
    } catch { draft.error = error.localizedDescription }
  }
}

struct LayerPanelOptionsSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: LayerPanelOptionsDraft
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Layers Panel Options").font(.headline)
      HStack(alignment: .top, spacing: 20) {
        VStack(alignment: .leading, spacing: 12) {
          GroupBox("Thumbnail Size") {
            Picker("Thumbnail Size", selection: $draft.options.thumbnailSize) {
              ForEach(LayerThumbnailSize.allCases, id: \.self) { size in
                HStack(spacing: 8) {
                  if size == .none {
                    Text("None")
                  } else {
                    ThumbnailSizeExample().frame(width: size.exampleEdge, height: size.exampleEdge)
                      .accessibilityLabel(size.title)
                  }
                }.tag(size)
              }
            }.pickerStyle(.radioGroup).labelsHidden()
              .accessibilityIdentifier("layerPanelOptions.size")
              .frame(maxWidth: .infinity, alignment: .leading).padding(6)
          }
          GroupBox("Thumbnail Contents") {
            Picker("Thumbnail Contents", selection: $draft.options.thumbnailContents) {
              Text("Layer Bounds").tag(ThumbnailFraming.layerBounds)
              Text("Entire Document").tag(ThumbnailFraming.entireDocument)
            }.pickerStyle(.radioGroup).labelsHidden()
              .accessibilityIdentifier("layerPanelOptions.contents")
              .frame(maxWidth: .infinity, alignment: .leading).padding(6)
          }
          // Keep reference order; never enable a preference with no complete behavior.
          Toggle("Use Default Masks on Fill Layers", isOn: .constant(true)).disabled(true)
          Toggle("Expand New Effects", isOn: .constant(false)).disabled(true)
          Toggle("Add “copy” to Copied Layers and Groups", isOn: .constant(true)).disabled(true)
          Toggle("Preview on canvas when reordering layers", isOn: .constant(false)).disabled(true)
          Toggle("Show layer mask badges", isOn: .constant(false)).disabled(true)
        }
        VStack(spacing: 8) {
          Button("OK") { store.commitLayerPanelOptions(draft) }.keyboardShortcut(.defaultAction)
          Button("Cancel") { store.cancelLayerPanelOptions() }.keyboardShortcut(.cancelAction)
        }.frame(width: 72)
      }
      if let error = draft.error {
        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
    }.padding(20).frame(width: 500).fixedSize(horizontal: false, vertical: true)
  }
}

/// Original native drawing for the size examples; no Photoshop image assets are bundled.
struct ThumbnailSizeExample: View {
  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color(red: 0.56, green: 0.72, blue: 0.79)
        Circle().fill(Color(red: 0.98, green: 0.83, blue: 0.46))
          .frame(width: proxy.size.width * 0.28, height: proxy.size.height * 0.28)
          .offset(x: proxy.size.width * 0.18, y: -proxy.size.height * 0.18)
        Path { p in
          p.move(to: CGPoint(x: 0, y: proxy.size.height * 0.75))
          p.addLine(to: CGPoint(x: proxy.size.width * 0.4, y: proxy.size.height * 0.4))
          p.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * 0.8))
          p.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
          p.addLine(to: CGPoint(x: 0, y: proxy.size.height))
          p.closeSubpath()
        }.fill(Color(red: 0.20, green: 0.40, blue: 0.39))
      }.border(Color.gray, width: 1)
    }
  }
}

extension AppDelegate {
  /// Offscreen diagnostic of our own native dialog, not a live Photoshop comparison.
  func layerPanelOptionsSnapshot() {
    do {
      let store = EditorStore(document: try CraftDocument(width: 3, height: 2))
      store.renderTask?.cancel()
      store.beginLayerPanelOptions()
      guard let draft = store.layerPanelOptionsDraft else { return }
      let host = NSHostingView(
        rootView: LayerPanelOptionsSheet(store: store, draft: draft)
          .background(StudioTheme.panel).preferredColorScheme(.dark))
      host.frame = NSRect(origin: .zero, size: host.fittingSize)
      let window = NSWindow(
        contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.contentView = host
      window.appearance = NSAppearance(named: .darkAqua)
      window.layoutIfNeeded()
      host.layoutSubtreeIfNeeded()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [window, host] in
        do {
          window.layoutIfNeeded()
          host.layoutSubtreeIfNeeded()
          guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CraftError.invalid("Layers Panel Options snapshot allocation failed.")
          }
          host.cacheDisplay(in: host.bounds, to: rep)
          guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CraftError.invalid("Layers Panel Options snapshot encoding failed.")
          }
          let path = CommandLine.arguments.last ?? "/private/tmp/photato-layer-options.png"
          try data.write(to: URL(fileURLWithPath: path))
          print("Offscreen Layers Panel Options snapshot: \(path)")
        } catch { print("Layers Panel Options snapshot failed: \(error)") }
        NSApp.terminate(nil)
      }
    } catch {
      print("Layers Panel Options snapshot setup failed: \(error)")
      NSApp.terminate(nil)
    }
  }
}
