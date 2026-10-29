import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

struct DocumentModeSheet: View {
  @Bindable var store: EditorStore
  @Bindable var model: DocumentModeWorkspace
  var body: some View {
    VStack(spacing: 14) {
      HStack { Text("Convert Color Mode").font(.headline); Spacer(); if model.rendering || model.committing { ProgressView().controlSize(.small) } }
      HStack(alignment: .top, spacing: 18) {
        GeometryReader { area in
          ZStack {
            Color(white: 0.12)
            if let image = model.preview ? model.image : model.originalImage {
              Image(decorative: image, scale: 1).resizable().scaledToFit().padding(12)
                .frame(width: area.size.width, height: area.size.height)
            }
          }.clipped().accessibilityLabel("Color mode preview")
        }
        VStack(alignment: .leading, spacing: 12) {
          Picker("Mode", selection: Binding(get: { model.request.conversion.mode }, set: { mode in
            model.chooseMode(mode)
          })) { ForEach(DocumentColorMode.componentModes, id: \.self) { Text($0.title).tag($0) } }
          Picker("Depth", selection: Binding(get: { model.request.conversion.depth }, set: { depth in
            model.chooseDepth(depth)
          })) { ForEach(model.request.conversion.mode.depths, id: \.self) { Text($0.rawValue).tag($0) } }
          Picker("Intent", selection: Binding(get: { model.request.conversion.intent }, set: { intent in model.update { $0.conversion.intent = intent } })) {
            Text("Perceptual").tag(ModeRenderingIntent.perceptual)
            Text("Relative Colorimetric").tag(ModeRenderingIntent.relativeColorimetric)
            Text("Saturation").tag(ModeRenderingIntent.saturation)
            Text("Absolute Colorimetric").tag(ModeRenderingIntent.absoluteColorimetric)
          }
          Text(model.request.conversion.profile.flatMap { CGColorSpace(iccData: $0 as CFData) }
            .flatMap { NSColorSpace(cgColorSpace: $0)?.localizedName } ?? "Platform standard ICC profile")
            .font(.caption).foregroundStyle(.secondary)
          HStack {
            Button("Load ICC…") { loadProfile() }
            Button("Use Working Profile") { model.useWorkingProfile() }
          }
          Divider()
          Toggle("Merge visible layers", isOn: Binding(get: { model.request.mergeVisible }, set: { value in model.update { $0.mergeVisible = value } }))
          Text("Merging replaces the layer stack with the visible composite and discards hidden layers.").font(.caption).foregroundStyle(.secondary)
          if model.source.depth == .f32 && model.request.conversion.depth != .f32 {
            Toggle("Clip HDR values", isOn: Binding(get: { model.request.clipHDR }, set: { value in model.update { $0.clipHDR = value } }))
            Text("Values outside the target range are clipped. Cancel and apply HDR Toning first to control their appearance.").font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
        }.frame(width: 295).disabled(model.committing)
      }
      if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      HStack {
        Toggle("Preview", isOn: $model.preview)
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty || model.committing).keyboardShortcut("z", modifiers: .command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty || model.committing).keyboardShortcut("z", modifiers: [.command, .shift])
        Spacer()
        Button("Cancel") { store.cancelDocumentMode() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitDocumentMode() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }.controlSize(.small)
    }.padding(16).frame(width: 850, height: 560)
      .onDisappear { model.close(); if store.documentModeWorkspace === model { store.documentModeWorkspace = nil } }
  }
  private func loadProfile() {
    let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [UTType(filenameExtension: "icc"), UTType(filenameExtension: "icm")].compactMap { $0 }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size > 0, size <= ICCProfile.maximumBytes else { throw CraftError.invalid("ICC profile exceeds the supported size.") }
      try model.loadProfile(Data(contentsOf: url))
    } catch { model.error = error.localizedDescription }
  }
}
