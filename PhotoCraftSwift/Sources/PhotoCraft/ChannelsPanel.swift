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
  @State private var eyeTracking = ChannelEyeTracking()
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
          if store.document.inkMode != nil {
            InkChannelRows(store: store, images: thumbnails.request == request ? thumbnails.images : [], size: size,eyeTracking:eyeTracking)
          } else if store.document.colorMode.isRestricted {
            HStack(spacing: 10) {
              Image(systemName: "eye")
              if thumbnails.request == request, let image = thumbnails.images.first, size != .none {
                Image(decorative: image, scale: 1).resizable().scaledToFit().frame(width: size.edge, height: size.edge)
              }
              Text(store.document.colorMode == .indexed ? "Index" : "Bitmap"); Spacer()
            }.font(.system(size: 11)).padding(8).background(Color.accentColor.opacity(0.18))
              .accessibilityLabel(store.document.colorMode == .indexed ? "Index channel" : "Bitmap channel")
          } else if store.usesModeChannels {
            ModeChannelRows(store: store, images: thumbnails.request == request ? thumbnails.images : [], size: size,eyeTracking:eyeTracking)
          } else if !store.document.isChannelOnly {
            ForEach(RGBChannelPreview.allCases, id: \.self) { channel in row(channel) }
          }
          ForEach(store.temporaryMaskChannels,id: \.self) { target in TemporaryMaskChannelRow(store:store,target:target,eyeTracking:eyeTracking) }
          ForEach(store.document.alphaChannels ?? []) { channel in AuxiliaryChannelRow(store:store,channel:channel,eyeTracking:eyeTracking) }
          if let channel = store.document.quickMask { AuxiliaryChannelRow(store:store,channel:channel,quick:true,eyeTracking:eyeTracking) }
        }
      }
      if let error = thumbnails.error {
        Text("Channel thumbnails unavailable: \(error)").font(.system(size: 10))
          .foregroundStyle(.secondary).padding(8)
      }
      HStack {
        Button { if store.document.inkMode != nil && store.editingChannel == nil { store.loadSelectedInkChannel() } else { store.beginChannelDialog(.load) } } label: { Image(systemName:"circle.dashed") }.help("Load channel as selection").disabled((store.document.alphaChannels ?? []).isEmpty && store.document.inkMode == nil)
        Button { store.beginChannelDialog(.save) } label: { Image(systemName:"square.and.arrow.down") }.help("Save selection as channel")
        Spacer()
        Button { if store.document.colorMode == .multichannel {store.beginInkChannelOptions()}else if NSApp.currentEvent?.modifierFlags.contains(.command)==true {store.beginChannelDialog(.newSpot)}else{store.newAlphaChannel()} } label: { Image(systemName:"plus.square") }.help("New channel (Command-click for New Spot Channel)")
        Button { if let id = store.alphaEditingID { store.perform(.channel(.delete(id))) } else if store.effectiveInkTargets.count == 1, case .plate(let id) = store.effectiveInkTargets.first { store.performInkChannel(.delete(id)) } } label: { Image(systemName:"trash") }.help("Delete channel").disabled(store.alphaEditingID == nil && !(store.document.colorMode == .multichannel && store.effectiveInkTargets.count == 1 && store.document.inkChannelTargets.count > 1))
      }.buttonStyle(.plain).padding(8).disabled(!store.canEditChannels)
    }
    .onDisappear {eyeTracking.cancel()}
    .task(id: request) {
      let document = store.document
      await thumbnails.update(request, source: store.surface) { surface, size in
        try (document.inkMode != nil ? InkChannelPresentation.thumbnails(document, maximumSize: size) : document.hasNativeModeStorage || document.depth != .u8 ? ModeChannelPresentation.thumbnails(document, maximumSize: size) : Renderer.channelThumbnails(surface, maximumSize: size)).enumerated().map {
          index, pixels in
          try index == 0 && document.inkMode == nil
            ? ColorManagement.displayImage(pixels, in: document) : RasterIO.displayImage(pixels)
        }
      }
    }
  }

  private func row(_ channel: RGBChannelPreview) -> some View {
    let selected = store.isColorComponentSelected(channel == .composite ? nil : channel.rawValue - 1)
    return HStack(spacing: 0) {
      ChannelEyeControl(store:store,channel:.rgb(channel),tracking:eyeTracking,label:"Visibility of \(channel.title) channel",identifier:"channels.visibility.\(channel.rawValue)",height:size.rowHeight)
        .frame(width:26,height:size.rowHeight)
      Rectangle().fill(StudioTheme.line).frame(width: 1)
      Button {
        do { try store.selectColorComponentRow(channel == .composite ? nil : channel.rawValue - 1, modifiers: NSApp.currentEvent?.modifierFlags ?? []) } catch {
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
      }.buttonStyle(.plain).help("Select \(channel.title) editing target; Shift-click to select multiple components")
        .accessibilityLabel("Select \(channel.title) channel")
        .accessibilityValue(selected ? "Selected editing target" : "")
        .accessibilityIdentifier("channels.preview.\(channel.rawValue)")
        .disabled(
          !store.canSelectComponentTarget || (channel != .composite && store.document.depth != .u8))
    }.background(selected ? StudioTheme.selected : StudioTheme.chrome)
      .overlay(alignment: .bottom) { Rectangle().fill(StudioTheme.line).frame(height: 1) }
  }
}

struct AuxiliaryChannelRow: View {
  @Bindable var store: EditorStore
  let channel: AlphaChannel
  var quick = false
  let eyeTracking:ChannelEyeTracking
  @State private var thumbnail: CGImage?
  @State private var renaming = false
  @State private var name = ""
  private var target: ChannelPlaneTarget { quick ? .quickMask:.alpha(channel.id) }
  var body: some View {
    HStack(spacing:6) {
      ChannelEyeControl(store:store,channel:quick ? .quickMask:.alpha(channel.id),tracking:eyeTracking,
        label:quick ? "Quick Mask visibility":"Visibility of \(channel.name) channel",
        identifier:quick ? "channels.visibility.quickMask":"channels.visibility.\(channel.id.uuidString)",height:40).frame(width:26,height:40)
      Button {
        if quick { try? store.selectQuickMaskChannel() }
        else { store.channelThumbnail(channel.id,modifiers:NSApp.currentEvent?.modifierFlags ?? []) }
      } label: {
        HStack {
          if store.workspaceLibrary.channelPanelOptions.thumbnailSize != .none {
            Group { if let thumbnail { Image(decorative:thumbnail,scale:1).resizable().scaledToFit() } else { Color.black } }
              .frame(width:32,height:32).border(.black)
          }
          if channel.spot != nil {Image(systemName:"drop.fill").help("Spot ink channel")}
          Text(channel.name).lineLimit(1); Spacer()
        }.contentShape(Rectangle())
      }.accessibilityLabel("Select \(channel.name) channel")
    }.buttonStyle(.plain).font(.system(size:11)).padding(.vertical,4).padding(.trailing,8)
      .background(store.editingChannel == target ? StudioTheme.selected:StudioTheme.chrome)
      .disabled(!store.canEditChannels)
      .contextMenu {
        Button("Load Selection") { store.perform(.channel(.load(target,.replace,false))) }
        Button(channel.spot == nil ? "Channel Options…":"Spot Channel Options…") { try? store.selectAlphaChannel(quick ? nil:channel.id); store.beginChannelDialog(quick ? .quickOptions:.options) }
        if !quick {
          Button("Rename…") { name = channel.name; renaming = true }
          Button("Duplicate Channel") { store.perform(.channel(.duplicate(channel.id,nil))) }
          Button("Move Up") { move(-1) }.disabled(index == 0)
          Button("Move Down") { move(1) }.disabled(index >= (store.document.alphaChannels?.count ?? 0)-1)
          Button("Delete Channel") { store.perform(.channel(.delete(channel.id))) }
        }
        Button("Invert") { store.perform(.channel(.invert(target))) }.disabled(quick && !store.isQuickMaskVisible)
      }
      .alert("Rename Channel",isPresented:$renaming) {
        TextField("Name",text:$name)
        Button("Cancel",role:.cancel) {}
        Button("OK") { store.perform(.channel(.rename(channel.id,name))) }
      }
      .task(id:store.canvasPresentationRevision) {
        let source = channel.pixels
        thumbnail = try? await Task.detached(priority:.utility) { try RasterIO.displayImage(Renderer.channelThumbnails(source,maximumSize:64)[0]) }.value
      }
  }
  private var index: Int { store.document.alphaChannels?.firstIndex(where:{$0.id == channel.id}) ?? 0 }
  private func move(_ delta: Int) { store.perform(.channel(.move(channel.id,index+delta))) }
}
