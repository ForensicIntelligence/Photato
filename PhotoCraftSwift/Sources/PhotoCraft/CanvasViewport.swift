import Foundation
import PhotoCraftCore

/// Display geometry only: zoom is backing pixels per image pixel; pan is in AppKit points.
struct CanvasViewport {
  static let minimumZoom = 0.0001
  static let maximumZoom = 32.0
  // PhotoCraft canvas.rs, MIT OR Apache-2.0. Keep Float arithmetic for the source step thresholds.
  static let steps: [Float] = [
    0.0001, 0.0002, 0.0005, 0.001, 0.002, 0.0033, 0.005, 0.0067, 0.01, 0.02, 0.03, 0.05, 0.0667, 0.1, 0.125, 0.1667, 0.25, 0.333, 0.5, 0.6667,
    1, 2, 3, 4, 5, 6, 8, 12, 16, 32,
  ]
  var documentSize: CGSize
  var size: CGSize
  var backingScale: Double
  var zoom: Double
  var pan: CGSize

  static func bounded(_ value: Double) -> Double {
    value.isFinite ? min(maximumZoom, max(minimumZoom, value)) : 1
  }
  static func step(from value: Double, inward: Bool) -> Double {
    let current = Float(bounded(value))
    return Double(
      inward
        ? steps.first(where: { $0 > current * 1.001 }) ?? 32
        : steps.reversed().first(where: { $0 < current * 0.999 }) ?? Float(minimumZoom))
  }
  var backing: Double { backingScale.isFinite && backingScale > 0 ? backingScale : 1 }
  var fitZoom: Double {
    Self.bounded(
      min(
        max(1, size.width - 40) * backing / max(1, documentSize.width),
        max(1, size.height - 40) * backing / max(1, documentSize.height)))
  }
  var resolvedZoom: Double { zoom > 0 ? Self.bounded(zoom) : min(1, fitZoom) }
  var scale: Double { resolvedZoom / backing }
  var largeCanvasRequest: (region: IntRect, width: Int, height: Int) {
    let a = documentPoint(at: .zero), b = documentPoint(at: CGPoint(x: size.width, y: size.height))
    let x0 = max(0, min(Int(documentSize.width) - 1, Int(floor(a.x))))
    let y0 = max(0, min(Int(documentSize.height) - 1, Int(floor(a.y))))
    let x1 = max(x0 + 1, min(Int(documentSize.width), Int(ceil(b.x))))
    let y1 = max(y0 + 1, min(Int(documentSize.height), Int(ceil(b.y))))
    let region = IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    let scale = min(1, resolvedZoom, sqrt(4_194_304 / Double(region.width * region.height)))
    return (region, max(1, Int(floor(Double(region.width) * scale))), max(1, Int(floor(Double(region.height) * scale))))
  }
  var imageRect: CGRect {
    let width = documentSize.width * scale
    let height = documentSize.height * scale
    return CGRect(
      x: (size.width - width) / 2 + pan.width,
      y: (size.height - height) / 2 + pan.height, width: width, height: height)
  }
  func documentPoint(at point: CGPoint) -> CGPoint {
    CGPoint(x: (point.x - imageRect.minX) / scale, y: (point.y - imageRect.minY) / scale)
  }
  func pan(for newZoom: Double, anchoredAt point: CGPoint) -> CGSize {
    let documentPoint = documentPoint(at: point)
    let scale = Self.bounded(newZoom) / backing
    return CGSize(
      width: point.x - size.width / 2 + (documentSize.width / 2 - documentPoint.x) * scale,
      height: point.y - size.height / 2 + (documentSize.height / 2 - documentPoint.y) * scale)
  }
  static func percentage(_ zoom: Double) -> String {
    (bounded(zoom) * 100).formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
      + "%"
  }
  static func parsePercentage(_ text: String, locale: Locale = .current) -> Double? {
    var number = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if number.hasSuffix("%") { number.removeLast() }
    number = number.trimmingCharacters(in: .whitespacesAndNewlines)
    if let separator = locale.decimalSeparator, separator != "." {
      number = number.replacingOccurrences(of: separator, with: ".")
    }
    guard let percent = Double(number), percent.isFinite,
      percent >= minimumZoom * 100, percent <= maximumZoom * 100
    else { return nil }
    return percent / 100
  }
}

extension EditorStore {
  var viewport: CanvasViewport {
    CanvasViewport(
      documentSize: CGSize(width: document.width, height: document.height),
      size: viewportSize, backingScale: viewportBackingScale, zoom: zoom, pan: pan)
  }
  var effectiveZoom: Double { viewport.resolvedZoom }
  func updateViewport(size: CGSize, backingScale: Double) {
    let priorScale = min(1, effectiveZoom)
    let priorSize = viewportSize
    if viewportSize != size { viewportSize = size }
    let backing = backingScale.isFinite && backingScale > 0 ? backingScale : 1
    if viewportBackingScale != backing {
      let ratio = viewport.backing / backing
      pan = CGSize(width: pan.width * ratio, height: pan.height * ratio)
      viewportBackingScale = backing
    }
    // Initial fit is resolved once. Panel visibility and window resize do not silently change zoom.
    if zoom == 0 { zoom = viewport.resolvedZoom }
    if measuredZoom != effectiveZoom { measuredZoom = effectiveZoom }
    // The initial render may still be preparing a different fit scale. Replace
    // it now so the first visible preview and first edit use this viewport.
    if priorScale != min(1, effectiveZoom) || (priorSize != size && document.width * document.height > Surface.maximumDensePixels) { render() }
  }
  func setZoom(_ value: Double, anchoredAt point: CGPoint? = nil, center: Bool = false) {
    let priorScale = min(1, effectiveZoom)
    let next = CanvasViewport.bounded(value)
    pan =
      center
      ? .zero
      : viewport.pan(
        for: next,
        anchoredAt: point ?? CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2))
    zoom = next
    measuredZoom = next
    if priorScale != min(1, effectiveZoom) { render() }
  }
  func stepZoom(inward: Bool, anchoredAt point: CGPoint? = nil) {
    setZoom(CanvasViewport.step(from: effectiveZoom, inward: inward), anchoredAt: point)
  }
}
