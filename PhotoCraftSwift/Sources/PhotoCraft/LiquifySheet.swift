import AppKit
import PhotoCraftCore
import SwiftUI
import UniformTypeIdentifiers

struct LiquifySheet: View {
  @Bindable var store: EditorStore
  @State private var model = LiquifyWorkspace()
  @State private var importing = false
  @State private var exporting = false
  @State private var exportFile: LUTDocument?
  @State private var reconstructAmount = 100.0
  init(store: EditorStore, workspace: LiquifyWorkspace? = nil) {
    self.store = store; _model = State(initialValue:workspace ?? LiquifyWorkspace())
  }
  private func slider(_ title: String,_ value: Binding<Double>,_ range: ClosedRange<Double>) -> some View {
    VStack(alignment:.leading,spacing:3) {
      HStack { Text(title); Spacer(); TextField(title,value:value,format:.number.precision(.fractionLength(0))).frame(width:60).textFieldStyle(.roundedBorder) }
      Slider(value:value,in:range,step:1).accessibilityLabel(title)
    }
  }
  var body: some View {
    VStack(spacing:0) {
      HStack { Text("Liquify").font(.headline); Spacer(); if model.loading || model.rendering || model.detecting { ProgressView().controlSize(.small) }; Text("\(model.settings.width) × \(model.settings.height)").foregroundStyle(.secondary) }.padding(12)
      Divider()
      HStack(spacing:0) {
        toolbar.frame(width:48)
        LiquifyCanvas(model:model).frame(minWidth:480,minHeight:460).clipped()
        Divider()
        ScrollView { controls.padding(14) }.frame(width:292).disabled(!model.ready)
      }
      Divider()
      if let error = model.error { HStack { Text(error).foregroundStyle(.red).font(.caption); Button("Dismiss") { model.error = nil } }.padding(6) }
      if let notice = model.notice { Text(notice).font(.caption).padding(6) }
      HStack {
        Toggle("Preview",isOn:$model.preview)
        Button("−") { model.zoom = max(0.125,model.zoom/1.25) }
        Text("\(Int(model.zoom*100))% fit").monospacedDigit().frame(width:70)
        Button("+") { model.zoom = min(16,model.zoom*1.25) }
        Button("Fit") { model.zoom = 1; model.pan = .zero }
        Spacer()
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty)
        Button("Cancel") { model.close(); store.cancelFilter() }.keyboardShortcut(.cancelAction)
        Button("OK") {
          model.end(); guard model.error == nil else { return }
          store.filterDraft?.filter.liquify = model.settings; model.close(); store.commitFilter()
        }.keyboardShortcut(.defaultAction).disabled(!model.ready || model.error != nil)
      }.padding(12)
    }.background(Color(nsColor:.windowBackgroundColor)).frame(width:min(1180,(NSScreen.main?.visibleFrame.width ?? 1280)-80),height:min(780,(NSScreen.main?.visibleFrame.height ?? 900)-100))
    .task {
      guard let draft = store.filterDraft else { return }
      model.onChange = { store.filterDraft?.filter.liquify = $0 }
      await model.prepare(document:store.document,draft:draft)
    }
    .onDisappear { model.close() }
    .fileImporter(isPresented:$importing,allowedContentTypes:[UTType(filenameExtension:LiquifyMeshFile.fileExtension) ?? .data]) { result in
      do {
        let url = try result.get(), access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom:url); defer { try? file.close() }
        model.end(); model.change(try LiquifyMeshFile.decode(file.read(upToCount:LiquifyMeshFile.maximumBytes+1) ?? Data()))
      } catch { model.error = error.localizedDescription }
    }
    .fileExporter(isPresented:$exporting,document:exportFile,contentType:UTType(filenameExtension:LiquifyMeshFile.fileExtension) ?? .data,defaultFilename:"Liquify.\(LiquifyMeshFile.fileExtension)") { result in
      if case .failure(let error) = result { model.error = error.localizedDescription }
    }
  }
  private var toolbar: some View {
    VStack(spacing:5) {
      ForEach(Array(zip([LiquifyTool.forwardWarp,.reconstruct,.smooth,.twirlCw,.pucker,.bloat,.pushLeft,.freeze,.thaw,.lassoMask],["W","R","E","C","S","B","O","F","D","L"])),id:\.0) { tool,key in
        Button(key) { model.end(); model.tool = tool; model.panTool = false }
          .buttonStyle(.bordered).tint(model.tool == tool && !model.panTool ? .accentColor : .gray)
          .help("\(tool.title) (\(key))").accessibilityLabel(tool.title)
      }
      Divider()
      Button { model.panTool.toggle() } label: { Image(systemName:"hand.draw") }.help("Hand (H), or hold Space to pan")
      Spacer()
    }.padding(.vertical,10).disabled(!model.ready)
  }
  private var controls: some View {
    VStack(alignment:.leading,spacing:14) {
      DisclosureGroup("Brush Tool Options") {
        VStack(spacing:8) {
          slider("Size",$model.size,1...15000); slider("Density",$model.density,0...100)
          slider("Pressure",$model.pressure,0...100); slider("Rate",$model.rate,0...100)
        }.padding(.top,8)
      }.disclosureGroupStyle(LiquifyDisclosure())
      Divider()
      Text("Face Controls").font(.headline)
      Button(model.detecting ? "Detecting…" : "Detect Faces on Device") { model.detect() }
      if !model.settings.faces.isEmpty {
        Picker("Face",selection:$model.selectedFace) {
          ForEach(model.settings.faces.indices,id:\.self) { Text("Face \($0+1)").tag($0) }
        }
        ForEach([("Eyes",Array(LiquifyFaceParameter.allCases.prefix(9))), ("Nose",Array(LiquifyFaceParameter.allCases[9...10])), ("Mouth",Array(LiquifyFaceParameter.allCases[11...15])), ("Face Shape",Array(LiquifyFaceParameter.allCases.suffix(4)))],id:\.0) { group in
          DisclosureGroup(group.0) {
            ForEach(group.1,id:\.self) { key in
              VStack(alignment:.leading,spacing:2) {
                HStack { Text(key.title); Spacer(); Text("\(Int(model.faceValue(key)))").monospacedDigit() }
                Slider(value:Binding(get:{ model.faceValue(key) },set:{ model.setFace(key,value:$0) }),in:-100...100,step:1,onEditingChanged:model.faceSlider).accessibilityLabel(key.title)
              }
            }
          }
        }
      }
      Divider()
      Text("Mask Options").font(.headline)
      HStack { Button("None") { model.global(.thawAll) }; Button("All") { model.global(.freezeAll) }; Button("Invert") { model.global(.invertFreeze) } }
      Text("Frozen areas are protected from deformation.").font(.caption).foregroundStyle(.secondary)
      Divider()
      Text("View Options").font(.headline)
      Toggle("Show Mesh",isOn:$model.showMesh); Toggle("Show Mask",isOn:$model.showMask)
      Toggle("Show Original Backdrop",isOn:$model.showBackdrop)
      if model.showBackdrop { Slider(value:$model.backdropOpacity,in:0...1).accessibilityLabel("Backdrop Opacity") }
      HStack { Button("Load Mesh…") { importing = true }; Button("Save Mesh…") {
        do { model.end(); exportFile = LUTDocument(data:try LiquifyMeshFile.encode(model.settings)); exporting = true }
        catch { model.error = error.localizedDescription }
      } }
      Divider()
      Text("Reconstruct Options").font(.headline)
      slider("Amount",$reconstructAmount,0...100)
      HStack { Button("Reconstruct") { model.global(.reconstructAll,amount:reconstructAmount) }; Button("Restore All") { model.restore() } }
      if store.filterDraft?.filterID != nil {
        Divider()
        Picker("Blending Mode",selection:Binding(get:{ store.filterDraft?.blendMode ?? .normal },set:{ store.filterDraft?.blendMode = $0 })) {
          ForEach(BlendMode.allCases,id:\.self) { Text($0.rawValue).tag($0) }
        }
        Slider(value:Binding(get:{ Double(store.filterDraft?.opacity ?? 1) },set:{ store.filterDraft?.opacity = Float($0) }),in:0...1).accessibilityLabel("Smart Filter Opacity")
        Text("Blending and the shared filter mask apply on commit.").font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
private struct LiquifyDisclosure: DisclosureGroupStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment:.leading) { configuration.label.font(.headline); configuration.content }
  }
}
