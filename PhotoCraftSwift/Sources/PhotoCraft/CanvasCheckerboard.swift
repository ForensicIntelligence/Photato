import AppKit

/// Cache the viewport's transparency decoration. Its many small rectangles only
/// need rebuilding when zoom, pan, backing scale or viewport geometry changes.
@MainActor final class CanvasCheckerboard {
  private struct Key: Equatable {
    let viewport: CGRect
    let image: CGRect
    let cell: CGFloat
    let backing: CGFloat
  }
  private var key: Key?
  private var image: CGImage?
  private(set) var rebuildCount = 0

  func draw(in context: CGContext, viewport: CGRect, imageRect: CGRect, cell: CGFloat, backing: CGFloat) {
    let next = Key(viewport: viewport, image: imageRect, cell: cell, backing: max(1, backing))
    if key != next || image == nil {
      let width = Int(ceil(viewport.width * next.backing)), height = Int(ceil(viewport.height * next.backing))
      guard width > 0, height > 0, width <= 16_777_216 / height,
        let buffer = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { Self.paint(in: context, viewport: viewport, imageRect: imageRect, cell: cell); return }
      buffer.translateBy(x: 0, y: CGFloat(height)); buffer.scaleBy(x: next.backing, y: -next.backing)
      buffer.translateBy(x: -viewport.minX, y: -viewport.minY)
      Self.paint(in: buffer, viewport: viewport, imageRect: imageRect, cell: cell)
      image = buffer.makeImage(); key = next; rebuildCount += 1
    }
    guard let image else { return }
    context.saveGState(); context.interpolationQuality = .none
    context.translateBy(x: viewport.minX, y: viewport.maxY); context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(origin: .zero, size: viewport.size)); context.restoreGState()
  }
  static func paint(in c: CGContext, viewport: CGRect, imageRect r: CGRect, cell: CGFloat) {
    c.saveGState(); defer { c.restoreGState() }
    c.clip(to: viewport); c.clip(to: r)
    c.setFillColor(NSColor(calibratedWhite: 0.77, alpha: 1).cgColor); c.fill(r)
    c.setFillColor(NSColor.white.cgColor)
    let visible = r.intersection(viewport)
    guard !visible.isNull, visible.width > 0, visible.height > 0 else { return }
    for row in Int(floor((visible.minY - r.minY) / cell))...Int(ceil((visible.maxY - r.minY) / cell)) {
      for column in Int(floor((visible.minX - r.minX) / cell))...Int(ceil((visible.maxX - r.minX) / cell)) where (row + column) % 2 == 0 {
        c.fill(CGRect(x: r.minX + CGFloat(column) * cell, y: r.minY + CGFloat(row) * cell, width: cell, height: cell))
      }
    }
  }
}
