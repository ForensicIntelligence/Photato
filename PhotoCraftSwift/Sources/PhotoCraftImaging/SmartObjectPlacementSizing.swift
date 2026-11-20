import Foundation
import PhotoCraftCore

public enum SmartObjectPlacementSizing: String, Codable, CaseIterable, Sendable {
  case pixels
  case physical

  func center(_ layer: inout Layer, source: SmartObject, in parent: CraftDocument, fit: Bool) throws {
    let sourceWidth = Double(source.width), sourceHeight = Double(source.height)
    let canvasWidth = Double(parent.width), canvasHeight = Double(parent.height)
    let ppi = parent.pixelsPerInch
    var scaleX = 1.0, scaleY = 1.0
    if self == .physical {
      guard ppi.isFinite, (1...100_000).contains(ppi) else {
        throw CraftError.invalid("The document has an invalid print resolution.")
      }
      if let page = source.pdfSource, page.image == nil {
        // PDF page boxes are specified in points. Use their actual extent rather
        // than deriving the physical size from an integer-sized render cache.
        scaleX = (page.width * ppi / 72) / sourceWidth
        scaleY = (page.height * ppi / 72) / sourceHeight
      } else {
        scaleX = ppi / source.resolution
        scaleY = scaleX
      }
    }
    if fit {
      if scaleX == scaleY {
        let scale = min(scaleX, canvasWidth / sourceWidth, canvasHeight / sourceHeight)
        scaleX = scale
        scaleY = scale
      } else {
        let reduction = min(1, canvasWidth / (sourceWidth * scaleX), canvasHeight / (sourceHeight * scaleY))
        scaleX *= reduction
        scaleY *= reduction
      }
    }
    let x = ((canvasWidth - sourceWidth * scaleX) / 2).rounded(.towardZero)
    let y = ((canvasHeight - sourceHeight * scaleY) / 2).rounded(.towardZero)
    guard let x = Int(exactly: x), let y = Int(exactly: y) else {
      throw CraftError.invalid("The artwork’s placement is out of range.")
    }
    let transform = Transform2D(a: scaleX, d: scaleY, tx: Double(x), ty: Double(y))
    try transform.validated()
    layer.x = x
    layer.y = y
    layer.affine = .scale(scaleX, scaleY)
  }
}
