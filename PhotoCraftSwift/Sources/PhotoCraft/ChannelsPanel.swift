import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

struct ChannelThumbnailRequest: Equatable {
  let owner: UUID
  let generation: UUID
  let composite: UUID
  let maximumSize: Int
}

@MainActor @Observable final class ChannelThumbnailCache {
  private(set) var request: ChannelThumbnailRequest?
  private(set) var images: [CGImage] = []
  private(set) var error: String?

  func update(
    _ request: ChannelThumbnailRequest, source: Surface?,
    render: @escaping @Sendable (Surface, Int) throws -> [CGImage] = { source, size in
      try Renderer.channelThumbnails(source, maximumSize: size).map {
        try RasterIO.displayImage($0)
      }
    }
  ) async {
    self.request = request
    images = []
    error = nil
    guard request.maximumSize > 0, let source else { return }
    let worker = Task.detached(priority: .utility) { try render(source, request.maximumSize) }
    do {
      let result = try await withTaskCancellationHandler(
        operation: { try await worker.value }, onCancel: { worker.cancel() })
      guard !Task.isCancelled, self.request == request else { return }
      images = result
    } catch is CancellationError {
    } catch {
      guard !Task.isCancelled, self.request == request else { return }
      self.error = error.localizedDescription
    }
  }
}

struct ChannelsPanel: View {
  @Bindable var store: EditorStore
  @Environment(\.displayScale) private var displayScale
  @State private var thumbnails = ChannelThumbnailCache()
  private var size: ChannelThumbnailSize {
    store.workspaceLibrary.channelPanelOptions.thumbnailSize
  }
  private var request: ChannelThumbnailRequest {
    ChannelThumbnailRequest(
      owner: store.identity, generation: store.layerPanelGeneration,
      composite: store.channelCompositeRevision,
      maximumSize: size == .none ? 0 : min(512, max(1, Int(ceil(size.edge * displayScale)))))
  }
  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 0) {
          ForEach(RGBChannelPreview.allCases, id: \.self) { channel in
            row(channel)
          }
        }
      }
      if let error = thumbnails.error {
        Text("Channel thumbnails unavailable: \(error)").font(.system(size: 10))
          .foregroundStyle(.secondary).padding(8)
      }
      Text(
        "RGB8 component Fill available · Other component tools, alpha and spot editing are in development."
      )
      .font(.system(size: 10)).foregroundStyle(.secondary).padding(8)
    }
    .task(id: request) {
      await thumbnails.update(request, source: store.surface)
    }
  }

  private func row(_ channel: RGBChannelPreview) -> some View {
    let visible = store.channelView.isVisible(channel)
    let selected = store.componentTarget == .composite || store.componentTarget == channel
    return HStack(spacing: 0) {
      Button {
        store.setChannelVisibility(channel, visible: !visible)
      } label: {
        Image(systemName: "eye").font(.system(size: 11)).opacity(visible ? 1 : 0)
          .frame(width: 26, height: size.rowHeight).contentShape(Rectangle())
      }.buttonStyle(.plain)
        .accessibilityLabel("Visibility of \(channel.title) channel")
        .accessibilityValue(visible ? "Visible" : "Hidden")
        .accessibilityIdentifier("channels.visibility.\(channel.rawValue)")
        .help("Show or hide \(channel.title) channel")
        .disabled(!store.canChangeChannelVisibility)
      Rectangle().fill(StudioTheme.line).frame(width: 1)
      Button {
        do { try store.selectEditingChannel(channel) } catch {
          store.error = error.localizedDescription
        }
      } label: {
        HStack(spacing: 0) {
          if size != .none {
            ZStack {
              Checkerboard()
              if thumbnails.request == request, thumbnails.images.indices.contains(channel.rawValue)
              {
                Image(decorative: thumbnails.images[channel.rawValue], scale: 1)
                  .resizable().scaledToFit()
              }
            }.frame(width: size.edge, height: size.edge).border(Color.black.opacity(0.7))
              .padding(.leading, 4).padding(.trailing, 5).accessibilityHidden(true)
          }
          Text(channel.title).font(.system(size: 11)).padding(.leading, size == .none ? 7 : 0)
          Spacer(minLength: 5)
        }.frame(maxWidth: .infinity).frame(height: size.rowHeight)
          .contentShape(Rectangle())
      }.buttonStyle(.plain).help("Select \(channel.title) editing target")
        .accessibilityLabel("Select \(channel.title) channel")
        .accessibilityValue(selected ? "Selected editing target" : "")
        .accessibilityIdentifier("channels.preview.\(channel.rawValue)")
        .disabled(
          !store.canSelectComponentTarget || (channel != .composite && store.document.depth != .u8))
    }.background(selected ? StudioTheme.selected : StudioTheme.chrome)
      .overlay(alignment: .bottom) { Rectangle().fill(StudioTheme.line).frame(height: 1) }
  }
}
