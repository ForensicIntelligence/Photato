import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

@MainActor @Observable final class NewLayerDraft: Identifiable {
  let id = UUID()
  let original: CraftDocument
  let below: Bool
  var options: NewPixelLayerOptions
  var opacityText = "100"
  var error: String?
  init(document: CraftDocument, below: Bool) {
    original = document
    self.below = below
    options = .init(name: document.suggestedPixelLayerName)
  }
  var validatedOptions: NewPixelLayerOptions? {
    guard let percent = Float(opacityText), percent.isFinite, (0...100).contains(percent),
      !options.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      options.name.utf16.count <= 65_535,
      !options.neutralFill || options.mode.neutralFillValue != nil
    else { return nil }
    var result = options
    result.opacity = percent / 100
    return result
  }
  var canClip: Bool {
    var candidate = original
    var options = NewPixelLayerOptions(name: "Layer")
    options.clipped = true
    return (try? Command.newPixelLayer(options, below: below).apply(to: &candidate)) != nil
  }
}

extension EditorStore {
  var canBeginLayerCreation: Bool {
    !geometryBusy && !hasToneDraft && transformDraft == nil && geometrySheet == nil
      && !showAI && !showGaps && !showFeatherSelection && patternNameDraft == nil
      && gradientNameDraft == nil && layerProtectionDraft == nil && error == nil
  }
  func canCreatePixelLayer(below: Bool = false) -> Bool {
    guard !editingComponent, canBeginLayerCreation else { return false }
    var candidate = document
    return (try? Command.newPixelLayer(.init(name: "Layer"), below: below).apply(to: &candidate))
      != nil
  }
  func beginNewLayer(below: Bool = false) {
    finishLayerName()
    guard canCreatePixelLayer(below: below) else { return }
    newLayerDraft = NewLayerDraft(document: document, below: below)
  }
  func cancelNewLayer() { newLayerDraft = nil }
  func commitNewLayer(_ draft: NewLayerDraft) {
    guard newLayerDraft === draft, let options = draft.validatedOptions else { return }
    guard document == draft.original, !geometryBusy, transformDraft == nil else {
      draft.error = "The document changed. Cancel and reopen New Layer."
      return
    }
    // Clear the modal guard only after validation. One command records all settings.
    newLayerDraft = nil
    guard canCreatePixelLayer(below: draft.below) else {
      draft.error = "Finish the current edit before creating a layer."
      newLayerDraft = draft
      return
    }
    error = nil
    perform(.newPixelLayer(options, below: draft.below))
    if let error {
      draft.error = error
      self.error = nil
      newLayerDraft = draft
    } else {
      maskEditingLayerID = nil
      selectPath(nil)
    }
  }
  func createPixelLayerFromFooter(modifiers: NSEvent.ModifierFlags) {
    let below = modifiers.contains(.command)
    if modifiers.contains(.option) {
      beginNewLayer(below: below)
    } else {
      addPixelLayer(below: below)
    }
  }
}

extension LayerColorLabel {
  var swatch: Color {
    switch self {
    case .none: .clear
    case .red: Color(red: 0.91, green: 0.32, blue: 0.29)
    case .orange: .orange
    case .yellow: .yellow
    case .green: Color(red: 0.39, green: 0.73, blue: 0.40)
    case .blue: Color(red: 0.30, green: 0.56, blue: 0.93)
    case .violet: Color(red: 0.68, green: 0.46, blue: 0.87)
    case .gray: .gray
    case .seafoam: Color(red: 0.39, green: 0.79, blue: 0.67)
    case .indigo: Color(red: 0.46, green: 0.46, blue: 0.85)
    case .magenta: Color(red: 0.83, green: 0.38, blue: 0.63)
    case .fuchsia: Color(red: 0.91, green: 0.41, blue: 0.84)
    }
  }
}

struct NewLayerSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: NewLayerDraft
  @FocusState private var nameFocused: Bool
  var neutralTitle: String {
    guard let value = draft.options.mode.neutralFillValue else {
      return "Fill with mode-neutral color"
    }
    let color = value == 0 ? "black" : value == 1 ? "white" : "50% gray"
    return "Fill with \(draft.options.mode.rawValue)-neutral color (\(color))"
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("New Layer").font(.headline)
      HStack(alignment: .top, spacing: 20) {
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            Text("Name:").frame(width: 48, alignment: .trailing)
            TextField("Name", text: $draft.options.name).labelsHidden()
              .focused($nameFocused).accessibilityIdentifier("newLayer.name")
          }
          Toggle("Use Previous Layer to Create Clipping Mask", isOn: $draft.options.clipped)
            .disabled(!draft.canClip).accessibilityIdentifier("newLayer.clipped")
          HStack {
            Text("Color:").frame(width: 48, alignment: .trailing)
            Picker("Color", selection: $draft.options.color) {
              ForEach(LayerColorLabel.allCases, id: \.self) { color in
                HStack {
                  Image(systemName: "square.fill").foregroundStyle(color.swatch)
                  Text(color.title)
                }.tag(color)
              }
            }.labelsHidden().frame(width: 158).accessibilityIdentifier("newLayer.color")
            Spacer(minLength: 0)
          }
          HStack {
            Text("Mode:").frame(width: 48, alignment: .trailing)
            Picker("Mode", selection: $draft.options.mode) {
              ForEach(BlendMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
            }.labelsHidden().frame(width: 158).accessibilityIdentifier("newLayer.mode")
            Text("Opacity:")
            TextField("Opacity", text: $draft.opacityText).labelsHidden().frame(width: 48)
              .multilineTextAlignment(.trailing).accessibilityIdentifier("newLayer.opacity")
            Text("%")
          }
          Toggle(neutralTitle, isOn: $draft.options.neutralFill)
            .disabled(draft.options.mode.neutralFillValue == nil)
            .accessibilityIdentifier("newLayer.neutralFill")
        }
        VStack(spacing: 10) {
          Button("OK") { store.commitNewLayer(draft) }.keyboardShortcut(.defaultAction)
            .disabled(draft.validatedOptions == nil).frame(width: 76)
          Button("Cancel") { store.cancelNewLayer() }.keyboardShortcut(.cancelAction)
            .frame(width: 76)
        }
      }
      if let error = draft.error {
        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
    }.padding(20).frame(width: 560).font(.system(size: 12)).controlSize(.small)
      .onAppear { nameFocused = true }
      .onChange(of: draft.options.mode) { _, mode in
        if mode.neutralFillValue == nil { draft.options.neutralFill = false }
      }
  }
}

extension AppDelegate {
  /// Our own offscreen content, not a live sheet or a Photoshop reference capture.
  func newLayerSnapshot() {
    do {
      let store = EditorStore(document: try CraftDocument(width: 3, height: 2))
      store.renderTask?.cancel()
      store.beginNewLayer()
      guard let draft = store.newLayerDraft else { return }
      if CommandLine.arguments.contains("--snapshot-new-layer-neutral") {
        draft.options.name = "Dodge & Burn"
        draft.options.mode = .softLight
        draft.options.color = .seafoam
        draft.options.clipped = true
        draft.options.neutralFill = true
        draft.opacityText = "75"
      }
      let host = NSHostingView(
        rootView: NewLayerSheet(store: store, draft: draft)
          .background(StudioTheme.panel).preferredColorScheme(.dark))
      host.frame = .init(x: 0, y: 0, width: 560, height: 260)
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
            throw CraftError.invalid("New Layer snapshot allocation failed.")
          }
          host.cacheDisplay(in: host.bounds, to: rep)
          guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CraftError.invalid("New Layer snapshot encoding failed.")
          }
          let path = CommandLine.arguments.last ?? "/private/tmp/photato-new-layer.png"
          try data.write(to: URL(fileURLWithPath: path))
          print("Offscreen New Layer snapshot: \(path)")
        } catch { print("New Layer snapshot failed: \(error)") }
        NSApp.terminate(nil)
      }
    } catch {
      print("New Layer snapshot setup failed: \(error)")
      NSApp.terminate(nil)
    }
  }
}
