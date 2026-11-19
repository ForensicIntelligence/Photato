import AppKit
import PhotoCraftCore
import PhotoCraftImaging

enum PhotoshopCompatibilityPreference: String, Codable, CaseIterable {
  case always, ask, never
}

extension RecoveryPreferences {
  /// The application preference supplies defaults. Photato's explicit output
  /// options remain authoritative and are never replaced by ambient state.
  func encodingOptions(_ requested: RasterEncodingOptions, format: DocumentIO.Format,
    document: CraftDocument) -> RasterEncodingOptions {
    guard format == .psd || format == .psb else { return requested }
    var result = requested
    if disablePSDCompression, document.depth != .u8 {
      if result.psdLayerCompression == nil { result.psdLayerCompression = .raw }
      if result.psdCompositeCompression == nil { result.psdCompositeCompression = .raw }
    }
    if result.psdMaximizeCompatibility == nil, maximizePSDCompatibility == .never,
      PSDCodec.canOmitMergedImage(document) {
      result.psdMaximizeCompatibility = false
    }
    return result
  }

  func shouldAskPhotoshopCompatibility(_ options: RasterEncodingOptions, format: DocumentIO.Format,
    document: CraftDocument) -> Bool {
    maximizePSDCompatibility == .ask && options.psdMaximizeCompatibility == nil
      && (format == .psd || format == .psb) && PSDCodec.canOmitMergedImage(document)
  }
}

@MainActor extension CraftNSDocument {
  var fileHandlingPreferences: RecoveryPreferences {
    ownerController?.recoveryPreferences.value ?? .init()
  }
  func effectiveEncodingOptions(_ requested: RasterEncodingOptions, format: DocumentIO.Format,
    persistence: Bool = false)
    -> RasterEncodingOptions {
    let options = persistence ? DocumentIO.persistenceOptions(requested, format: format, document: store.document) : requested
    return fileHandlingPreferences.encodingOptions(options, format: format, document: store.document)
  }

  func fileOperationEncodingOptions(_ requested: RasterEncodingOptions, format: DocumentIO.Format,
    document: CraftDocument, destination: URL, persistence: Bool, interactive: Bool) async throws
    -> RasterEncodingOptions {
    let preferences = fileHandlingPreferences
    let options = persistence ? DocumentIO.persistenceOptions(requested, format: format, document: document) : requested
    var effective = preferences.encodingOptions(options, format: format, document: document)
    if interactive && preferences.shouldAskPhotoshopCompatibility(options, format: format, document: document) {
      effective.psdMaximizeCompatibility = try await confirmPhotoshopCompatibility(destination)
    }
    return effective
  }

  private func confirmPhotoshopCompatibility(_ url: URL) async throws -> Bool {
    let alert = NSAlert()
    alert.messageText = "Maximize Compatibility?"
    alert.informativeText = "Include a merged preview so other apps can display “\(url.lastPathComponent)”."
    let option = NSButton(checkboxWithTitle: "Maximize Compatibility", target: nil, action: nil)
    option.state = .on
    option.sizeToFit()
    alert.accessoryView = option
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    let response: NSApplication.ModalResponse
    if let window = windowForSheet {
      response = try await withTaskCancellationHandler {
        try Task.checkCancellation()
        return await withCheckedContinuation { continuation in
          alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
      } onCancel: {
        Task { @MainActor in
          if let parent = alert.window.sheetParent {
            parent.endSheet(alert.window, returnCode: .alertSecondButtonReturn)
          }
        }
      }
    } else {
      response = alert.runModal()
    }
    try Task.checkCancellation()
    guard response == .alertFirstButtonReturn else { throw CocoaError(.userCancelled) }
    return option.state == .on
  }
}

@MainActor extension CraftNSDocument {
  var compatibleRememberedEncodingOptions: [DocumentIO.Format: RasterEncodingOptions] {
    let document = store.document
    return rememberedEncodingOptions.mapValues { options in
      var result = options
      if result.psdMaximizeCompatibility == false, !PSDCodec.canOmitMergedImage(document) {
        result.psdMaximizeCompatibility = nil
      }
      guard document.colorMode.isRestricted else { return result }
      if result.tiffLayers != nil { result.tiffLayers = false }
      result.tiffLayerCompression = nil
      if result.tiffPredictor != nil { result.tiffPredictor = false }
      result.psdLayerCompression = nil
      if store.document.colorMode == .bitmap, result.psdCompositeCompression == .zipPrediction { result.psdCompositeCompression = .zip }
      return result
    }
  }
}
