import AppKit
import PhotoCraftCore
import PhotoCraftImaging

struct SkyPreviewTile: Sendable {
  let request: RasterPreviewRequest
  let image: CGImage
  let mask: CGImage?
}

struct SkyViewportContent: Equatable {
  let generation: Int
  let replacement: Bool
  let mask: Bool
}

struct SkyViewportPlan: Equatable {
  let content: SkyViewportContent
  let requests: [RasterPreviewRequest]

  static let tileSide = 1024
  static let maximumTiles = 256

  /// Tiles follow a document-anchored grid. A pan reuses matching visible tiles;
  /// a large Retina viewport does not stretch one globally downsampled buffer.
  static func requests(for viewport: CanvasViewport) throws -> [RasterPreviewRequest] {
    guard viewport.size.width.isFinite, viewport.size.height.isFinite,
      viewport.size.width > 0, viewport.size.height > 0,
      viewport.pan.width.isFinite, viewport.pan.height.isFinite else { return [] }
    let visible = CGRect(origin: .zero, size: viewport.size).intersection(viewport.imageRect)
    guard !visible.isNull, !visible.isEmpty else { return [] }
    let a = viewport.documentPoint(at: visible.origin)
    let b = viewport.documentPoint(at: CGPoint(x: visible.maxX, y: visible.maxY))
    let width = Int(viewport.documentSize.width), height = Int(viewport.documentSize.height)
    let x0 = max(0, min(width - 1, Int(floor(a.x))))
    let y0 = max(0, min(height - 1, Int(floor(a.y))))
    let x1 = max(x0 + 1, min(width, Int(ceil(b.x))))
    let y1 = max(y0 + 1, min(height, Int(ceil(b.y))))
    let side = max(1, Int(floor(Double(tileSide) / viewport.resolvedZoom)))
    let firstX = x0 / side * side, firstY = y0 / side * side
    let columns = (x1 - firstX + side - 1) / side
    let rows = (y1 - firstY + side - 1) / side
    guard columns <= maximumTiles / rows else {
      throw CraftError.invalid("The visible sky preview exceeds 256 tiles. Reduce the window size or zoom in.")
    }
    let density = min(1, viewport.resolvedZoom)
    var requests: [RasterPreviewRequest] = []
    for y in stride(from: firstY, to: y1, by: side) {
      for x in stride(from: firstX, to: x1, by: side) {
        let region = IntRect(x: x, y: y, width: min(side, width - x), height: min(side, height - y))
        requests.append(try RasterPreviewRequest(region: region,
          width: max(1, min(tileSide, min(region.width, Int(ceil(Double(region.width) * density))))),
          height: max(1, min(tileSide, min(region.height, Int(ceil(Double(region.height) * density)))))))
      }
    }
    return requests
  }
}

@MainActor extension SkyWorkspace {
  var canNavigate: Bool { !closed && !committing && viewportSize.width > 0 && viewportSize.height > 0 }
  var viewport: CanvasViewport {
    CanvasViewport(documentSize: CGSize(width: original.width, height: original.height),
      size: viewportSize, backingScale: viewportBackingScale, zoom: zoom, pan: pan)
  }
  var effectiveZoom: Double { viewport.resolvedZoom }
  var zoomLabel: String { CanvasViewport.percentage(effectiveZoom) }
  var viewportState: [String: Any] {
    ["zoom":effectiveZoom,"fitZoom":viewport.fitZoom,"width":viewportSize.width,"height":viewportSize.height,
      "backingScale":viewportBackingScale,"panX":pan.width,"panY":pan.height,"canNavigate":canNavigate,
      "detailBusy":detailBusy,"detailSource":!showOriginal && outputSurface != nil ? "replacement":"original",
      "showMask":showMask,"requestedTiles":detailPlan?.requests.count ?? 0,
      "visibleTiles":detailTiles.map{tile in let r=tile.request.region
        return ["x":r.x,"y":r.y,"width":r.width,"height":r.height,"displayWidth":tile.image.width,"displayHeight":tile.image.height]},
      "detailError":detailError as Any? ?? NSNull()]
  }
  func updateViewport(size: CGSize, backingScale: Double) {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
    let backing = backingScale.isFinite && backingScale > 0 ? backingScale : 1
    guard size != viewportSize || backing != viewportBackingScale else { return }
    updatingViewport = true
    pan = CGSize(width: pan.width * viewportBackingScale / backing,
      height: pan.height * viewportBackingScale / backing)
    viewportSize = size; viewportBackingScale = backing
    if zoom == 0 { zoom = viewport.resolvedZoom }
    updatingViewport = false; scheduleDetail()
  }
  func setZoom(_ value: Double, anchoredAt point: CGPoint? = nil, center: Bool = false) {
    guard canNavigate else { return }
    let next = CanvasViewport.bounded(value)
    updatingViewport = true
    pan = center ? .zero : viewport.pan(for: next,
      anchoredAt: point ?? CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2))
    zoom = next; updatingViewport = false; scheduleDetail()
  }
  func fitViewport() { setZoom(viewport.fitZoom, center: true) }
  func stepZoom(inward: Bool, anchoredAt point: CGPoint? = nil) {
    setZoom(CanvasViewport.step(from: effectiveZoom, inward: inward), anchoredAt: point)
  }
  func invalidateDetail() {
    detailSequence += 1; detailTask?.cancel(); detailTask = nil
    detailPlan = nil; detailTiles = []; detailBusy = false; detailError = nil
  }
  func scheduleDetail() {
    guard !updatingViewport else { return }
    guard canNavigate, let input,
      original.width > SkyReplacement.denseMaximumPixels / original.height,
      viewportSize.width > 0, viewportSize.height > 0,
      effectiveZoom > min(1, 2048 / Double(max(original.width, original.height))) else {
      if detailPlan != nil || !detailTiles.isEmpty || detailBusy { invalidateDetail() }
      return
    }
    let replacement = !showOriginal && outputSurface != nil
    let content = SkyViewportContent(generation: generation, replacement: replacement, mask: showMask && mask != nil)
    let plan: SkyViewportPlan
    do { plan = SkyViewportPlan(content: content, requests: try SkyViewportPlan.requests(for: viewport)) }
    catch { invalidateDetail(); detailError = error.localizedDescription; return }
    guard detailPlan != plan else { return }
    let reusable = detailPlan?.content == content ? detailTiles.filter { tile in plan.requests.contains(tile.request) } : []
    detailSequence += 1; let sequence = detailSequence
    detailTask?.cancel(); detailPlan = plan; detailTiles = reusable; detailError = nil
    let missing = plan.requests.filter { request in !reusable.contains { $0.request == request } }
    detailBusy = !missing.isEmpty
    guard !missing.isEmpty else { detailTask = nil; return }
    let source = (replacement ? outputSurface : nil) ?? input.composite
    // Replacement preserves the original dimensions/depth/working profile.
    let document = original
    let coverage = content.mask ? mask : nil
    detailTask = Task { [weak self] in
      do {
        for request in missing {
          try Task.checkCancellation()
          let worker = Task.detached(priority: .userInitiated) {
            let image = try SkyReplacementInput.display(source, in: document, request: request)
            let overlay = try SelectionToolPreparation.overlay(coverage, color: Pixel(1, 0, 0, 0.55), request: request)
            try Task.checkCancellation()
            return SkyPreviewTile(request: request, image: image, mask: overlay)
          }
          let tile = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
          try Task.checkCancellation()
          guard let self, !self.closed, self.detailSequence == sequence, self.detailPlan == plan else { return }
          self.detailTiles.append(tile)
        }
      } catch {
        if let self, !self.closed, self.detailSequence == sequence, !Task.isCancelled {
          self.detailError = error.localizedDescription
        }
      }
      if let self, self.detailSequence == sequence { self.detailBusy = false }
    }
  }
}
