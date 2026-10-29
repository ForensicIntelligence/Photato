import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension RecoveryPreferences {
  /// The application preference supplies defaults. Photato's explicit output
  /// options remain authoritative and are never replaced by ambient state.
  func encodingOptions(_ requested: RasterEncodingOptions, format: DocumentIO.Format,
    depth: PixelDepth) -> RasterEncodingOptions {
    guard disablePSDCompression, depth != .u8, format == .psd || format == .psb else {
      return requested
    }
    var result = requested
    if result.psdLayerCompression == nil { result.psdLayerCompression = .raw }
    if result.psdCompositeCompression == nil { result.psdCompositeCompression = .raw }
    return result
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
    return fileHandlingPreferences.encodingOptions(options, format: format, depth: store.document.depth)
  }
}

@MainActor extension CraftNSDocument {
  var compatibleRememberedEncodingOptions: [DocumentIO.Format: RasterEncodingOptions] {
    guard store.document.colorMode.isRestricted else { return rememberedEncodingOptions }
    return rememberedEncodingOptions.mapValues { options in
      var result = options
      if result.tiffLayers != nil { result.tiffLayers = false }
      result.tiffLayerCompression = nil
      if result.tiffPredictor != nil { result.tiffPredictor = false }
      result.psdLayerCompression = nil
      if store.document.colorMode == .bitmap, result.psdCompositeCompression == .zipPrediction { result.psdCompositeCompression = .zip }
      return result
    }
  }
}
