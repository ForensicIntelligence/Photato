import Foundation
import PhotoCraftCore

enum RemoveGenerativeRegions {
  static let maximumSingleSide = 768
  private static let cellSide = 512
  private static let overlap = 48
  static let maximumPredictions = 64

  private struct Cell: Hashable, Comparable {
    let column: Int
    let row: Int
    var group = 0
    static func < (a: Self, b: Self) -> Bool { (a.group, a.row, a.column) < (b.group, b.row, b.column) }
  }

  private struct Group {
    var bounds: IntRect
    var tiles: [IntRect]
  }

  private struct Repair {
    let owned: IntRect
    let region: IntRect
    let pixels: Surface

    func weight(x: Int, y: Int) -> Float {
      let distanceX = max(owned.x - x, x - (owned.x + owned.width - 1), 0)
      let distanceY = max(owned.y - y, y - (owned.y + owned.height - 1), 0)
      let radius = Float(overlap + 1)
      return (1 - Float(distanceX) / radius) * (1 - Float(distanceY) / radius)
    }
  }

  static func support(of mask: SelectionMask) throws -> [IntRect] {
    guard let bounds = mask.bounds else { return [] }
    let surface = try mask.coverageSurface()
    if surface.defaultPixel.r > 0 { return [bounds] }
    let side = Surface.tileSide, columns = (mask.width + side - 1) / side
    return surface.storedTileKeys.map { key in
      let x = (key % columns) * side, y = (key / columns) * side
      return IntRect(x: x, y: y, width: min(side, mask.width - x), height: min(side, mask.height - y))
    }
  }

  private static func ownedRegions(_ mask: SelectionMask, bounds: IntRect) throws -> [(Cell, IntRect)] {
    if max(bounds.width, bounds.height) <= maximumSingleSide { return [(Cell(column: 0, row: 0), bounds)] }
    var result: [(Cell, IntRect)] = []
    for (group, marks) in try groups(mask).enumerated() {
      guard let box = try enclosedMarks(mask, window: marks.bounds) else { continue }
      if max(box.width, box.height) <= maximumSingleSide {
        result.append((Cell(column: 0, row: 0, group: group), box))
      } else {
        var cells = Set<Cell>()
        for tile in marks.tiles {
          try Task.checkCancellation()
          guard let available = intersection(tile, box) else { continue }
          let left = (available.x - box.x) / cellSide, right = (available.x + available.width - 1 - box.x) / cellSide
          let top = (available.y - box.y) / cellSide, bottom = (available.y + available.height - 1 - box.y) / cellSide
          for row in top...bottom { for column in left...right { cells.insert(Cell(column: column, row: row, group: group)) } }
        }
        guard result.count + cells.count <= maximumPredictions else { throw tooManyRepairs }
        for cell in cells.sorted() {
          let offsetX = cell.column * cellSide, offsetY = cell.row * cellSide
          result.append((cell, IntRect(x: box.x + offsetX, y: box.y + offsetY,
            width: min(cellSide, box.width - offsetX), height: min(cellSide, box.height - offsetY))))
        }
      }
      guard result.count <= maximumPredictions else { throw tooManyRepairs }
    }
    return result
  }

  private static var tooManyRepairs: CraftError {
    .unsupported("This generative Remove batch spans too many repair regions. Apply a smaller group of marks.")
  }

  private static func groups(_ mask: SelectionMask) throws -> [Group] {
    let side = Surface.tileSide, tileBudget = maximumPredictions * (cellSide / side) * (cellSide / side)
    var unvisited = Set<Cell>()
    for rect in try support(of: mask) where rect.width > 0 && rect.height > 0 {
      try Task.checkCancellation()
      for row in rect.y / side...(rect.y + rect.height - 1) / side {
        for column in rect.x / side...(rect.x + rect.width - 1) / side {
          unvisited.insert(Cell(column: column, row: row))
          guard unvisited.count <= tileBudget else { throw tooManyRepairs }
        }
      }
    }
    var regions: [Group] = []
    for seed in unvisited.sorted() where unvisited.remove(seed) != nil {
      var walk = [seed], next = 0, tiles: [IntRect] = []
      while next < walk.count {
        try Task.checkCancellation()
        let cell = walk[next]; next += 1
        let tile = IntRect(x: cell.column * side, y: cell.row * side, width: side, height: side)
        tiles.append(tile.clipped(toWidth: mask.width, height: mask.height))
        for row in (cell.row - 1)...(cell.row + 1) {
          for column in (cell.column - 1)...(cell.column + 1) {
            let neighbor = Cell(column: column, row: row)
            if unvisited.remove(neighbor) != nil { walk.append(neighbor) }
          }
        }
      }
      guard var bounds = try LayerLayout.union(tiles) else { continue }
      // Bounding boxes of disconnected shapes can intersect, such as a ring
      // surrounding a second mark. Use one owner for the common area.
      while let index = regions.firstIndex(where: { intersection($0.bounds, bounds) != nil }) {
        let other = regions.remove(at: index)
        guard let combined = try LayerLayout.union([bounds, other.bounds]) else { continue }
        bounds = combined; tiles += other.tiles
      }
      regions.append(Group(bounds: bounds, tiles: tiles))
      guard regions.count <= maximumPredictions else { throw tooManyRepairs }
    }
    return regions
  }

  private static func intersection(_ a: IntRect, _ b: IntRect) -> IntRect? {
    let x = max(a.x, b.x), y = max(a.y, b.y)
    let width = min(a.x + a.width, b.x + b.width) - x, height = min(a.y + a.height, b.y + b.height) - y
    return width > 0 && height > 0 ? IntRect(x: x, y: y, width: width, height: height) : nil
  }

  static func prepare(_ request: RemoveRequest, source: CraftDocument, marked: CraftDocument, layer: Layer,
    mask: SelectionMask, predict: ([Float], [Float]) throws -> Surface) throws -> RegionRetouchEdit {
    guard let bounds = mask.bounds else { throw CraftError.invalid("Mark an area to remove.") }
    let sampling = request.settings.sampleAllLayers ? nil : ContentAwareInput.samplingLayer(layer)
    var repairs: [Cell: Repair] = [:]
    let cells = try ownedRegions(mask, bounds: bounds)
    for (cell, owned) in cells {
      try Task.checkCancellation()
      let expanded = IntRect(x: owned.x - overlap, y: owned.y - overlap, width: owned.width + 2 * overlap,
        height: owned.height + 2 * overlap).clipped(toWidth: source.width, height: source.height)
      guard let region = try enclosedMarks(mask, window: expanded) else { continue }
      let (recipe, _) = try LocalGenerativeFill.capture(marked, samplingLayer: sampling, selectionBounds: region)
      guard let pixels = try recipe.patches(in: marked, predict: { data, mark in [try predict(data, mark)] }).first else {
        throw CraftError.invalid("The local model returned no Remove result.")
      }
      repairs[cell] = Repair(owned: owned, region: region, pixels: pixels)
    }
    return try commit(request, source: source, layer: layer, mask: mask, bounds: bounds,
      repairs: repairs, order: cells.map(\.0))
  }

  private static func enclosedMarks(_ mask: SelectionMask, window: IntRect) throws -> IntRect? {
    var x0 = window.x + window.width, y0 = window.y + window.height, x1 = -1, y1 = -1
    for y in window.y..<(window.y + window.height) {
      try Task.checkCancellation()
      for x in window.x..<(window.x + window.width) where mask.byte(at: y * mask.width + x) != 0 {
        x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
      }
    }
    return x1 >= x0 ? IntRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1) : nil
  }

  private static func commit(_ request: RemoveRequest, source: CraftDocument, layer: Layer, mask: SelectionMask,
    bounds: IntRect, repairs: [Cell: Repair], order: [Cell]) throws -> RegionRetouchEdit {
    var result = source
    guard let index = source.layers.firstIndex(where: { $0.id == layer.id }) else { throw CraftError.invalid("Remove target changed.") }
    let linear = source.depth == .f32
    let ownerRepairs = order.compactMap { cell -> (IntRect, [Repair])? in
      guard let owner = repairs[cell] else { return nil }
      let neighbors = ((cell.row - 1)...(cell.row + 1)).flatMap { row in
        ((cell.column - 1)...(cell.column + 1)).compactMap { column in repairs[Cell(column: column, row: row, group: cell.group)] }
      }
      return (owner.owned, neighbors)
    }
    if request.settings.createNewLayer {
      var patch = try Surface(width: bounds.width, height: bounds.height, depth: source.depth,
        colorEncoding: linear ? .linearRGB : .sRGB)
      for (owned, neighbors) in ownerRepairs {
        for y in owned.y..<(owned.y + owned.height) {
          try Task.checkCancellation()
          for x in owned.x..<(owned.x + owned.width) {
            let k = mask.coverage(x: x, y: y)
            guard k > 0, var fill = sample(neighbors, atX: x, y: y, linear: linear) else { continue }
            fill.a *= k
            if linear { patch.setLinearPixel(x: x - bounds.x, y: y - bounds.y, fill) }
            else { patch.setPixel(x: x - bounds.x, y: y - bounds.y, fill) }
          }
        }
      }
      var correction = Layer(name: "Remove", content: .raster(patch))
      correction.x = bounds.x; correction.y = bounds.y; correction.parentID = layer.parentID
      result.layers.insert(correction, at: index + 1); result.activeLayerID = correction.id
    } else {
      let preserve = source.isTransparencyLocked(layer.id)
      var targetLayer = layer
      let changed = try ClonePainter.paintTarget(mask: false, bounds: bounds, on: &targetLayer,
        clipping: bounds, preserveTransparency: preserve) { target, transform, _ in
        let inverse = try transform.inverted()
        var changed = false
        var visited = 0
        for (owned, neighbors) in ownerRepairs {
          let local = try (inverse * .translation(Double(owned.x), Double(owned.y)))
            .bounds(width: owned.width, height: owned.height).clipped(toWidth: target.width, height: target.height)
          visited += local.width * local.height
          guard visited <= 64_000_000 else { throw CraftError.unsupported("This transformed Remove target spans too many stored pixels.") }
          for y in local.y..<(local.y + local.height) {
            try Task.checkCancellation()
            for x in local.x..<(local.x + local.width) {
              let p = transform.point(Double(x) + 0.5, Double(y) + 0.5)
              let dx = Int(floor(p.x)), dy = Int(floor(p.y))
              guard owned.contains(dx, dy) else { continue }
              let k = mask.coverage(x: dx, y: dy)
              guard k > 0, let fill = sample(neighbors, atX: dx, y: dy, linear: linear) else { continue }
              let old = linear ? target.linearPixel(x: x, y: y) : target.pixel(x: x, y: y)
              if preserve && old.a == 0 { continue }
              let pixel = ContentAwareEdit.removeSample(old, fill: fill, coverage: k, preserveTransparency: preserve)
              if linear { target.setLinearPixel(x: x, y: y, pixel) }
              else { target.setPixel(x: x, y: y, pixel) }
              changed = true
            }
          }
        }
        return changed
      }
      if changed { result.layers[index] = targetLayer; result.activeLayerID = layer.id }
    }
    try result.validate(); try Task.checkCancellation()
    return .init(source: source, result: result, label: "Remove")
  }

  private static func sample(_ repairs: [Repair], atX x: Int, y: Int, linear: Bool) -> Pixel? {
    var sum = SIMD4<Float>.zero
    var total: Float = 0
    var first: Pixel?, count = 0
    for repair in repairs where repair.region.contains(x, y) {
      let px = x - repair.region.x, py = y - repair.region.y
      let ink = linear ? repair.pixels.linearPixel(x: px, y: py) : repair.pixels.pixel(x: px, y: py)
      let weight = repair.weight(x: x, y: y)
      sum += SIMD4(ink.r, ink.g, ink.b, ink.a) * weight
      total += weight
      if first == nil { first = ink }
      count += 1
    }
    guard count > 1 else { return first }
    let mixed = sum / total
    return Pixel(mixed.x, mixed.y, mixed.z, mixed.w)
  }
}
