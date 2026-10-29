import CoreGraphics
import Foundation
import PhotoCraftCore

/// Adobe's public PSD layout; numerical CMYK inversion is independently cross-checked
/// with the MIT-licensed psd-tools reader. No proprietary Adobe code is used.
enum PSDModeStorage {
  static func mode(_ code: Int) throws -> DocumentColorMode {
    switch code {
    case 1: return .grayscale
    case 3: return .rgb
    case 4: return .cmyk
    case 9: return .lab
    default: throw CraftError.unsupported("This Photoshop color mode is not implemented yet.")
    }
  }
  static func code(_ mode: DocumentColorMode) -> Int {
    switch mode { case .grayscale: 1; case .rgb: 3; case .cmyk: 4; case .lab: 9; case .indexed: 2; case .bitmap: 0; case .duotone: 8; case .multichannel: 7 }
  }
  static func sample(_ value: Float, mode: DocumentColorMode, component: Int) -> Float {
    mode == .cmyk && component < mode.componentCount ? 1 - value : value
  }
  static func profile(_ source: Data?, mode: DocumentColorMode, depth: PixelDepth) throws -> Data {
    guard let source else { return try NativeModeProfile.standard(mode, depth: depth) }
    if depth == .f32 {
      try NativeModeProfile.validate(source, mode: mode, depth: .u16)
      if (try? NativeModeProfile.validate(source, mode: mode, depth: .f32)) != nil { return source }
      guard let space = CGColorSpace(iccData: source as CFData), let linear = CGColorSpaceCreateLinearized(space),
        let profile = linear.copyICCData() as Data? else {
        throw CraftError.unsupported("The embedded 32-bit mode profile cannot be linearized.")
      }
      try NativeModeProfile.validate(profile, mode: mode, depth: depth); return profile
    }
    try NativeModeProfile.validate(source, mode: mode, depth: depth); return source
  }
  static func validateExport(_ document: CraftDocument) throws {
    guard document.hasNativeModeStorage else { return }
    for layer in document.layers {
      guard layer.smartObject == nil, layer.smartFilters == nil else {
        throw CraftError.unsupported("Rasterize or merge Smart Objects/Filters before exporting native color-mode PSD/PSB.")
      }
      switch layer.content {
      case .raster, .group: break
      default: throw CraftError.unsupported("Rasterize or merge live layers before exporting native color-mode PSD/PSB.")
      }
    }
  }
  static func mergedSample(_ native: NativeModeRaster, component: Int, index: Int) -> Float {
    let value = native.value(component: component, index: index)
    let alpha = native.value(component: native.mode.componentCount, index: index)
    if native.mode == .rgb || native.mode == .grayscale {
      let p = Pixel(value, value, value, alpha)
      let m = native.depth == .f32 ? PSDMergedSample.encodeLinear(p) : PSDMergedSample.encode(p, depth: native.depth == .u8 ? 8 : 16)
      return component == native.mode.componentCount ? m.a : m.r
    }
    // CMYK/Lab merged channels remain straight; alpha is never inverted.
    return sample(value, mode: native.mode, component: component)
  }
}
