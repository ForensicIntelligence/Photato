import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

struct ImageExportSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: ImageExportDraft
  var body: some View {
    VStack(spacing: 0) {
      HStack { Text(draft.preferences ? "Export Preferences" : "Export As").font(.title2.bold()); Spacer(); if draft.busy || store.imageExportID != nil { ProgressView().controlSize(.small) } }.padding()
      Divider()
      HStack(spacing: 0) {
        if !draft.preferences {
          assetList.frame(width: 210)
          Divider()
          VStack {
            if let image = draft.preview { Image(nsImage: image).resizable().interpolation(.none).scaledToFit().padding(24) }
            else { ContentUnavailableView(draft.busy ? "Preparing preview" : "Select assets to export", systemImage: "photo") }
            if let first = draft.previewFiles.first { Text("\(first.width) × \(first.height) px · \(ByteCountFormatter.string(fromByteCount: Int64(first.data.count), countStyle: .file))").font(.caption).foregroundStyle(.secondary) }
          }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .underPageBackgroundColor))
          Divider()
        }
        ScrollView {
          Form {
            Section("File Settings") {
              Picker("Format", selection: $draft.settings.format) { Text("PNG").tag(ImageExportSettings.Format.png); Text("JPG").tag(ImageExportSettings.Format.jpeg); Text("GIF").tag(ImageExportSettings.Format.gif) }
              if draft.settings.format == .jpeg {
                HStack { Text("Quality"); Slider(value: Binding(get: { Double(draft.settings.quality) }, set: { draft.settings.quality = Int($0) }), in: 0...100, step: 1); Text("\(draft.settings.quality)%").monospacedDigit().frame(width: 42) }
              } else { Toggle("Transparency", isOn: $draft.settings.transparency) }
            }
            if !draft.preferences {
              Section("Image Size") {
                dimension("Width", \.width); dimension("Height", \.height)
                Picker("Resample", selection: $draft.settings.resampling) { ForEach(Resampling.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Toggle("Trim Transparent Pixels", isOn: $draft.settings.trim)
              }
              Section("Canvas Size") {
                dimension("Width", \.canvasWidth); dimension("Height", \.canvasHeight)
                Button("Reset Canvas") { draft.settings.canvasWidth = nil; draft.settings.canvasHeight = nil }
              }
              Section("Scale All") {
                ForEach(draft.settings.scales.indices, id: \.self) { index in
                  HStack {
                    TextField("Scale", value: $draft.settings.scales[index].factor, format: .number).frame(width: 58); Text("×")
                    TextField("Suffix", text: $draft.settings.scales[index].suffix)
                    Button { draft.settings.scales.remove(at: index) } label: { Image(systemName: "minus.circle") }.disabled(draft.settings.scales.count == 1)
                  }
                }
                Button("Add Scale") { let n = draft.settings.scales.count + 1; draft.settings.scales.append(.init(Double(n), suffix: "@\(n)x")) }.disabled(draft.settings.scales.count >= 16)
              }
            }
            Section("Metadata") {
              Picker("Include", selection: $draft.settings.metadata) { Text("None").tag(ImageExportSettings.Metadata.none); Text("Copyright and Author").tag(ImageExportSettings.Metadata.copyright) }.disabled(draft.settings.format == .gif)
            }
            Section("Color Space") {
              Toggle("Convert to sRGB", isOn: $draft.settings.convertToSRGB).disabled(draft.settings.format == .gif)
              Toggle("Embed Color Profile", isOn: $draft.settings.embedProfile).disabled(draft.settings.format == .gif)
            }
            if draft.preferences { Section("Quick Export Location") { Text("Ask where to export each time").foregroundStyle(.secondary) } }
          }.formStyle(.grouped).padding(4)
        }.frame(width: draft.preferences ? 420 : 310)
      }
      Divider()
      HStack {
        if let error = draft.error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(3).textSelection(.enabled) }
        Spacer()
        Button("Cancel") { store.cancelImageExport() }.keyboardShortcut(.cancelAction)
        Button(draft.preferences ? "Done" : draft.previewFiles.count > 1 ? "Export All…" : "Export…") { store.finishNativeImageExport(draft) }
          .keyboardShortcut(.defaultAction).disabled(store.imageExportID != nil || (!draft.preferences && (draft.busy || draft.previewFiles.isEmpty || draft.error != nil)))
      }.padding()
    }.frame(width: draft.preferences ? 450 : 1000, height: draft.preferences ? 530 : 660)
      .task { draft.refresh() }
      .onChange(of: draft.settings.format) { _, format in if format == .gif { draft.settings.embedProfile = false; draft.settings.metadata = .none; draft.settings.convertToSRGB = true } }
      .onChange(of: draft.settings) { _, _ in draft.refresh() }
      .onDisappear { draft.cancel() }
  }
  var assetList: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker("Export", selection: $draft.settings.target) { Text("Document").tag(ImageExportSettings.Target.document); Text("Layers").tag(ImageExportSettings.Target.layers); Text("Artboards").tag(ImageExportSettings.Target.artboards) }.labelsHidden()
      ScrollView {
        if draft.settings.target == .document { Text(draft.original.name).font(.headline).frame(maxWidth: .infinity, alignment: .leading) }
        else {
          ForEach(draft.original.layers.filter { draft.settings.target == .layers || $0.artboardBounds != nil }) { layer in
            Toggle(layer.name, isOn: Binding(get: { draft.settings.ids.contains(layer.id) }, set: { enabled in if enabled { draft.settings.ids.append(layer.id) } else { draft.settings.ids.removeAll { $0 == layer.id } } }))
          }
        }
        ForEach(draft.previewFiles, id: \.name) { file in VStack(alignment: .leading) { Text(file.name).lineLimit(2); Text("\(file.width) × \(file.height) · \(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))").font(.caption).foregroundStyle(.secondary) }.padding(.top, 8) }
      }
    }.padding(14).onChange(of: draft.settings.target) { _, target in
      if target == .document { draft.settings.ids = [] }
      else if target == .artboards { draft.settings.ids = draft.original.artboards.map(\.id) }
      else { draft.settings.ids = draft.original.layers.filter { store.selectedLayerIDs.contains($0.id) }.map(\.id) }
    }
  }
  func dimension(_ title: String, _ path: WritableKeyPath<ImageExportSettings, Int?>) -> some View {
    TextField(title + " (Auto)", value: Binding(get: { draft.settings[keyPath: path] ?? 0 }, set: { draft.settings[keyPath: path] = $0 == 0 ? nil : $0 }), format: .number)
  }
}
@MainActor extension AppDelegate {
  @objc func exportLayerAssets() { store?.beginImageExport(layers: true) }
  @objc func quickExportAssets() { store?.quickExportImages() }
  @objc func quickExportLayerAssets() { store?.quickExportImages(layers: true) }
  @objc func exportPreferences() { store?.beginImageExport(preferences: true) }
}
