import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

struct CameraRawSheet: View {
  @Bindable var store: EditorStore
  private var placement: RawPlacementWorkspace?
  private var filmstrip: RawFilmstripWorkspace?
  private let filmstripPhoto: UUID?
  private let gridInspectorOnly: Bool
  @State private var model = CameraRawWorkspace()
  @State private var group = "Light"
  @State private var band = 0
  @State private var wheel = 0
  @State private var curveChannel = 0
  @State private var importing = false
  @State private var exporting = false
  @State private var exportFile: LUTDocument?
  @State private var exportType = Self.xmpType
  @State private var exportName = "Camera Raw.xmp"
  @State private var dngTask: Task<Void, Never>?
  @State private var sourceTask: Task<Void, Never>?
  @State private var imageExportTask: Task<Void, Never>?
  @State private var imageExportPanel: NSSavePanel?
  @State private var imageExportStatus: String?
  @State private var imageExportFormat = DocumentIO.Format.tiff
  @State private var imageExportOptions: [DocumentIO.Format: RasterEncodingOptions] = [:]
  @State private var showingWorkflow = false
  @State private var openModifiers: NSEvent.ModifierFlags = []
  private var savingSource: Bool { sourceTask != nil }
  private var exportingImage: Bool { imageExportTask != nil || imageExportPanel != nil }
  @State private var sourceSaveError: String?
  @State private var sidecarAccessPanel: NSOpenPanel?
  private static let xmpType = UTType(filenameExtension: "xmp", conformingTo: .data) ?? .xml
  private static let dngType = UTType("com.adobe.raw-image") ?? .data
  private var defaultOpenAsObject: Bool { filmstrip?.defaultOpenAsObject ?? store.documentController?.cameraRawPreferences.openAsSmartObject ?? false }
  private var groups: [String] { (model.sensorSettings == nil ? [] : ["Sensor"]) + ["Light","Color","Effects","Curve","Color Mixer","Color Grading","Detail"] }
  init(store: EditorStore, workspace: CameraRawWorkspace? = nil, placement: RawPlacementWorkspace? = nil,
    filmstrip: RawFilmstripWorkspace? = nil, filmstripPhoto: UUID? = nil, gridInspectorOnly: Bool = false) {
    self.store = store
    self.placement = placement
    self.filmstrip = filmstrip
    self.filmstripPhoto = filmstripPhoto
    self.gridInspectorOnly = gridInspectorOnly
    _model = State(initialValue: workspace ?? CameraRawWorkspace())
  }

  private func slider(_ editing: Bool) {
    filmstrip?.slider(editing)
    model.slider(editing)
  }
  private func binding(_ key: String) -> Binding<Double> { Binding(get:{ Double(model.settings[key]) },set:{ var value = model.settings; value[key] = Float($0); model.change(value) }) }
  private func control(_ title: String,_ value: Binding<Double>,_ range: ClosedRange<Double>) -> some View {
    VStack(alignment:.leading,spacing:3) {
      HStack { Text(title); Spacer(); TextField(title,value:value,format:.number.precision(.fractionLength(0...2))).frame(width:64).textFieldStyle(.roundedBorder) }
      Slider(value:value,in:range,onEditingChanged:slider).accessibilityLabel(title)
    }.padding(.vertical,3)
  }
  private var loupe: some View {
    VStack(spacing:0) {
      HStack {
        Text(filmstrip?.activeName ?? (model.sensorSettings == nil ? "Camera Raw Filter" : "Camera Raw — Source")).font(.headline)
        Spacer()
        if savingSource {
          ProgressView().controlSize(.small).accessibilityLabel("Finishing Camera Raw")
        } else if imageExportTask != nil {
          ProgressView().controlSize(.small).accessibilityLabel("Preparing the developed image")
        } else if model.rendering {
          ProgressView().controlSize(.small).accessibilityLabel("Rendering Camera Raw preview")
        }
        if let filmstrip {
          Button("Save Images…", action: filmstrip.chooseExportDestination)
            .help("Develop the selected photos and save TIFF, JPEG, PNG or Photoshop files.")
            .disabled(!filmstrip.canFinish)
        } else if let document = store.initialRawDocument {
          Button("Save Image…") { saveDevelopedImage(from: document) }
            .keyboardShortcut("s", modifiers: .command)
            .help("Save a TIFF, JPEG, PNG or Photoshop file using these Camera Raw settings.")
            .disabled(!model.ready || exportingImage || dngTask != nil || showingWorkflow)
        }
        settingsCommands
      }.padding(12)
      Divider()
      HStack(spacing:0) {
        GeometryReader { geo in
          ScrollView([.horizontal,.vertical]) {
            if let image = model.preview ? model.image : model.originalImage {
              let fit = min(geo.size.width/CGFloat(image.width),geo.size.height/CGFloat(image.height))
              Image(decorative:image,scale:1).resizable().interpolation(.high)
                .frame(width:CGFloat(image.width)*fit*model.zoom,height:CGFloat(image.height)*fit*model.zoom)
                .frame(minWidth:geo.size.width,minHeight:geo.size.height)
            }
          }.background(Color(white:0.12))
        }
        Divider()
        adjustmentPanel
      }
      Divider()
      if let error = sourceSaveError ?? model.error {
        Text(error).font(.caption).foregroundStyle(.red).padding(6)
      } else if let imageExportStatus {
        Text(imageExportStatus).font(.caption).foregroundStyle(.secondary).padding(6)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview)
        Button("−") { model.zoom = max(0.25,model.zoom/1.25) }; Text("\(Int(model.zoom*100))% fit").monospacedDigit()
        Button("+") { model.zoom = min(8,model.zoom*1.25) }; Button("Fit") { model.zoom = 1 }
        if let filmstrip {
          Button("Output Settings…") { showingWorkflow = true }
            .popover(isPresented: $showingWorkflow, arrowEdge: .bottom) {
              RawWorkflowControls(output: filmstrip.workflowOutput, width: store.document.width,
                height: store.document.height, onApply: { filmstrip.setWorkflow($0); showingWorkflow = false },
                onCancel: { showingWorkflow = false })
            }
        } else if store.initialRawDocument != nil, let preferences = store.documentController?.cameraRawPreferences {
          Button("Output Settings…") { showingWorkflow = true }
            .help("Choose the color profile, bit depth, resolution and dimensions of the opened document.")
            .popover(isPresented: $showingWorkflow, arrowEdge: .bottom) {
              RawWorkflowControls(output: preferences.workflowOutput, width: store.document.width,
                height: store.document.height, onApply: {
                  preferences.workflowOutput = $0
                  showingWorkflow = false
                }, onCancel: { showingWorkflow = false })
            }
        }
        Spacer()
        Button("Reset") { model.reset() }
        if let filmstrip {
          RawFilmstripFinishControls(workspace: filmstrip, openingEnabled: !importing && !exporting && !showingWorkflow,
            showsSave: false)
        } else {
          Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty)
          Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty)
          Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
          openSourceControls
        }
      }.padding(12)
    }
  }

  @ViewBuilder private var openSourceControls: some View {
    if let document = store.initialRawDocument {
      if document.localRawSource != nil {
        Button("Done") { finishSource(document, mode: nil) }
          .help("Save these settings to the RAW file or its XMP sidecar and close Camera Raw.")
          .disabled(!model.ready || dngTask != nil || exportingImage)
      }
      let mode = RawOpenShortcuts.mode(for: openModifiers, defaultAsObject: defaultOpenAsObject)
      HStack(spacing: 4) {
        Button(mode.title) {
          let flags = NSApp.currentEvent?.modifierFlags ?? openModifiers
          finishSource(document, mode: RawOpenShortcuts.mode(for: flags, defaultAsObject: defaultOpenAsObject))
        }
          .keyboardShortcut(.defaultAction)
          .help(mode.openHelp)
        Menu {
          Button(RawOpenMode.image.title) { finishSource(document, mode: .image) }
            .keyboardShortcut("o", modifiers: defaultOpenAsObject ? [.command, .shift] : .command)
          Button(RawOpenMode.object.title) { finishSource(document, mode: .object) }
            .keyboardShortcut("o", modifiers: defaultOpenAsObject ? .command : [.command, .shift])
          Button(RawOpenMode.copy.title) { finishSource(document, mode: .copy) }
            .keyboardShortcut("o", modifiers: [.command, .option])
        } label: {
          Image(systemName: "chevron.down")
        }
        .accessibilityLabel("Camera Raw opening options")
        .help("Choose how to open this RAW image.")
        .fixedSize()
      }
      .disabled(!model.ready || dngTask != nil || exportingImage)
      .background(RawSourceKeyMonitor(onFlags: { openModifiers = $0 }, onOpen: { flags in
        let selected = RawOpenShortcuts.mode(for: flags, defaultAsObject: defaultOpenAsObject)
        finishSource(document, mode: selected)
      }, onSave: {
        saveDevelopedImage(from: document)
      }))
    } else {
      Button("OK", action: commit).keyboardShortcut(.defaultAction).disabled(!model.ready)
    }
  }

  private var settingsCommands: some View {
    HStack {
      Button("Load Settings…") { importing = true }
        .help("Load Camera Raw XMP or Photato JSON settings.")
        .disabled(exportingImage)
      Menu("Save Settings") {
        Button("Camera Raw XMP…") { exportSettings(xmp: true) }
          .help("Share supported adjustments with Adobe Camera Raw.")
        Button("Photato JSON…") { exportSettings(xmp: false) }
          .help("Save all Photato Camera Raw settings.")
        if model.dngSource != nil {
          Divider()
          Button("DNG Copy…", action: exportDNG)
            .help("Save a copy of the RAW sensor data with embedded Camera Raw settings.")
        }
      }.disabled(dngTask != nil || exportingImage)
    }
  }

  private var adjustmentPanel: some View {
    VStack(spacing: 10) {
      if gridInspectorOnly {
        settingsCommands.controlSize(.small)
        if let error = sourceSaveError ?? model.error {
          Text(error).font(.caption).foregroundStyle(.red)
        }
      }
      histogram.frame(height:90).background(Color(white:0.1)).clipShape(RoundedRectangle(cornerRadius:5))
      Picker("Adjustments",selection:$group) { ForEach(groups,id:\.self) { Text($0) } }.labelsHidden()
      ScrollView { controls.padding(.trailing,5) }
    }
    .padding(14)
    .frame(width: 310)
  }

  var body: some View {
    Group {
      if gridInspectorOnly { adjustmentPanel }
      else { loupe }
    }
    .disabled(savingSource)
    .interactiveDismissDisabled(savingSource)
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      openModifiers = NSEvent.modifierFlags
    }
    .frame(width: filmstrip == nil ? min(1180, (NSScreen.main?.visibleFrame.width ?? 1280) - 80) : nil,
      height: filmstrip == nil ? min(780, (NSScreen.main?.visibleFrame.height ?? 900) - 100) : nil)
    .task {
      guard let draft = store.filterDraft else { return }
      model.onChange = { store.filterDraft?.filter.cameraRaw = $0 }
      model.onSensorChange = { value in
        store.filterDraft?.rawDevelopment = value
        if let filmstripPhoto { filmstrip?.apply(value, to: filmstripPhoto) }
      }
      if draft.rawDevelopment != nil { group = "Sensor" }
      await model.prepare(document: store.document, draft: draft,
        retainRawOutput: store.initialRawDocument != nil || filmstrip != nil)
    }
    .onChange(of: filmstrip?.activeSettings) { _, current in
      if filmstrip?.activeID == filmstripPhoto, let current { model.changeSensor(current, remember: false) }
    }
    .onDisappear {
      imageExportTask?.cancel()
      imageExportTask = nil
      imageExportPanel?.cancel(nil)
      imageExportPanel = nil
      sourceTask?.cancel()
      sourceTask = nil
      dngTask?.cancel()
      dngTask = nil
      sidecarAccessPanel?.cancel(nil)
      sidecarAccessPanel = nil
      model.close()
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [Self.xmpType, .json, .data]) { result in
      do {
        let url = try result.get()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let xmp = url.pathExtension.lowercased() == "xmp"
        let limit = xmp ? CameraRawXMP.maximumBytes : 32_768
        let data = try file.read(upToCount: limit + 1) ?? Data()
        try model.loadSettings(data, xmp: xmp)
      } catch { model.error = error.localizedDescription }
    }
    .fileExporter(isPresented: $exporting, document: exportFile,
      contentType: exportType, defaultFilename: exportName) {
      if case .failure(let error) = $0 { model.error = error.localizedDescription }
    }
  }
  private func cancel() {
    if let filmstrip { filmstrip.close(); return }
    if let placement { placement.cancel(); return }
    let sourceDocument = store.initialRawDocument
    store.initialRawDocument = nil
    model.close()
    store.cancelFilter()
    sourceDocument?.close()
  }

  private func commit() {
    guard model.ready else { return }
    if let placement { placement.run(); return }
    store.initialRawDocument = nil
    store.filterDraft?.filter.cameraRaw = model.settings
    store.filterDraft?.rawDevelopment = model.sensorSettings
    let sensor = model.sensorRaster
    model.close()
    store.commitFilter(reusingRawSensor: sensor)
  }

  private func finishSource(_ document: CraftNSDocument, mode: RawOpenMode?, authorizedFolder: URL? = nil) {
    guard !savingSource, !exportingImage, !showingWorkflow, sidecarAccessPanel == nil, dngTask == nil,
      store.initialRawDocument === document, let layerID = store.filterDraft?.id,
      let settings = model.sensorSettings, model.canOpen(in: store.document),
      let output = model.developedRawPreview else { return }
    sourceSaveError = nil
    let workflow = store.documentController?.cameraRawPreferences.workflowOutput ?? .init()
    sourceTask = Task {
      defer { sourceTask = nil }
      do {
        if let mode {
          try await document.finishRawOpen(mode, from: output, layerID: layerID, workflow: workflow,
            authorizedFolder: authorizedFolder)
        } else {
          try await document.saveRawSourceSettings(layerID: layerID, settings: settings,
            authorizedFolder: authorizedFolder)
          guard store.initialRawDocument === document else { return }
          store.initialRawDocument = nil
          store.cancelFilter()
          document.close()
        }
      } catch RawDNGSource.SaveError.sidecarAccessNeeded where authorizedFolder == nil {
        sourceSaveError = RawDNGSource.SaveError.sidecarAccessNeeded.localizedDescription
        if let source = document.localRawSource?.original {
          requestSourceFolderAccess(source, document: document, mode: mode)
        }
      } catch is CancellationError {
      } catch {
        sourceSaveError = error.localizedDescription
      }
    }
  }

  private func requestSourceFolderAccess(_ source: RawSettingsSource, document: CraftNSDocument, mode: RawOpenMode?) {
    let panel = NSOpenPanel()
    let folder = source.url.deletingLastPathComponent()
    panel.title = "Allow Access to the Source Folder"
    if source.savesInsideDNG, let sidecar = source.sidecarURL {
      panel.message = "Select \(folder.lastPathComponent) so Photato can retire \(sidecar.lastPathComponent) after embedding its settings in the DNG."
    } else {
      panel.message = "Select \(folder.lastPathComponent) so Photato can save the XMP sidecar beside \(source.url.lastPathComponent)."
    }
    panel.prompt = "Allow Access"
    panel.directoryURL = folder
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = false
    sidecarAccessPanel = panel
    let completion: (NSApplication.ModalResponse) -> Void = { response in
      sidecarAccessPanel = nil
      guard response == .OK, let selected = panel.url, store.initialRawDocument === document else { return }
      finishSource(document, mode: mode, authorizedFolder: selected)
    }
    if let window = document.windowForSheet?.attachedSheet {
      panel.beginSheetModal(for: window, completionHandler: completion)
    } else {
      panel.begin(completionHandler: completion)
    }
  }

  private func saveDevelopedImage(from document: CraftNSDocument) {
    guard !exportingImage, !savingSource, dngTask == nil, !showingWorkflow,
      store.initialRawDocument === document, model.canOpen(in: store.document),
      let developed = model.developedRawPreview else { return }
    let workflow = document.ownerController?.cameraRawPreferences.workflowOutput ?? .init()
    let original = document.importedSourceURL
    imageExportStatus = nil
    sourceSaveError = nil
    imageExportTask = Task {
      defer { imageExportTask = nil }
      let worker = Task.detached(priority: .userInitiated) {
        try RawOpenMode.copy.output(from: developed, workflow: workflow)
      }
      do {
        let output = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard store.initialRawDocument === document else { return }
        showDevelopedImageSavePanel(output, document: document, original: original)
      } catch is CancellationError {
      } catch { sourceSaveError = error.localizedDescription }
    }
  }

  private func showDevelopedImageSavePanel(_ output: CraftDocument, document: CraftNSDocument, original: URL?) {
    let panel = NSSavePanel()
    panel.title = "Save Developed Image"
    panel.nameFieldStringValue = output.name + "." + imageExportFormat.rawValue
    panel.directoryURL = original?.deletingLastPathComponent()
    panel.canCreateDirectories = true
    let accessory = DocumentCopyAccessory(panel: panel, initial: imageExportFormat,
      availableFormats: [.tiff, .jpeg, .png, .psd], initialOptions: imageExportOptions,
      depth: output.depth, mode: output.colorMode, documentIsUntagged: output.profileIsUntagged == true,
      width: output.width, height: output.height)
    panel.accessoryView = accessory.view
    imageExportPanel = panel
    let completion: (NSApplication.ModalResponse) -> Void = { response in
      imageExportPanel = nil
      guard response == .OK, let destination = panel.url, store.initialRawDocument === document else { return }
      let format = accessory.format
      let options = accessory.encodingOptions
      imageExportTask = Task {
        defer { imageExportTask = nil }
        let worker = Task.detached(priority: .userInitiated) {
          let access = destination.startAccessingSecurityScopedResource()
          defer { if access { destination.stopAccessingSecurityScopedResource() } }
          guard destination.standardizedFileURL.resolvingSymlinksInPath() != original else {
            throw CraftError.invalid("Choose a different destination to keep the original Camera Raw file.")
          }
          let file = try DocumentIO.prepareOutput(output, format: format, persistence: false, options: options)
          try file.write(to: destination)
        }
        do {
          try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
          try Task.checkCancellation()
          guard store.initialRawDocument === document else { return }
          imageExportFormat = format
          imageExportOptions[format] = options
          imageExportStatus = "Saved " + destination.lastPathComponent
        } catch is CancellationError {
        } catch { sourceSaveError = error.localizedDescription }
      }
    }
    if let parent = document.windowForSheet?.attachedSheet {
      panel.beginSheetModal(for: parent, completionHandler: completion)
    } else {
      panel.begin(completionHandler: completion)
    }
  }

  private func exportSettings(xmp: Bool) {
    do {
      exportFile = LUTDocument(data: try model.settingsData(xmp: xmp))
      exportType = xmp ? Self.xmpType : .json
      exportName = xmp ? "Camera Raw.xmp" : "Camera Raw.photatoraw"
      exporting = true
    } catch { model.error = error.localizedDescription }
  }
  private func exportDNG() {
    guard dngTask == nil, let object = model.dngSource, let settings = model.sensorSettings else { return }
    dngTask = Task {
      defer { dngTask = nil }
      let worker = Task.detached(priority: .userInitiated) {
        try RawSourceIO.dngWithSettings(object.data, settings: settings)
      }
      do {
        let data = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        exportFile = LUTDocument(data: data)
        exportType = Self.dngType
        exportName = (object.fileName as NSString).deletingPathExtension + " Settings.dng"
        exporting = true
      } catch is CancellationError {
      } catch {
        model.error = error.localizedDescription
      }
    }
  }

  private var histogram: some View {
    Canvas { context,size in
      for channel in 0..<3 {
        var path = Path(); path.move(to:CGPoint(x:0,y:size.height))
        for i in 0..<256 { path.addLine(to:CGPoint(x:Double(i)/255*size.width,y:(1-Double(model.histogram[channel][i]))*size.height)) }
        path.addLine(to:CGPoint(x:size.width,y:size.height)); path.closeSubpath()
        context.fill(path,with:.color([Color.red,.green,.blue][channel].opacity(0.45)))
      }
    }.accessibilityLabel("RGB histogram")
  }
  @ViewBuilder private var controls: some View {
    VStack(alignment:.leading,spacing:8) {
      ForEach(CameraRawSettings.controls.filter { $0.group == group }) { c in control(c.title,binding(c.key),Double(c.minimum)...Double(c.maximum)) }
      if group == "Sensor" { sensorControls }
      if group == "Effects" {
        Picker("Vignette style",selection:Binding(get:{ model.settings.vignetteStyle },set:{ var v = model.settings; v.vignetteStyle = $0; model.change(v) })) {
          Text("Highlight Priority").tag("highlightPriority"); Text("Color Priority").tag("colorPriority"); Text("Paint Overlay").tag("paintOverlay")
        }
      }
      if group == "Color Mixer" { mixer }
      if group == "Color Grading" { grading }
      if group == "Curve" { curves }
    }
  }
  private func sensorNumber(_ key: WritableKeyPath<RawDevelopment,Float>) -> Binding<Double> {
    Binding(get:{ Double((model.sensorSettings ?? .init())[keyPath:key]) },set:{ n in var v = model.sensorSettings ?? .init(); v[keyPath:key] = Float(n); model.changeSensor(v) })
  }
  @ViewBuilder private var sensorControls: some View {
    if let info = model.sensorInfo,let settings = model.sensorSettings {
      Text(info.model).font(.headline)
      Text("\(info.nativeWidth) × \(info.nativeHeight) sensor pixels").font(.caption).foregroundStyle(.secondary)
      if let iso = info.iso {
        LabeledContent("ISO", value: iso.formatted()).font(.caption)
      }
      Picker("Decoder",selection:Binding(get:{ settings.decoderVersion ?? info.decoderVersion },set:{ var v = settings; v.decoderVersion = $0; model.changeSensor(v) })) {
        ForEach(info.supportedDecoders,id:\.self) { Text($0).tag($0) }
      }
      control("Temperature (K)",Binding(get:{ Double(settings.temperature ?? info.temperature) },set:{ var v = settings; v.temperature = Float($0); model.changeSensor(v) }),2000...50000)
      control("Tint",Binding(get:{ Double(settings.tint ?? info.tint) },set:{ var v = settings; v.tint = Float($0); model.changeSensor(v) }),-150...150)
      Button("As Shot White Balance") { var v = settings; v.temperature = nil; v.tint = nil; model.changeSensor(v) }
      control("Sensor exposure",sensorNumber(\.exposure),-5...5)
      control("Tone boost",sensorNumber(\.boost),0...1)
      control("Shadow boost",sensorNumber(\.shadowBoost),0...2)
      control("Extended range",sensorNumber(\.extendedRange),0...2)
      Toggle("Lens correction",isOn:Binding(get:{ settings.lensCorrection ?? info.lensCorrectionEnabled },set:{ var v = settings; v.lensCorrection = $0; model.changeSensor(v) })).disabled(!info.lensCorrectionSupported)
      Toggle("Highlight recovery",isOn:Binding(get:{ settings.highlightRecovery ?? info.highlightRecoveryEnabled },set:{ var v = settings; v.highlightRecovery = $0; model.changeSensor(v) })).disabled(!info.highlightRecoverySupported)
      Text("Original RAW data is retained. Changes redevelop every shared instance; use New Smart Object via Copy for an independent version.").font(.caption).foregroundStyle(.secondary)
    }
  }
  private var mixer: some View {
    VStack {
      Picker("Color",selection:$band) { ForEach(Array(["Reds","Oranges","Yellows","Greens","Aquas","Blues","Purples","Magentas"].enumerated()),id:\.offset) { Text($0.element).tag($0.offset) } }
      ForEach(0..<3,id:\.self) { index in
        control(["Hue","Saturation","Luminance"][index],Binding(get:{ Double([model.settings.hslHue,model.settings.hslSat,model.settings.hslLum][index][band]) },set:{ n in
          var v = model.settings
          switch index { case 0: v.hslHue[band] = Float(n); case 1: v.hslSat[band] = Float(n); default: v.hslLum[band] = Float(n) }; model.change(v)
        }),-100...100)
      }
    }
  }
  private var grading: some View {
    VStack {
      Picker("Tone",selection:$wheel) { ForEach(Array(["Shadows","Midtones","Highlights","Global"].enumerated()),id:\.offset) { Text($0.element).tag($0.offset) } }
      ForEach(0..<3,id:\.self) { index in
        control(["Hue","Saturation","Luminance"][index],Binding(get:{ let w = [model.settings.gradeShadows,model.settings.gradeMidtones,model.settings.gradeHighlights,model.settings.gradeGlobal][wheel]; return Double([w.hue,w.sat,w.lum][index]) },set:{ n in
          var v = model.settings; var w = [v.gradeShadows,v.gradeMidtones,v.gradeHighlights,v.gradeGlobal][wheel]
          switch index { case 0: w.hue = Float(n); case 1: w.sat = Float(n); default: w.lum = Float(n) }
          switch wheel { case 0: v.gradeShadows = w; case 1: v.gradeMidtones = w; case 2: v.gradeHighlights = w; default: v.gradeGlobal = w }; model.change(v)
        }), index == 0 ? 0...360 : index == 1 ? 0...100 : -100...100)
      }
    }
  }
  private var curves: some View {
    VStack {
      Picker("Point curve",selection:$curveChannel) { ForEach(Array(["RGB","Red","Green","Blue"].enumerated()),id:\.offset) { Text($0.element).tag($0.offset) } }
      CameraRawCurve(points:Binding(get:{ [model.settings.pointCurve,model.settings.pointCurveRed,model.settings.pointCurveGreen,model.settings.pointCurveBlue][curveChannel] },set:{ points in
        var v = model.settings
        switch curveChannel { case 0: v.pointCurve = points; case 1: v.pointCurveRed = points; case 2: v.pointCurveGreen = points; default: v.pointCurveBlue = points }; model.change(v)
      }),editing:slider).frame(height:220)
      Text("Drag a point, or click the curve area to add one.").font(.caption).foregroundStyle(.secondary)
      Button("Reset point curve") { var v = model.settings; switch curveChannel { case 0: v.pointCurve = []; case 1: v.pointCurveRed = []; case 2: v.pointCurveGreen = []; default: v.pointCurveBlue = [] }; model.change(v) }
    }
  }
}

private struct CameraRawCurve: View {
  @Binding var points: [[Float]]
  var editing: (Bool) -> Void
  @State private var selected: Int?
  private var display: [[Float]] { points.isEmpty ? [[0,0],[255,255]] : points }
  var body: some View {
    GeometryReader { geo in
      Canvas { context,size in
        var grid = Path()
        for i in 0...4 { let t = Double(i)/4; grid.move(to:CGPoint(x:t*size.width,y:0)); grid.addLine(to:CGPoint(x:t*size.width,y:size.height)); grid.move(to:CGPoint(x:0,y:t*size.height)); grid.addLine(to:CGPoint(x:size.width,y:t*size.height)) }
        context.stroke(grid,with:.color(.gray.opacity(0.4)),lineWidth:1)
        var line = Path()
        for (i,p) in display.enumerated() { let q = CGPoint(x:Double(p[0])/255*size.width,y:(1-Double(p[1])/255)*size.height); if i == 0 { line.move(to:q) } else { line.addLine(to:q) }; context.fill(Path(ellipseIn:CGRect(x:q.x-4,y:q.y-4,width:8,height:8)),with:.color(.white)) }
        context.stroke(line,with:.color(.white),lineWidth:1.5)
      }.background(Color(white:0.15)).gesture(DragGesture(minimumDistance:0).onChanged { event in
        var values = display
        let x = Float(min(255,max(0,event.location.x/geo.size.width*255))), y = Float(min(255,max(0,(1-event.location.y/geo.size.height)*255)))
        if selected == nil {
          editing(true)
          let nearby = values.indices.min { abs(values[$0][0]-x) < abs(values[$1][0]-x) }!
          if abs(values[nearby][0]-x) < 12 || values.count >= 16 { selected = nearby }
          else { let index = values.firstIndex { $0[0] > x } ?? values.count; values.insert([x,y],at:index); selected = index }
        }
        if let i = selected { let lower: Float = i == 0 ? 0 : values[i-1][0]+1, upper: Float = i == values.count-1 ? 255 : values[i+1][0]-1; values[i] = [min(upper,max(lower,x)),y]; points = values }
      }.onEnded { _ in selected = nil; editing(false) })
    }.accessibilityLabel("Point curve editor")
  }
}


private extension RawOpenMode {
  var title: String {
    switch self {
    case .image: "Open Image"
    case .object: "Open Object"
    case .copy: "Open Copy"
    }
  }

  var openHelp: String {
    switch self {
    case .image: "Open as a Background layer and save Camera Raw settings to the source."
    case .object: "Open as a Smart Object and save Camera Raw settings to the source."
    case .copy: "Open as a Background layer without saving settings to the source."
    }
  }
}

enum RawOpenShortcuts {
  static func mode(for flags: NSEvent.ModifierFlags, defaultAsObject: Bool) -> RawOpenMode {
    if flags.contains(.option) { return .copy }
    return flags.contains(.shift) != defaultAsObject ? .object : .image
  }
}

struct RawFilmstripFinishControls: View {
  let workspace: RawFilmstripWorkspace
  var openingEnabled = true
  var showsSave = true
  @State private var modifiers: NSEvent.ModifierFlags = []

  var body: some View {
    HStack(spacing: 6) {
      if showsSave {
        Button("Save Images…", action: workspace.chooseExportDestination).disabled(!workspace.canFinish)
      }
      Button("Undo", action: workspace.undoEdit).keyboardShortcut("z", modifiers: .command).disabled(!workspace.canUndo)
      Button("Redo", action: workspace.redoEdit).keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!workspace.canRedo)
      Button("Cancel", action: workspace.close).keyboardShortcut(.cancelAction).disabled(workspace.finishing)
      Button("Done") { workspace.finish(nil) }.disabled(!workspace.canWrite)
        .help("Save the selected photos’ Camera Raw settings.")
      let mode = RawOpenShortcuts.mode(for: modifiers, defaultAsObject: workspace.defaultOpenAsObject)
      HStack(spacing: 4) {
        Button(mode.title) { workspace.finish(mode) }.keyboardShortcut(.defaultAction)
          .help("Open the selected photos with their individual settings.")
        Menu {
          Button(RawOpenMode.image.title) { workspace.finish(.image) }
          Button(RawOpenMode.object.title) { workspace.finish(.object) }
          Button(RawOpenMode.copy.title) { workspace.finish(.copy) }
        } label: { Image(systemName: "chevron.down") }
        .menuIndicator(.hidden)
        .accessibilityLabel("Camera Raw opening options")
      }
      .disabled(!workspace.canFinish || !openingEnabled)
    }
    .background(RawSourceKeyMonitor(onFlags: { modifiers = $0 }, onOpen: { flags in
      guard openingEnabled else { return }
      workspace.finish(RawOpenShortcuts.mode(for: flags, defaultAsObject: workspace.defaultOpenAsObject))
    }, onSave: workspace.chooseExportDestination))
    .onAppear { modifiers = NSEvent.modifierFlags }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      modifiers = NSEvent.modifierFlags
    }
  }
}

private struct RawSourceKeyMonitor: NSViewRepresentable {
  var onFlags: (NSEvent.ModifierFlags) -> Void
  var onOpen: (NSEvent.ModifierFlags) -> Void
  var onSave: () -> Void

  func makeNSView(context: Context) -> MonitorView { MonitorView() }

  func updateNSView(_ view: MonitorView, context: Context) {
    view.onFlags = onFlags
    view.onOpen = onOpen
    view.onSave = onSave
  }

  final class MonitorView: NSView {
    var onFlags: ((NSEvent.ModifierFlags) -> Void)?
    var onOpen: ((NSEvent.ModifierFlags) -> Void)?
    var onSave: (() -> Void)?
    private var monitor: Any?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
      if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
      if newWindow != nil {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
          guard let self, let window, window.isKeyWindow, event.window === window else { return event }
          let modifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
          let flags = event.modifierFlags.intersection(modifiers)
          if event.type == .flagsChanged {
            onFlags?(flags)
          } else if flags.contains(.command), !flags.contains(.control) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "o":
              if !event.isARepeat { onOpen?(flags) }
              return nil
            case "s" where flags == .command:
              if !event.isARepeat { onSave?() }
              return nil
            default:
              break
            }
          }
          return event
        }
      }
      super.viewWillMove(toWindow: newWindow)
    }
  }
}
