import Foundation
import PhotoCraftCore

extension ClipboardRenderer {
  static func copyRestricted(_ document: CraftDocument, layerIDs: Set<UUID>, merged: Bool) throws -> ClipboardContent {
    guard let raster = document.restrictedMode,
      merged || layerIDs == Set(document.activeLayerID.map { [$0] } ?? []) else {
      throw CraftError.invalid("Select the flat image to copy.")
    }
    if document.selection == nil {
      return try .pixels(raster.surface(), resolution: document.pixelsPerInch,
        workingICC: document.workingICC, restrictedSamples: raster)
    }
    let original = try raster.surface()
    let selection = document.selection!.clipped(toWidth: document.width, height: document.height)
    var x0 = document.width, y0 = document.height, x1 = -1, y1 = -1
    if selection.width > 0, selection.height > 0 {
      for y in selection.y..<selection.y + selection.height { try Task.checkCancellation(); for x in selection.x..<selection.x + selection.width {
        if original.pixel(x: x, y: y).a * document.selectionCoverage(x: x, y: y) >= 0.5 / 255 {
          x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
        }
      } }
    }
    guard x1 >= x0, y1 >= y0 else { throw CraftError.invalid("Could not copy because the selected area is empty.") }
    let samples = try RestrictedModeGeometry.transformed(raster, by: .translation(-Double(x0), -Double(y0)), width: x1 - x0 + 1, height: y1 - y0 + 1)
    var pixels = try samples.surface()
    for y in 0..<pixels.height { try Task.checkCancellation(); for x in 0..<pixels.width {
      var p = pixels.pixel(x: x, y: y); p.a *= document.selectionCoverage(x: x + x0, y: y + y0)
      pixels.setPixel(x: x, y: y, p)
    } }
    return try .pixels(pixels, x: x0, y: y0, resolution: document.pixelsPerInch,
      workingICC: document.workingICC, restrictedSamples: samples)
  }
  /// Shared desktop/API preparation for mode-aware paste. The caller decides
  /// whether its input came from the system pasteboard or an explicit payload.
  public static func pasteCommand(_ content: ClipboardContent, into document: CraftDocument,
    placement: PastePlacement = .centered, center: PathPoint? = nil) throws -> Command {
    var input = content
    if document.restrictedMode != nil || placement == .into || placement == .outside { input = try flattened(input) }
    input = try ColorManagement.converted(input, to: document)
    return .paste(input, placement, input.kind == .pixels ? center : nil)
  }
}
