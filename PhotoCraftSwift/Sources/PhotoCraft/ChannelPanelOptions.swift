import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

enum ChannelThumbnailSize: String, Codable, CaseIterable, Sendable {
  case none, small, medium, large
  var title: String { rawValue.capitalized }
  var edge: CGFloat {
    switch self {
    case .none: 0
    case .small: 32
    case .medium: 57
    case .large: 82
    }
  }
  var rowHeight: CGFloat { self == .none ? 22 : edge + 5 }
}

struct ChannelPanelOptions: Codable, Equatable, Sendable {
  var thumbnailSize = ChannelThumbnailSize.small
}

@MainActor @Observable final class ChannelPanelOptionsDraft: Identifiable {
  let id = UUID()
  let libraryID: UUID
  let generation: UUID
  let original: ChannelPanelOptions
  var options: ChannelPanelOptions
  var error: String?
  init(store: EditorStore) {
    libraryID = store.workspaceLibrary.identity
    generation = store.layerPanelGeneration
    original = store.workspaceLibrary.channelPanelOptions
    options = original
  }
}

extension EditorStore {
  func beginChannelPanelOptions() {
    finishNumericField()
    finishLayerName()
    guard canBeginLayerCreation else { return }
    channelPanelOptionsDraft = ChannelPanelOptionsDraft(store: self)
  }
  func cancelChannelPanelOptions() { channelPanelOptionsDraft = nil }
  func commitChannelPanelOptions(_ draft: ChannelPanelOptionsDraft) {
    guard channelPanelOptionsDraft === draft else { return }
    guard workspaceLibrary.identity == draft.libraryID,
      layerPanelGeneration == draft.generation,
      workspaceLibrary.channelPanelOptions == draft.original
    else {
      draft.error = "The panel settings changed. Cancel and reopen Panel Options."
      return
    }
    do {
      try workspaceLibrary.setChannelPanelOptions(draft.options)
      channelPanelOptionsDraft = nil
    } catch { draft.error = error.localizedDescription }
  }

  func previewChannel(_ channel: RGBChannelPreview) {
    finishNumericField()
    finishLayerName()
    guard !geometryBusy, !hasToneDraft, transformDraft == nil else { return }
    clearMaskView()
    maskEditingLayerID = nil
    if document.inkMode != nil { if channel == .composite { try? selectInkChannels([]) }; return }
    if usesModeChannels { modeComponentVisibility = channel == .composite ? nil : [channel.rawValue - 1]; render() } else { channelView.selectPreview(channel) }
  }

  var canChangeChannelVisibility: Bool {
    !geometryBusy && !hasToneDraft && transformDraft == nil
      && !editingMask && currentMaskView == nil
  }

  @discardableResult func setChannelVisibility(_ channel: RGBChannelPreview, visible: Bool) -> Bool
  {
    finishNumericField()
    finishLayerName()
    guard canChangeChannelVisibility, document.inkMode == nil else { return false }
    if usesModeChannels {
      guard document.colorMode == .rgb else { return false }
      let targets = channel == .composite ? Set(0..<3) : [channel.rawValue - 1]
      let proposed = visible ? modeVisibleComponents.union(targets) : modeVisibleComponents.subtracting(targets)
      if !proposed.isEmpty { try? setModeComponentVisibility(proposed) }
    } else { channelView.setVisible(channel, visible) }
    return true
  }
}

struct ChannelPanelOptionsSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: ChannelPanelOptionsDraft
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Channels Panel Options").font(.headline)
      HStack(alignment: .top, spacing: 16) {
        GroupBox("Thumbnail Size") {
          Picker("Thumbnail Size", selection: $draft.options.thumbnailSize) {
            ForEach(ChannelThumbnailSize.allCases, id: \.self) { size in
              HStack {
                if size == .none {
                  Text("None")
                } else {
                  // Reuse our original illustration in grayscale, not Adobe's artwork.
                  ThumbnailSizeExample().saturation(0).frame(
                    width: size.edge + 1, height: size.edge + 1
                  )
                  .accessibilityLabel(size.title)
                }
              }.tag(size)
            }
          }.pickerStyle(.radioGroup).labelsHidden()
            .accessibilityIdentifier("channelPanelOptions.size").padding(6)
        }
        VStack(spacing: 8) {
          Button("OK") { store.commitChannelPanelOptions(draft) }.keyboardShortcut(.defaultAction)
          Button("Cancel") { store.cancelChannelPanelOptions() }.keyboardShortcut(.cancelAction)
        }.frame(width: 72)
      }
      if let error = draft.error {
        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
    }.padding(20).fixedSize()
  }
}

struct ChannelsMenu: View {
  @Bindable var store: EditorStore
  var body: some View {
    Button("New Channel…") { store.newAlphaChannel() }.disabled(!store.canEditChannels)
    Button("Duplicate Channel…") { if let id = store.alphaEditingID { store.perform(.channel(.duplicate(id,nil))) } }.disabled(!store.canEditChannels || store.alphaEditingID == nil)
    Button("Delete Channels") { if let id = store.alphaEditingID { store.perform(.channel(.delete(id))) } }.disabled(!store.canEditChannels || store.alphaEditingID == nil)
    Divider()
    Button("New Spot Channel…") {if store.document.colorMode == .multichannel {store.beginInkChannelOptions()}else{store.beginChannelDialog(.newSpot)}}.disabled(!store.canEditChannels || store.document.colorMode.isRestricted || store.document.colorMode == .duotone)
    Button("Merge Spot Channel") {}.disabled(true)
    Divider()
    Button("Channel Options…") { store.beginChannelDialog(.options) }.disabled(!store.canEditChannels || store.editingChannel == nil)
    Button("Split Channels") {}.disabled(true)
    Button("Merge Channels…") {}.disabled(true)
    Divider()
    Button("Panel Options…") { store.beginChannelPanelOptions() }
      .disabled(!store.canBeginLayerCreation)
  }
}
