import Foundation

public enum LayerViaOperation: String, Sendable, CaseIterable {
  case copy = "Layer Via Copy"
  case cut = "Layer Via Cut"
}

/// Selection extraction measured against original Photoshop 2026 RGB/8, /16 and /32 probes.
/// This is deliberately separate from clipboard Copy/Cut, whose pixel semantics differ.
public enum LayerVia {
  public static func canApply(to layer: Layer, in document: CraftDocument) -> Bool {
    guard document.selection != nil, document.layers.count < 512,
      !document.isLocked(layer.id), layer.affine == nil, !layer.isClipped,
      layer.vectorMask == nil, case .raster = layer.content
    else { return false }
    return true
  }

  /// Alpha extraction uses byte coverage even in high-depth documents. Removal uses
  /// a byte ratio and the document's arithmetic; ordinary alpha multiplication is not equivalent.
  public static func alpha(source: Float, selection: UInt8, depth: PixelDepth)
    -> (copied: Float, remaining: Float)
  {
    let a = Int((unit(source) * 255).rounded())
    let s = Int(selection)
    let lo = min(a, s)
    let hi = max(a, s)
    let t = (lo * (255 - hi) + 127) / 255
    let copied = lo - (t * (hi - lo) + 127) / 255
    let removal = a == 0 ? 0 : (copied * 255 + a / 2) / a
    switch depth {
    case .u8:
      return (Float(copied) / 255, Float((a * (255 - removal) + 127) / 255) / 255)
    case .u16:
      let working = Int((Double(unit(source)) * 32768).rounded())
      let copy16 = (copied * 32768 + 127) / 255
      let removal16 = (removal * 32768 + 127) / 255
      let remaining16 = (working * (32768 - removal16) + 16384) / 32768
      func stored(_ value: Int) -> Float {
        Float((value * 65535 + 16384) / 32768) / 65535
      }
      return (stored(copy16), stored(remaining16))
    case .f32:
      let reciprocal: Float = 1 / 255
      let coverage = Float(removal) * reciprocal
      let remainingCoverage: Float = 1 - coverage
      return (Float(copied) * reciprocal, source * remainingCoverage)
    }
  }

  static func apply(_ operation: LayerViaOperation, layerID: UUID, to document: inout CraftDocument)
    throws
  {
    try document.validate()
    guard let index = document.layers.firstIndex(where: { $0.id == layerID }),
      canApply(to: document.layers[index], in: document), let selection = document.selection,
      case .raster(let source) = document.layers[index].content
    else {
      throw CraftError.unsupported(
        "Select pixels on one unlocked, untransformed pixel layer. Clipped layers and vector masks are not supported by Layer Via yet."
      )
    }
    let original = document.layers[index]
    let left = max(selection.x, original.x)
    let top = max(selection.y, original.y)
    let right = min(selection.x + selection.width, original.x + source.width)
    let bottom = min(selection.y + selection.height, original.y + source.height)
    guard right > left, bottom > top else {
      throw CraftError.invalid(
        "Could not complete the \(operation.rawValue) command because the selected area is empty.")
    }
    var extracted = try Surface(width: right - left, height: bottom - top, depth: document.depth)
    var remaining = source
    for y in top..<bottom {
      try Task.checkCancellation()
      for x in left..<right {
        let coverage = document.selectionMask?.byte(at:y * document.width + x) ?? 255
        var pixel = source.pixel(x: x - original.x, y: y - original.y)
        let result = alpha(source: pixel.a, selection: coverage, depth: document.depth)
        if operation == .cut && coverage > 0 {
          var retained = pixel
          retained.a = result.remaining
          // Photoshop clears hidden color to white when removal makes a pixel transparent.
          if result.remaining == 0 { retained = Pixel(1, 1, 1, 0) }
          remaining.setPixel(x: x - original.x, y: y - original.y, retained)
        }
        pixel.a = result.copied
        extracted.setPixel(x: x - left, y: y - top, pixel)
      }
    }
    guard let bounds = try extracted.contentBounds() else {
      throw CraftError.invalid(
        "Could not complete the \(operation.rawValue) command because the selected area is empty.")
    }
    var candidate = document
    if operation == .cut {
      candidate.layers[index].content = .raster(remaining)
      if let native = original.nativeMode {
        candidate.layers[index].nativeMode = try native.reconciled(with: remaining, previous: source)
      }
      try LayerLayout.trimMovedRaster(&candidate.layers[index])
    }
    var number = 1
    let names = Set(document.layers.map(\.name))
    while names.contains("Layer \(number)") { number += 1 }
    var layer = Layer(name: "Layer \(number)", content: .raster(try extracted.cropped(to: bounds)))
    layer.x = left + bounds.x
    layer.y = top + bounds.y
    layer.parentID = original.parentID
    layer.opacity = original.opacity
    layer.blendMode = original.blendMode
    if let native = original.nativeMode {
      var retained = try native.cropped(to: IntRect(x: left - original.x + bounds.x,
        y: top - original.y + bounds.y, width: bounds.width, height: bounds.height))
      for y in 0..<bounds.height { try Task.checkCancellation(); for x in 0..<bounds.width {
        try retained.set(extracted.pixel(x: bounds.x + x, y: bounds.y + y).a,
          component: retained.mode.componentCount, index: y * bounds.width + x)
      } }
      layer.nativeMode = retained; layer.content = .raster(try retained.surface())
    }
    candidate.layers.insert(layer, at: index + 1)
    candidate.activeLayerID = layer.id
    candidate.selection = nil
    candidate.selectionMask = nil
    try candidate.reconcileModeStorage(from: document)
    try candidate.validate()
    try Task.checkCancellation()
    document = candidate
  }
}
