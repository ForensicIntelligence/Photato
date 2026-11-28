import AppKit
import PhotoCraftCore
import PhotoCraftImaging

enum DocumentPersistenceConflict: LocalizedError {
  case changed
  var errorDescription: String? { "The document changed while reading its saved version." }
}

@MainActor final class DocumentCopyAccessory: NSObject {
  let view = NSStackView()
  let formats = NSPopUpButton(frame: .zero, pullsDown: false)
  let explanation = NSTextField(wrappingLabelWithString: "")
  let jpegControls = JPEGSaveControls()
  let exrControls = OpenEXRSaveControls()
  weak var panel: NSSavePanel?
  let availableFormats: [DocumentIO.Format]
  let saving: Bool
  let pngCompression = NSPopUpButton(frame: .zero, pullsDown: false)
  let pngInterlaced = NSButton(checkboxWithTitle: "Interlaced", target: nil, action: nil)
  let tiffCompression = NSPopUpButton(frame: .zero, pullsDown: false)
  let tiffJPEGQuality = NSPopUpButton(frame: .zero, pullsDown: false)
  private let tiffJPEGQualityRow = NSStackView()
  private var selectedTIFFCompression: RasterEncodingOptions.TIFFCompression? {
    let index = tiffCompression.indexOfSelectedItem - 1
    let choices = RasterEncodingOptions.TIFFCompression.allCases
    return choices.indices.contains(index) ? choices[index] : nil
  }
  let tiffByteOrder = NSPopUpButton(frame: .zero, pullsDown: false)
  let tiffPixelOrder = NSPopUpButton(frame: .zero, pullsDown: false)
  let tiffPredictor = NSButton(checkboxWithTitle: "Use Predictor", target: nil, action: nil)
  let tiffLayers = NSButton(checkboxWithTitle: "Layers", target: nil, action: nil)
  let tiffImagePyramid = NSButton(checkboxWithTitle: "Save Image Pyramid", target: nil, action: nil)
  let tiffTransparency = NSButton(checkboxWithTitle: "Save Transparency", target: nil, action: nil)
  let tiffEmbedProfile = NSButton(checkboxWithTitle: "Embed Color Profile", target: nil, action: nil)
  let tiffLayerCompression = NSPopUpButton(frame: .zero, pullsDown: false)
  let tiffLayersRow = NSStackView()
  let tiffByteOrderRow = NSStackView(), tiffPixelOrderRow = NSStackView()
  private let depth: PixelDepth
  private let mode: DocumentColorMode
  private var predictorExplicit = false
  private var layersExplicit = false
  private var transparencyExplicit = false
  private var pyramidExplicit = false
  private var embedProfileExplicit = false
  let pngRow = NSStackView(), tiffRow = NSStackView()
  let psdLayerCompression = NSPopUpButton(frame: .zero, pullsDown: false)
  let psdCompositeCompression = NSPopUpButton(frame: .zero, pullsDown: false)
  let psdLayerRow = NSStackView(), psdCompositeRow = NSStackView()
  private var photoshopOptions: [DocumentIO.Format: RasterEncodingOptions] = [:]
  private var photoshopFormat: DocumentIO.Format?
  private var photoshopEncodingOptions: RasterEncodingOptions {
    let methods = RasterEncodingOptions.PhotoshopCompression.allCases
    return .init(
      psdLayerCompression: mode.isRestricted || mode == .multichannel || psdLayerCompression.indexOfSelectedItem <= 0 ? nil : methods[psdLayerCompression.indexOfSelectedItem - 1],
      psdCompositeCompression: psdCompositeCompression.indexOfSelectedItem <= 0 ? nil : methods[psdCompositeCompression.indexOfSelectedItem - 1],
      psdMaximizeCompatibility: photoshopFormat.flatMap { photoshopOptions[$0]?.psdMaximizeCompatibility })
  }
  var format: DocumentIO.Format { availableFormats[formats.indexOfSelectedItem] }
  var encodingOptions: RasterEncodingOptions {
    switch format {
    case .jpeg: return jpegControls.options
    case .exr: return exrControls.options
    case .png:
      return .init(pngCompression: pngCompression.indexOfSelectedItem == 0 ? nil : pngCompression.indexOfSelectedItem - 1,
        pngInterlaced: pngInterlaced.state == .on)
    case .tiff:
      let compression = selectedTIFFCompression
      return .init(tiffCompression: compression,
        tiffByteOrder: tiffByteOrder.indexOfSelectedItem <= 0 ? nil :
          RasterEncodingOptions.TIFFByteOrder.allCases[tiffByteOrder.indexOfSelectedItem - 1],
        tiffPixelOrder: tiffPixelOrder.indexOfSelectedItem <= 0 ? nil :
          RasterEncodingOptions.TIFFPixelOrder.allCases[tiffPixelOrder.indexOfSelectedItem - 1],
        tiffPredictor: predictorExplicit || tiffPredictor.state == .on ? tiffPredictor.state == .on : nil,
        tiffLayers: mode.isRestricted ? false : (layersExplicit || tiffLayers.state == .on ? tiffLayers.state == .on : nil),
        tiffTransparency: mode == .bitmap || !transparencyExplicit ? nil : tiffTransparency.state == .on,
        tiffImagePyramid: !tiffImagePyramid.isEnabled || !pyramidExplicit ? nil : tiffImagePyramid.state == .on,
        tiffJPEGQuality: compression == .jpeg && tiffJPEGQuality.indexOfSelectedItem > 0
          ? tiffJPEGQuality.indexOfSelectedItem - 1 : nil,
        tiffEmbedProfile: mode == .bitmap || !embedProfileExplicit ? nil : tiffEmbedProfile.state == .on,
        tiffLayerCompression: tiffLayers.state != .on || tiffLayerCompression.indexOfSelectedItem <= 0 ? nil :
          RasterEncodingOptions.TIFFLayerCompression.allCases[tiffLayerCompression.indexOfSelectedItem - 1])
    case .psd, .psb: return photoshopEncodingOptions
    default: return .init()
    }
  }

  init(
    panel: NSSavePanel, initial: DocumentIO.Format,
    availableFormats: [DocumentIO.Format] = DocumentIO.Format.allCases, saving: Bool = false,
    initialOptions: [DocumentIO.Format: RasterEncodingOptions] = [:],
    uncompressedPhotoshopDefault: Bool = false, depth: PixelDepth = .u8, mode: DocumentColorMode = .rgb,
    documentIsUntagged: Bool = false, width: Int = 1, height: Int = 1
  ) {
    self.panel = panel
    self.availableFormats = availableFormats.isEmpty ? [.native] : availableFormats
    self.saving = saving
    self.depth = depth
    self.mode = mode
    self.photoshopOptions = initialOptions
    super.init()
    formats.addItems(withTitles: self.availableFormats.map(\.title))
    formats.selectItem(at: self.availableFormats.firstIndex(of: initial) ?? 0)
    formats.target = self
    formats.action = #selector(updateFormat)
    formats.setAccessibilityLabel("File format")
    formats.identifier = WorkflowGuideHighlighter.saveFormatControl
    explanation.textColor = .secondaryLabelColor
    explanation.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    view.orientation = .vertical
    view.alignment = .leading
    view.spacing = 8
    view.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: "Format:"), formats]))
    jpegControls.configure(initialOptions[.jpeg] ?? .init())
    view.addArrangedSubview(jpegControls.view)
    exrControls.configure(initialOptions[.exr] ?? .init())
    view.addArrangedSubview(exrControls.view)
    pngCompression.addItems(withTitles: ["Default", "None (0)", "Fastest (1)", "2", "3", "4", "5", "6", "7", "8", "Smallest (9)"])
    pngCompression.setAccessibilityLabel("PNG compression")
    if let level = initialOptions[.png]?.pngCompression, (0...9).contains(level) {
      pngCompression.selectItem(at: level + 1)
    }
    pngInterlaced.state = initialOptions[.png]?.pngInterlaced == true ? .on : .off
    pngRow.addArrangedSubview(NSTextField(labelWithString: "Compression:"))
    pngRow.addArrangedSubview(pngCompression); pngRow.addArrangedSubview(pngInterlaced)
    tiffCompression.addItems(withTitles: ["Default", "None", "LZW", "ZIP", "JPEG"])
    tiffCompression.autoenablesItems = false
    tiffCompression.setAccessibilityLabel("TIFF image compression")
    let allowsJPEG = RasterEncodingOptions.supportsTIFFJPEG(width: width, height: height, depth: depth, mode: mode)
    tiffCompression.itemArray.last?.isEnabled = allowsJPEG
    tiffCompression.itemArray.last?.toolTip = "Requires opaque RGB or Grayscale at 8 bits per channel and at most 30,000 pixels per side."
    if let selected = initialOptions[.tiff]?.tiffCompression, selected != .jpeg || allowsJPEG,
      let index = RasterEncodingOptions.TIFFCompression.allCases.firstIndex(of: selected) {
      tiffCompression.selectItem(at: index + 1)
    }
    tiffJPEGQuality.addItems(withTitles: ["Default (95%)"] + (0...12).map(String.init))
    if let quality = initialOptions[.tiff]?.tiffJPEGQuality, (0...12).contains(quality) {
      tiffJPEGQuality.selectItem(at: quality + 1)
    }
    tiffJPEGQuality.setAccessibilityLabel("TIFF JPEG quality")
    tiffJPEGQualityRow.addArrangedSubview(NSTextField(labelWithString: "JPEG Quality"))
    tiffJPEGQualityRow.addArrangedSubview(tiffJPEGQuality)
    tiffRow.addArrangedSubview(NSTextField(labelWithString: "Image Compression:"))
    tiffRow.addArrangedSubview(tiffCompression)
    tiffCompression.target = self; tiffCompression.action = #selector(updateTIFFCompression)
    tiffByteOrder.addItems(withTitles: ["Default", "Macintosh (Big Endian)", "IBM PC (Little Endian)"])
    tiffPixelOrder.addItems(withTitles: ["Default", "Interleaved (RGBRGB)", "Per Channel (RRGGBB)"])
    tiffByteOrder.setAccessibilityLabel("TIFF byte order")
    tiffPixelOrder.setAccessibilityLabel("TIFF pixel order")
    let tiffOptions = initialOptions[.tiff] ?? .init()
    layersExplicit = tiffOptions.tiffLayers != nil
    tiffLayers.state = !mode.isRestricted && (tiffOptions.tiffLayers ?? saving) ? .on : .off
    tiffLayers.isEnabled = !mode.isRestricted
    tiffLayers.setAccessibilityLabel("TIFF layers")
    tiffLayers.target = self; tiffLayers.action = #selector(changeTIFFLayers)
    pyramidExplicit = tiffOptions.tiffImagePyramid != nil
    tiffImagePyramid.isEnabled = [.rgb, .grayscale, .cmyk, .lab].contains(mode)
    tiffImagePyramid.state = tiffImagePyramid.isEnabled && tiffOptions.tiffImagePyramid == true ? .on : .off
    tiffImagePyramid.target = self; tiffImagePyramid.action = #selector(changeTIFFImagePyramid)
    tiffImagePyramid.toolTip = "Includes smaller previews that page-layout apps can display without decoding the full image."
    transparencyExplicit = tiffOptions.tiffTransparency != nil
    tiffTransparency.state = mode != .bitmap && (tiffOptions.tiffTransparency ?? true) ? .on : .off
    tiffTransparency.isEnabled = mode != .bitmap
    tiffTransparency.target = self; tiffTransparency.action = #selector(changeTIFFTransparency)
    tiffTransparency.toolTip = "Keeps transparency in the merged TIFF image. Turn off to use white behind the image. Editable layers retain their transparency."
    embedProfileExplicit = tiffOptions.tiffEmbedProfile != nil
    tiffEmbedProfile.state = mode != .bitmap && (tiffOptions.tiffEmbedProfile ?? !documentIsUntagged) ? .on : .off
    tiffEmbedProfile.isEnabled = mode != .bitmap
    tiffEmbedProfile.target = self; tiffEmbedProfile.action = #selector(changeTIFFEmbedProfile)
    tiffEmbedProfile.toolTip = "Includes the document’s current ICC profile in the TIFF file."
    tiffLayerCompression.addItems(withTitles: ["Default (ZIP)", "RLE", "ZIP"])
    tiffLayerCompression.setAccessibilityLabel("TIFF layer compression")
    if let selected = tiffOptions.tiffLayerCompression,
      let index = RasterEncodingOptions.TIFFLayerCompression.allCases.firstIndex(of: selected) {
      tiffLayerCompression.selectItem(at: index + 1)
    }
    tiffLayersRow.addArrangedSubview(tiffLayers)
    tiffLayersRow.addArrangedSubview(NSTextField(labelWithString: "Layer Compression:"))
    tiffLayersRow.addArrangedSubview(tiffLayerCompression)
    updateTIFFLayers()
    tiffByteOrder.selectItem(at: tiffOptions.tiffByteOrder.flatMap {
      RasterEncodingOptions.TIFFByteOrder.allCases.firstIndex(of: $0)
    }.map { $0 + 1 } ?? 0)
    tiffPixelOrder.selectItem(at: tiffOptions.tiffPixelOrder.flatMap {
      RasterEncodingOptions.TIFFPixelOrder.allCases.firstIndex(of: $0)
    }.map { $0 + 1 } ?? 0)
    predictorExplicit = tiffOptions.tiffPredictor != nil
    tiffPredictor.state = tiffOptions.tiffPredictor == true ? .on : .off
    tiffPredictor.target = self; tiffPredictor.action = #selector(updateTIFFPredictor)
    tiffPredictor.toolTip = "Lossless floating-point prediction for 32-bit TIFF with LZW or ZIP compression."
    tiffRow.addArrangedSubview(tiffPredictor)
    tiffByteOrderRow.addArrangedSubview(NSTextField(labelWithString: "Byte Order:"))
    tiffByteOrderRow.addArrangedSubview(tiffByteOrder)
    tiffPixelOrderRow.addArrangedSubview(NSTextField(labelWithString: "Pixel Order:"))
    tiffPixelOrderRow.addArrangedSubview(tiffPixelOrder)
    updateTIFFCompression()
    let methods = ["None", "RLE", "ZIP", "ZIP with Prediction"]
    psdLayerCompression.addItems(withTitles: [
      uncompressedPhotoshopDefault ? "Default (None — File Handling)" : "Default (ZIP with Prediction)"
    ] + methods)
    psdCompositeCompression.addItems(withTitles: ["Default (None)"] + methods)
    psdLayerCompression.setAccessibilityLabel("PSD and PSB layer compression")
    psdCompositeCompression.setAccessibilityLabel("PSD and PSB composite compression")
    psdLayerRow.addArrangedSubview(NSTextField(labelWithString: "Layer Compression:"))
    psdLayerRow.addArrangedSubview(psdLayerCompression)
    psdCompositeRow.addArrangedSubview(NSTextField(labelWithString: "Composite Compression:"))
    psdCompositeRow.addArrangedSubview(psdCompositeCompression)
    view.addArrangedSubview(pngRow); view.addArrangedSubview(tiffRow)
    view.addArrangedSubview(tiffJPEGQualityRow)
    view.addArrangedSubview(tiffByteOrderRow); view.addArrangedSubview(tiffPixelOrderRow)
    view.addArrangedSubview(tiffLayersRow)
    view.addArrangedSubview(tiffImagePyramid)
    view.addArrangedSubview(tiffTransparency)
    view.addArrangedSubview(tiffEmbedProfile)
    view.addArrangedSubview(psdLayerRow); view.addArrangedSubview(psdCompositeRow)
    view.addArrangedSubview(explanation)
    view.widthAnchor.constraint(equalToConstant: 420).isActive = true
    updateFormat()
  }
  @objc func updateTIFFPredictor() { predictorExplicit = true }
  @objc func updateTIFFLayers() {
    tiffLayerCompression.isEnabled = !mode.isRestricted && tiffLayers.state == .on
  }
  @objc func changeTIFFLayers() {
    layersExplicit = true; updateTIFFLayers()
  }
  @objc func changeTIFFImagePyramid() { pyramidExplicit = true }
  @objc func changeTIFFTransparency() { transparencyExplicit = true }
  @objc func changeTIFFEmbedProfile() { embedProfileExplicit = true }
  @objc func updateTIFFCompression() {
    tiffPredictor.isHidden = depth != .f32
    tiffPredictor.isEnabled = depth == .f32 && (selectedTIFFCompression == .lzw || selectedTIFFCompression == .zip)
    if !tiffPredictor.isEnabled { tiffPredictor.state = .off }
    tiffJPEGQualityRow.isHidden = format != .tiff || selectedTIFFCompression != .jpeg
  }
  @objc func updateFormat() {
    if let previous = photoshopFormat { photoshopOptions[previous] = photoshopEncodingOptions }
    photoshopFormat = format == .psd || format == .psb ? format : nil
    if let current = photoshopFormat {
      let options = photoshopOptions[current] ?? .init()
      let methods = RasterEncodingOptions.PhotoshopCompression.allCases
      psdLayerCompression.selectItem(at: options.psdLayerCompression.flatMap { methods.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
      psdCompositeCompression.selectItem(at: options.psdCompositeCompression.flatMap { methods.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
    }
    panel?.allowedContentTypes = [format.contentType]
    explanation.stringValue = saving ? format.saveNotice : format.copyDescription
    pngRow.isHidden = format != .png; tiffRow.isHidden = format != .tiff
    updateTIFFCompression()
    jpegControls.view.isHidden = format != .jpeg
    exrControls.view.isHidden = format != .exr
    tiffByteOrderRow.isHidden = format != .tiff; tiffPixelOrderRow.isHidden = format != .tiff
    tiffLayersRow.isHidden = format != .tiff
    tiffImagePyramid.isHidden = format != .tiff
    tiffTransparency.isHidden = format != .tiff
    tiffEmbedProfile.isHidden = format != .tiff
    psdLayerRow.isHidden = photoshopFormat == nil || mode.isRestricted || mode == .multichannel; psdCompositeRow.isHidden = photoshopFormat == nil
    psdCompositeCompression.autoenablesItems = false
    psdCompositeCompression.item(at: 4)?.isEnabled = mode != .bitmap
    if mode == .bitmap && psdCompositeCompression.indexOfSelectedItem == 4 { psdCompositeCompression.selectItem(at: 0) }
    if mode.isRestricted, format == .tiff || format == .png || format == .psd || format == .psb {
      explanation.stringValue = "Preserves the document’s " + (mode == .bitmap ? "one-bit black and white pixels." : "palette indices and transparent color.")
    }
    if mode == .multichannel, photoshopFormat != nil {
      explanation.stringValue = "Preserves numeric ink and alpha samples, channel names and spot display settings. PSD stores display colors at16-bit precision and solidity in whole percentages."
    }
    if let panel {
      let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
      panel.nameFieldStringValue = base + "." + format.rawValue
    }
  }
}

@MainActor extension CraftNSDocument {
  var revertSourceURL: URL? { fileURL ?? importedSourceURL }
  var canRunFileCommand: Bool {
    ownerController?.recoveryIndex.isBusy != true && recoverySourceStatus != .checking && !recoveryWriteBusy && !fileOperationBusy && copyPanel == nil && !store.geometryBusy
      && !store.aiBusy
      && !store.hasToneDraft && store.transformDraft == nil && !store.coalescingChanges
      && store.pathGesture == nil && store.geometrySheet == nil && !store.showFeatherSelection
      && store.patternNameDraft == nil && store.gradientNameDraft == nil && !store.showAI
      && !store.showImagePlayground && store.error == nil
      && windowForSheet?.attachedSheet == nil && NSApp?.modalWindow == nil
  }
  var canRevertDocument: Bool { revertSourceURL != nil && canRunFileCommand }

  /// Encodes the same snapshot as API file downloads; the copy never takes ownership
  /// of the document, clears its dirty state, or alters its history.
  func copyDocument(
    to url: URL, format: DocumentIO.Format, allowReplacingSource: Bool = false,
    options: RasterEncodingOptions = .init(), interactiveCompatibility: Bool = false,
    encoder: DocumentIO.Encoder? = nil
  ) async throws {
    guard canRunFileCommand else {
      throw CraftError.invalid("Finish the current document operation.")
    }
    guard url.isFileURL else { throw CraftError.invalid("Choose a local file for the copy.") }
    try options.validate(for: format.contentType)
    if !allowReplacingSource, let source = revertSourceURL {
      let sourcePath = source.standardizedFileURL.resolvingSymlinksInPath()
      let targetPath = url.standardizedFileURL.resolvingSymlinksInPath()
      let a = try? source.resourceValues(forKeys: [.fileResourceIdentifierKey])
        .fileResourceIdentifier
      let b = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
      let sameResource =
        (a as? NSObject).flatMap { first in
          (b as? NSObject).map { first.isEqual($0) }
        } ?? false
      guard sourcePath != targetPath, !sameResource else {
        throw CraftError.invalid("Choose a different file for Save a Copy.")
      }
    }
    store.finishNumericField()
    store.finishLayerName()
    let snapshot = store.document
    let outputSnapshot = try store.documentWithPrintSettings(snapshot, format: format)
    let source = revertSourceURL
    let generation = store.layerPanelGeneration
    fileOperationBusy = true
    defer {
      fileOperationBusy = false
      preparedSaveOutput = nil
    }
    let effectiveOptions = try await fileOperationEncodingOptions(options, format: format, document: snapshot,
      destination: url, persistence: false, interactive: interactiveCompatibility)
    guard store.document == snapshot, store.layerPanelGeneration == generation,
      revertSourceURL == source else { throw DocumentSaveConflict.changed }
    let worker = Task.detached(priority: .userInitiated) {
      try DocumentIO.prepareOutput(outputSnapshot, format: format, persistence: false, options: effectiveOptions, encoder: encoder)
    }
    let output = try await withTaskCancellationHandler(
      operation: { try await worker.value }, onCancel: { worker.cancel() })
    try Task.checkCancellation()
    guard store.layerPanelGeneration == generation, store.document == snapshot,
      revertSourceURL == source
    else {
      throw CraftError.invalid(
        "The document changed while preparing the copy. Save the copy again.")
    }
    // A Save panel grants access to its destination, not arbitrary siblings.
    // Let AppKit provide the coordinated safe-write location, as for Save As.
    // Save To preserves this document's association, dirty state and history.
    let hidden = try Self.destinationHiddenFlag(url)
    preparedSaveOutput = (format.typeIdentifier, output, hidden)
    try await writePreparedDocument(to: url, type: format.typeIdentifier, operation: .saveToOperation)
  }

  /// Reload only this document's associated file, keeping the previous edit in history.
  /// API callers add session/share checks and tighter decode limits via these closures.
  func revertDocument(
    reader: @escaping @Sendable (URL) throws -> CraftDocument = DocumentIO.read,
    validate: (CraftDocument) throws -> Void = { _ in }
  ) async throws {
    guard canRevertDocument, let source = revertSourceURL else {
      throw CraftError.invalid(
        "Open or save a document and finish the current operation before reverting.")
    }
    store.finishNumericField()
    store.finishLayerName()
    let original = store.document
    let generation = store.layerPanelGeneration
    fileOperationBusy = true
    defer { fileOperationBusy = false }
    let worker = Task.detached(priority: .userInitiated) {
      try RecoverySourceReader.withStableMetadata {
        let identity = try? RecoverySourceReader(source)
        let saved = try reader(source)
        let format = DocumentIO.sourceFormat(source)
        return (saved, try identity?.finish(), format)
      }
    }
    let (saved, fingerprint, sourceFormat) = try await withTaskCancellationHandler(
      operation: { try await worker.value }, onCancel: { worker.cancel() })
    try Task.checkCancellation()
    guard generation == store.layerPanelGeneration, source == revertSourceURL,
      original == store.document, !store.geometryBusy, !store.aiBusy,
      store.transformDraft == nil, !store.hasToneDraft, !store.coalescingChanges,
      store.numericEditor == nil, store.layerNameDraft == nil, store.pathGesture == nil,
      windowForSheet?.attachedSheet == nil, NSApp?.modalWindow == nil
    else { throw DocumentPersistenceConflict.changed }
    try validate(saved)
    let prepared = try PreparedEdit(restoring: saved, over: original)
    store.session.endCoalescing()
    try store.session.executePrepared(prepared)
    store.layerVisibilityDraft = nil
    store.layerVisibilityIsolation = nil
    store.componentTarget = .composite; store.modeComponentTargets = []; store.modeComponentVisibility = nil
    store.channelView = RGBChannelView()
    store.clearMaskView()
    store.maskEditingLayerID = nil
    store.selectedLayerIDs = Set(store.document.activeLayerID.map { [$0] } ?? [])
    resetRecoverySource()
    if let fingerprint, let sourceFormat, fileURL != nil {
      sourceSaveNeedsReview = Self.formatNeedsReview(saved, format: sourceFormat)
      recoverySourceRecord = .make(url: source, format: sourceFormat,
        needsReview: sourceSaveNeedsReview, fingerprint: fingerprint)
      fileModificationDate = try? source.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
    }
    updateChangeCount(.changeCleared)
    store.render()
    store.status = "Revert"
  }

  func showSaveCopy() {
    guard canRunFileCommand else { return }
    guard !dialogCopyFormats.isEmpty else { explainUnavailableSaveFormats(); return }
    store.finishNumericField()
    store.finishLayerName()
    let panel = NSSavePanel()
    panel.title = "Save a Copy"
    panel.nameFieldStringValue =
      (revertSourceURL?.deletingPathExtension().lastPathComponent
        ?? store.document.name) + " copy." + DocumentIO.Format.native.rawValue
    panel.directoryURL = revertSourceURL?.deletingLastPathComponent()
    panel.canCreateDirectories = true
    let initial = persistenceFormat
    let accessory = DocumentCopyAccessory(panel: panel, initial: initial,
      availableFormats: dialogCopyFormats, initialOptions: compatibleRememberedEncodingOptions,
      uncompressedPhotoshopDefault: fileHandlingPreferences.disablePSDCompression
        && store.document.depth != .u8, depth: store.document.depth, mode: store.document.colorMode,
      documentIsUntagged: store.document.profileIsUntagged == true, width: store.document.width, height: store.document.height)
    panel.accessoryView = accessory.view
    copyPanel = panel
    let finish: (NSApplication.ModalResponse) -> Void = { [weak self, accessory] response in
      guard let self else { return }
      self.copyPanel = nil
      guard response == .OK, let url = panel.url else { return }
      self.fileOperationTask = Task { [weak self] in
        guard let self else { return }
        defer { self.fileOperationTask = nil }
        do {
          try await self.copyDocument(to: url, format: accessory.format, allowReplacingSource: true,
            options: accessory.encodingOptions, interactiveCompatibility: true)
        } catch is CancellationError {
        } catch let error as CocoaError where error.code == .userCancelled {
        } catch { self.store.error = error.localizedDescription }
      }
    }
    if let window = windowForSheet {
      panel.beginSheetModal(for: window, completionHandler: finish)
    } else {
      finish(panel.runModal())
    }
  }

  func showRevert() {
    guard canRevertDocument else { return }
    let alert = NSAlert()
    alert.messageText =
      "Revert to the last saved version of “\(displayName ?? store.document.name)”?"
    alert.informativeText = "Your current changes will be replaced. You can undo Revert."
    alert.addButton(withTitle: "Revert")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    fileOperationTask = Task { [weak self] in
      guard let self else { return }
      defer { self.fileOperationTask = nil }
      do { try await self.revertDocument() } catch is CancellationError {} catch {
        self.store.error = error.localizedDescription
      }
    }
  }
}
