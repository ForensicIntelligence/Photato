import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

@MainActor @Observable final class FitImageDraft {
  let source: CraftDocument
  let generation: UUID
  var width = "1024"
  var height = "1024"
  var dontEnlarge = false
  var method: Resampling
  var error: String?
  init(source: CraftDocument, generation: UUID) {
    self.source = source; self.generation = generation
    method = source.colorMode.isRestricted ? .nearest : .bicubic
  }
  func options() throws -> FitImageOptions {
    guard let width = Int(width.trimmingCharacters(in: .whitespacesAndNewlines)),
      let height = Int(height.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      throw CraftError.invalid("Enter whole pixel dimensions for Fit Image.")
    }
    let value = FitImageOptions(width: width, height: height, dontEnlarge: dontEnlarge, method: method)
    try value.validate(); return value
  }
}

extension EditorStore {
  var canBeginFitImage: Bool {
    canSelectComponentTarget && document.animation == nil && document.videoTimeline == nil
  }
  func beginFitImage() {
    guard canBeginFitImage else { return }
    fitImageDraft = FitImageDraft(source: document, generation: layerPanelGeneration)
    geometrySheet = .fitImage
  }
  func cancelFitImage() { if geometrySheet == .fitImage { geometrySheet = nil } }
  func commitFitImage(_ draft: FitImageDraft) {
    guard fitImageDraft === draft, geometrySheet == .fitImage else { return }
    do {
      guard !geometryBusy, !aiBusy, !hasToneDraft, transformDraft == nil, historyOperation == nil,
        !coalescingChanges else { throw CraftError.invalid("Finish the current interaction before fitting the image.") }
      guard draft.source == document, draft.generation == layerPanelGeneration else {
        throw CraftError.invalid("The document changed. Cancel and reopen Fit Image.")
      }
      let options = try draft.options()
      geometrySheet = nil
      performGeometry(label: "Fit Image", allowAuxiliary: true,
        prepare: { _ in .fitImage(options) }, onSuccess: { self.fit() })
    } catch { draft.error = error.localizedDescription }
  }
}

struct FitImageSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: FitImageDraft
  private var result: String? {
    guard let options = try? draft.options(),
      let size = try? options.dimensions(sourceWidth: draft.source.width, sourceHeight: draft.source.height) else { return nil }
    return "\(draft.source.width) × \(draft.source.height) → \(size.width) × \(size.height) pixels"
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Fit Image").font(.headline)
      GroupBox("Fit Within") {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
          GridRow {
            Text("Width:")
            TextField("Width", text: $draft.width).accessibilityIdentifier("fitImage.width")
            Text("Pixels").foregroundStyle(.secondary)
          }
          GridRow {
            Text("Height:")
            TextField("Height", text: $draft.height).accessibilityIdentifier("fitImage.height")
            Text("Pixels").foregroundStyle(.secondary)
          }
        }.textFieldStyle(.roundedBorder).padding(8)
      }
      Toggle("Don’t Enlarge", isOn: $draft.dontEnlarge).accessibilityIdentifier("fitImage.dontEnlarge")
      if let result { Text(result).font(.caption).foregroundStyle(.secondary) }
      if let error = draft.error { Text(error).foregroundStyle(.red).font(.caption) }
      HStack {
        Spacer()
        Button("Cancel") { store.cancelFitImage() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitFitImage(draft) }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 360)
  }
}

@MainActor extension AppDelegate {
  @objc func fitImage() { store?.beginFitImage() }
}
