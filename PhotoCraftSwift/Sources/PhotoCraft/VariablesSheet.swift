import AppKit
import SwiftUI
import PhotoCraftCore

struct VariablesSheet: View {
  @ObservedObject var model: VariableEditorModel
  var window: () -> NSWindow?
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Variables", selection: $model.tab) { Text("Define").tag(0); Text("Data Sets").tag(1) }.pickerStyle(.segmented).frame(width: 280)
      HStack(alignment: .top, spacing: 20) {
        ScrollView {
          VStack(alignment: .leading, spacing: 14) { if model.tab == 0 { definitions } else { dataSets } }
          .frame(maxWidth: .infinity, alignment: .leading).padding(4)
        }.frame(width: 460)
        VStack(alignment: .leading, spacing: 8) {
          Toggle("Preview", isOn: $model.previewEnabled)
          ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let image = model.preview { Image(nsImage: image).resizable().scaledToFit().padding(8) }
            else { Text(model.previewEnabled ? "Preview unavailable" : "Preview off").foregroundStyle(.secondary) }
          }.frame(width: 270, height: 290).clipShape(RoundedRectangle(cornerRadius: 8))
          Text("\(model.settings.definitions.count) bindings · \(model.settings.dataSets.count) data sets")
            .font(.caption).foregroundStyle(.secondary)
          Text("Changes stay in this dialog until you choose OK or Apply.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }.disabled(model.busy)
      HStack {
        Button("Import…") { model.chooseDataFile(window: window()) }.disabled(model.busy || model.settings.definitions.isEmpty)
        if model.busy { ProgressView().controlSize(.small); Text("Importing…").font(.caption) }
        Spacer()
        if let error = model.error { Text(error).foregroundStyle(.red).font(.caption).lineLimit(3).frame(maxWidth: 540, alignment: .trailing) }
      }
    }.padding(12).frame(width: 780, height: 465)
      .onAppear { model.refreshPreview() }
      .onChange(of: model.settings) { _, _ in model.refreshPreview() }
      .onChange(of: model.rowID) { _, _ in model.refreshPreview() }
      .onChange(of: model.tab) { _, _ in model.refreshPreview() }
      .onChange(of: model.previewEnabled) { _, _ in model.refreshPreview() }
      .onDisappear { model.cancel() }
  }
  private var definitions: some View {
    VStack(alignment: .leading, spacing: 14) {
      Picker("Layer:", selection: $model.layerID) { ForEach(model.source.layers) { layer in Text(layer.name).tag(Optional(layer.id)) } }
      ForEach(VariableKind.allCases, id: \.self) { kind in
        VStack(alignment: .leading, spacing: 8) {
          Toggle(title(kind), isOn: Binding(get: { model.binding(kind) != nil }, set: { model.setEnabled(kind, $0) })).disabled(!model.supports(kind))
          if let definition = model.binding(kind) {
            HStack {
              TextField("Variable name", text: Binding(get: { model.binding(kind)?.name ?? "" }, set: { model.rename(kind, $0) }))
              Menu("Link") {
                ForEach(model.settings.variableNames.filter { name in model.settings.definitions.contains { $0.name == name && $0.kind == kind } }, id: \.self) { name in
                  Button(name) { model.rename(kind, name) }
                }
              }.frame(width: 65)
            }
            if kind == .pixelReplacement { pixelOptions(definition.pixelOptions ?? .init()) }
          }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
      }
      Text("Use the same variable name on multiple layers to link their values. Names start with a letter, underscore or colon.").font(.caption).foregroundStyle(.secondary)
    }
  }
  private func pixelOptions(_ options: VariablePixelOptions) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("Method:", selection: Binding(get: { options.method }, set: { var next = options; next.method = $0; model.setPixelOptions(next) })) {
        Text("Fit").tag(VariablePixelMethod.fit); Text("Fill").tag(VariablePixelMethod.fill)
        Text("As Is").tag(VariablePixelMethod.asIs); Text("Conform").tag(VariablePixelMethod.conform)
      }
      Picker("Alignment:", selection: Binding(get: { options.alignment }, set: { var next = options; next.alignment = $0; model.setPixelOptions(next) })) {
        ForEach(CanvasAnchor.allCases, id: \.self) { anchor in Text(anchorTitle(anchor)).tag(anchor) }
      }
      Toggle("Clip to Bounding Box", isOn: Binding(get: { options.clipToBounds }, set: { var next = options; next.clipToBounds = $0; model.setPixelOptions(next) }))
        .disabled(options.method == .fit || options.method == .conform)
    }.font(.callout)
  }
  private var dataSets: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Picker("Data Set:", selection: $model.rowID) {
          if model.settings.dataSets.isEmpty { Text("No data sets").tag(Optional<UUID>.none) }
          ForEach(model.settings.dataSets) { row in Text(row.name).tag(Optional(row.id)) }
        }
        Button { model.addRow() } label: { Image(systemName: "plus") }.help("Create Data Set").disabled(model.settings.definitions.isEmpty)
        Button { model.addRow(duplicate: true) } label: { Image(systemName: "plus.square.on.square") }.help("Duplicate Data Set").disabled(model.selectedRow == nil)
        Button { model.deleteRow() } label: { Image(systemName: "trash") }.help("Delete Data Set").disabled(model.selectedRow == nil)
      }
      if model.selectedRow != nil {
        TextField("Data set name", text: Binding(get: { model.selectedRow?.name ?? "" }, set: { model.setRowName($0) }))
        ForEach(model.settings.variableNames, id: \.self) { name in
          if let definition = model.settings.definitions.first(where: { $0.name == name }) { valueEditor(definition) }
        }
      } else { Text("Define variables, then create or import a data set.").foregroundStyle(.secondary) }
    }
  }
  @ViewBuilder private func valueEditor(_ definition: VariableDefinition) -> some View {
    let name = definition.name, value = model.selectedRow?.values[name]
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(name).fontWeight(.medium); Spacer()
        Toggle("Set value", isOn: Binding(get: { model.selectedRow?.values[name] != nil }, set: { enabled in
          let initial: VariableValue = definition.kind == .visibility ? .visibility(true) : definition.kind == .textReplacement ? .text("") : .pixels(nil)
          model.setValue(enabled ? initial : nil, for: name)
        })).font(.caption).toggleStyle(.checkbox)
      }
      if let value {
        switch value {
        case .visibility(let visible): Toggle("Visible", isOn: Binding(get: { visible }, set: { model.setValue(.visibility($0), for: name) }))
        case .text(let text): TextField("Replacement text", text: Binding(get: { text }, set: { model.setValue(.text($0), for: name) }), axis: .vertical).lineLimit(2...5)
        case .pixels(let id):
          HStack {
            Picker("Image:", selection: Binding(get: { id }, set: { model.setValue(.pixels($0), for: name) })) {
              Text("Do Not Replace").tag(Optional<UUID>.none)
              ForEach(model.settings.images) { image in Text(image.name).tag(Optional(image.id)) }
            }
            Button("Select File…") { model.chooseImage(for: name, window: window()) }
          }
        }
      } else { Text("Leave this variable unchanged").font(.caption).foregroundStyle(.secondary) }
    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
  }
  private func title(_ kind: VariableKind) -> String {
    switch kind { case .visibility: "Visibility"; case .textReplacement: "Text Replacement"; case .pixelReplacement: "Pixel Replacement" }
  }
  private func anchorTitle(_ anchor: CanvasAnchor) -> String {
    switch anchor { case .topLeft: "Top Left"; case .top: "Top"; case .topRight: "Top Right"; case .left: "Left"; case .center: "Center"; case .right: "Right"; case .bottomLeft: "Bottom Left"; case .bottom: "Bottom"; case .bottomRight: "Bottom Right" }
  }
}
extension EditorStore {
  func presentVariables(dataSets: Bool = false, importData: Bool = false, applyOnly: Bool = false) {
    guard canEditVariables else { return }
    let snapshot = document, generation = layerPanelGeneration, model = VariableEditorModel(document, dataSets: dataSets || importData || applyOnly)
    let alert = NSAlert(); alert.messageText = applyOnly ? "Apply Data Set" : "Variables"
    alert.informativeText = "Define layer variables and generate variations from named data sets."
    alert.addButton(withTitle: applyOnly ? "Apply" : "OK"); alert.addButton(withTitle: "Cancel")
    if !applyOnly { alert.addButton(withTitle: "Apply") }
    model.onBusyChanged = { [weak alert] busy in
      guard let alert else { return }
      for (index, button) in alert.buttons.enumerated() where index != 1 { button.isEnabled = !busy }
    }
    let host = NSHostingView(rootView: VariablesSheet(model: model, window: { [weak alert] in alert?.window }))
    host.frame = NSRect(x: 0, y: 0, width: 780, height: 465); alert.accessoryView = host
    let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      model.cancel()
      guard response == .alertFirstButtonReturn || response == .alertThirdButtonReturn, let self else { return }
      guard self.canEditVariables, self.document == snapshot, self.layerPanelGeneration == generation else { self.error = "The template changed. Reopen Variables."; return }
      let apply = applyOnly || response == .alertThirdButtonReturn
      guard !apply || model.rowID != nil else { self.error = "Choose a data set to apply."; return }
      self.performGeometry(.variables(.configure(model.settings, apply: apply ? model.rowID : nil)))
    }
    if let window = NSApp.keyWindow {
      alert.beginSheetModal(for: window, completionHandler: finish)
      if importData { model.chooseDataFile(window: alert.window) }
    } else { finish(alert.runModal()) }
  }
}
extension AppDelegate {
  @objc func defineVariables() { store?.presentVariables() }
  @objc func editVariableDataSets() { store?.presentVariables(dataSets: true) }
  @objc func importVariableDataSets() { store?.presentVariables(importData: true) }
  @objc func applyVariableDataSet() { store?.presentVariables(applyOnly: true) }
  @objc func exportVariableDataSets() { store?.presentVariableExport() }
  func validateVariableMenu(_ item: NSMenuItem) -> Bool? {
    guard [#selector(defineVariables), #selector(editVariableDataSets), #selector(importVariableDataSets), #selector(applyVariableDataSet), #selector(exportVariableDataSets)].contains(item.action) else { return nil }
    guard let store, store.canEditVariables else { return false }
    if item.action == #selector(applyVariableDataSet) || item.action == #selector(exportVariableDataSets) { return store.document.variables?.dataSets.isEmpty == false }
    if item.action == #selector(importVariableDataSets) { return store.document.variables?.definitions.isEmpty == false }
    return true
  }
}
