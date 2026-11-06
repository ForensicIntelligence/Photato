import AppKit
import PhotoCraftCore

/// Placement resolves in logical pixels before the existing engine rebases the canvas.
enum ArtboardSide: String, CaseIterable, Sendable { case top, right, bottom, left }
struct ArtboardNeighborRequest: Sendable {
  let layerID: UUID
  let side: ArtboardSide
  var duplicate = false
  var spacing = 100
  var name: String?
  func command(in document: CraftDocument) throws -> Command {
    guard (0...32768).contains(spacing),
      let layer = document.artboards.first(where: { $0.id == layerID }),
      let board = layer.artboard, let source = document.logicalArtboardBounds(layer),
      !document.isLocked(layerID), !duplicate || !document.isPositionLocked(layerID)
    else { throw CraftError.invalid("Choose an available artboard and valid spacing.") }
    var x = source.x, y = source.y
    switch side {
    case .top: y -= source.height + spacing
    case .right: x += source.width + spacing
    case .bottom: y += source.height + spacing
    case .left: x -= source.width + spacing
    }
    let bounds = IntRect(x: x, y: y, width: source.width, height: source.height)
    _ = try LayerLayout.union([bounds])
    let physicalX = x - (document.artboardOrigin?.x ?? 0), physicalY = y - (document.artboardOrigin?.y ?? 0)
    guard max(document.width, physicalX + source.width) - min(0, physicalX) <= Surface.maxDimension,
      max(document.height, physicalY + source.height) - min(0, physicalY) <= Surface.maxDimension
    else { throw CraftError.invalid("Adjacent artboard exceeds the 300,000-pixel canvas extent.") }
    if duplicate { return .artboard(.duplicate(layerID, x: x, y: y, name: name)) }
    return .artboard(.create(name: name ?? "Artboard \(document.artboards.count + 1)",
      bounds: .init(x: x, y: y, width: source.width, height: source.height),
      background: board.background, children: []))
  }
}
struct ArtboardNeighborPress {
  let request: ArtboardNeighborRequest
  let generation: UUID
}
extension EditorStore {
  func addArtboardNeighbor(_ request: ArtboardNeighborRequest) {
    guard canEditArtboards else { return }
    performGeometry(label: request.duplicate ? "Duplicate Artboard" : "New Artboard",
      prepare: { try request.command(in: $0) })
  }
}
extension ToolCursor {
  static func artboardNeighbor(duplicate: Bool, available: Bool) -> ToolCursor {
    available ? .symbol("plus", duplicate ? .copy : nil) : .unavailable
  }
}
extension CraftCanvas {
  func artboardNeighborCenter(_ side: ArtboardSide) -> CGPoint? {
    guard store.tool == .artboard, store.unavailableToolID == nil,
      let rect = store.selectedArtboard?.artboardBounds else { return nil }
    let p = viewPoint(CGPoint(x: rect.x, y: rect.y))
    let box = CGRect(x: p.x, y: p.y, width: Double(rect.width) * scale, height: Double(rect.height) * scale)
    switch side {
    case .top: return CGPoint(x: box.midX, y: box.minY - (store.showArtboardNames ? 36 : 20))
    case .right: return CGPoint(x: box.maxX + 20, y: box.midY)
    case .bottom: return CGPoint(x: box.midX, y: box.maxY + 20)
    case .left: return CGPoint(x: box.minX - 20, y: box.midY)
    }
  }
  func artboardNeighborHit(_ point: CGPoint) -> ArtboardSide? {
    guard visibleRect.contains(point) else { return nil }
    return ArtboardSide.allCases.first { side in
      guard let center = artboardNeighborCenter(side) else { return false }
      return hypot(center.x - point.x, center.y - point.y) <= 10
    }
  }
  var artboardNeighborCursor: ToolCursor? {
    let press = store.artboardNeighborPress
    guard let side = press?.request.side ?? cursorLocationInView.flatMap(artboardNeighborHit),
      let id = press?.request.layerID ?? store.selectedArtboard?.id else { return nil }
    let duplicate = press?.request.duplicate ?? cursorModifiers.contains(.option)
    let request = ArtboardNeighborRequest(layerID: id, side: side, duplicate: duplicate)
    let current = press.map { $0.generation == store.sessionGeneration && store.selectedArtboard?.id == id } ?? store.canEditArtboards
    return .artboardNeighbor(duplicate: duplicate, available: current && (try? request.command(in: store.document)) != nil)
  }
  func beginArtboardNeighbor(_ event: NSEvent) -> Bool {
    guard !spaceHeld, let side = artboardNeighborHit(convert(event.locationInWindow, from: nil)),
      let id = store.selectedArtboard?.id else { return false }
    guard store.canEditArtboards else { return true }
    let request = ArtboardNeighborRequest(layerID: id, side: side, duplicate: event.modifierFlags.contains(.option))
    guard (try? request.command(in: store.document)) != nil else { return true }
    store.artboardNeighborPress = .init(request: request, generation: store.sessionGeneration)
    needsDisplay = true
    return true
  }
  func endArtboardNeighbor(_ event: NSEvent) -> Bool {
    guard let press = store.artboardNeighborPress else { return false }
    store.artboardNeighborPress = nil
    defer { needsDisplay = true }
    guard !spaceHeld, press.generation == store.sessionGeneration, store.tool == .artboard,
      store.unavailableToolID == nil, store.selectedArtboard?.id == press.request.layerID,
      artboardNeighborHit(convert(event.locationInWindow, from: nil)) == press.request.side
    else { return true }
    store.addArtboardNeighbor(press.request)
    return true
  }
  func drawArtboardNeighbors(in context: CGContext) {
    guard store.tool == .artboard, store.selectedArtboard != nil else { return }
    context.saveGState(); defer { context.restoreGState() }
    context.setLineDash(phase: 0, lengths: [])
    for side in ArtboardSide.allCases {
      guard let center = artboardNeighborCenter(side) else { continue }
      let circle = CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)
      guard visibleRect.intersects(circle) else { continue }
      context.setFillColor(NSColor.windowBackgroundColor.cgColor); context.fillEllipse(in: circle)
      context.setStrokeColor(NSColor.controlAccentColor.cgColor); context.setLineWidth(1); context.strokeEllipse(in: circle)
      context.move(to: CGPoint(x: center.x - 4, y: center.y)); context.addLine(to: CGPoint(x: center.x + 4, y: center.y))
      context.move(to: CGPoint(x: center.x, y: center.y - 4)); context.addLine(to: CGPoint(x: center.x, y: center.y + 4)); context.strokePath()
    }
  }
}
