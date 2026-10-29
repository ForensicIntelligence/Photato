import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

struct ColorProfileChoice: Identifiable {
  let id: String
  let name: String
  let data: Data
  static func available(mode: DocumentColorMode?, depth: PixelDepth) -> [Self] {
    var result: [Self] = []
    for model in [NSColorSpace.Model.rgb, .cmyk, .gray] {
      for space in NSColorSpace.availableColorSpaces(with: model) {
        guard let original = space.iccProfileData, let kind = try? ProofSettings.mode(of: original),
          mode == nil || mode == kind, let data = try? NativeModeProfile.atDepth(original, mode: kind, depth: depth) else { continue }
        let name = space.localizedName ?? kind.title
        if !result.contains(where: { $0.data == data }) { result.append(.init(id: name + "-\(result.count)", name: name, data: data)) }
      }
    }
    return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}
struct ColorProfileSheet: View {
  @Bindable var store: EditorStore
  @Bindable var model: ColorProfileWorkspace
  var body: some View {
    VStack(spacing: 14) {
      HStack { Text(model.title).font(.headline); Spacer(); if model.rendering || model.committing { ProgressView().controlSize(.small) } }
      Text("Source: \(ColorProfileInput.name(model.source))").frame(maxWidth: .infinity, alignment: .leading)
      HStack(alignment: .top, spacing: 18) {
        GeometryReader { area in
          ZStack { Color(white: 0.12)
            if let image = model.preview ? model.image : model.originalImage {
              Image(decorative: image, scale: 1).resizable().scaledToFit().padding(12).frame(width: area.size.width, height: area.size.height)
            }
          }.clipped().accessibilityLabel("Color profile preview")
        }
        VStack(alignment: .leading, spacing: 12) {
          let name = CGColorSpace(iccData: model.request.profile as CFData).flatMap { NSColorSpace(cgColorSpace: $0)?.localizedName } ?? "Custom ICC profile"
          Text("Profile: \(name)").fixedSize(horizontal: false, vertical: true)
          Menu("Choose Profile") {
            ForEach(ColorProfileChoice.available(mode: model.request.operation == .assign ? model.source.colorMode : nil, depth: model.source.depth)) { choice in
              Button(choice.name) { do { try model.loadProfile(choice.data) } catch { model.error = error.localizedDescription } }
            }
          }
          Button("Load ICC Profile…") { loadProfile() }
          if model.source.variables?.images.isEmpty == false {
            Text("Replacement images in your data sets are converted to the new working profile so future placements keep their appearance.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          }
          Button("Use Working Profile") {
            do { try model.loadProfile(model.workingSettings.profile(model.source.colorMode, depth: model.source.depth)) }
            catch { model.error = error.localizedDescription }
          }
          if model.request.operation == .assign {
            Toggle("Don’t Color Manage This Document", isOn: Binding(get: { model.request.removeProfile }, set: { value in
              do {
                let profile = try model.workingSettings.profile(model.source.colorMode, depth: model.source.depth)
                model.update { $0.removeProfile = value; if value { $0.profile = profile } }
              } catch { model.error = error.localizedDescription }
            }))
            Text("Assignment preserves numerical samples. The preview may change. An untagged document uses the working-space interpretation captured when this dialog opened and saves without an embedded profile.").font(.caption).foregroundStyle(.secondary)
          } else {
            Text("Engine: Apple ColorSync").font(.caption)
            Picker("Intent", selection: Binding(get: { model.request.intent }, set: { value in model.update { $0.intent = value } })) {
              Text("Perceptual").tag(ModeRenderingIntent.perceptual)
              Text("Relative Colorimetric").tag(ModeRenderingIntent.relativeColorimetric)
              Text("Saturation").tag(ModeRenderingIntent.saturation)
              Text("Absolute Colorimetric").tag(ModeRenderingIntent.absoluteColorimetric)
            }
            Toggle("Use Black Point Compensation", isOn: Binding(get: { model.request.blackPointCompensation }, set: { value in model.update { $0.blackPointCompensation = value } }))
            Toggle("Flatten Image to Preserve Appearance", isOn: Binding(get: { model.request.mergeVisible }, set: { value in model.update { $0.mergeVisible = value } }))
            Text("Flattening replaces the stack with the visible composite and removes hidden layers. Cancel to keep the original.").font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
        }.frame(width: 310).disabled(model.committing)
      }
      if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      HStack {
        Toggle("Preview", isOn: $model.preview)
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty || model.committing).keyboardShortcut("z", modifiers: .command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty || model.committing).keyboardShortcut("z", modifiers: [.command, .shift])
        Spacer()
        Button("Cancel") { store.cancelColorProfile() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitColorProfile() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }.controlSize(.small)
    }.padding(16).frame(width: 850, height: 530)
      .onDisappear { model.close(); if store.colorProfileWorkspace === model { store.colorProfileWorkspace = nil } }
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
