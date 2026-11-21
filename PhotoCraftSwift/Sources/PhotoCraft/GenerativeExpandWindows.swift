import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Page the generated border independently of the protected source canvas.
/// Each window supplies its core and a weighted contribution to its neighbours.
struct GenerativeExpandWindows {
  static let side = 384
  static let overlap = 64

  struct Cell: Hashable {
    let column: Int
    let row: Int
  }

  private struct Patch {
    let bounds: IntRect
    let pixels: [SIMD4<Float>]

    func pixel(_ x: Int, _ y: Int) -> SIMD4<Float>? {
      guard bounds.contains(x, y) else { return nil }
      return pixels[(y - bounds.y) * bounds.width + x - bounds.x]
    }
  }

  let frame: IntRect
  let protected: IntRect
  let border: IntRect
  let cells: [Cell]
  let encoding: SurfaceColorEncoding

  init(frame: IntRect, protected: IntRect, border: IntRect, strips: [IntRect], depth: PixelDepth) {
    self.frame = frame
    self.protected = protected
    self.border = border
    encoding = depth == .f32 ? .linearRGB : .sRGB
    var occupied = Set<Cell>()
    for strip in strips {
      let left = (strip.x - border.x) / Self.side
      let top = (strip.y - border.y) / Self.side
      let right = (strip.x + strip.width - 1 - border.x) / Self.side
      let bottom = (strip.y + strip.height - 1 - border.y) / Self.side
      for row in top...bottom {
        for column in left...right { occupied.insert(Cell(column: column, row: row)) }
      }
    }
    cells = occupied.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
  }

  func render(
    original: CraftDocument, count: Int, predict: (Int, [Float], [Float]) throws -> Surface
  ) throws -> [Layer] {
    let folder = FileManager.default.temporaryDirectory.appending(path: "Photato-Expand-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: folder) }
    let mask = try assemble(depth: .u8, colorEncoding: .sRGB, fill: .black) { _ in
      { x, y in self.protected.contains(x, y) ? nil : .white }
    }
    let order = cells.sorted { (rank($0), $0.row, $0.column) < (rank($1), $1.row, $1.column) }
    return try (0..<count).map { variation in
      let directory = folder.appending(path: "\(variation)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
      var saved: [Cell: IntRect] = [:]
      for cell in order {
        try Task.checkCancellation()
        saved[cell] = try generate(cell, original: original, saved: saved, directory: directory) { image, mask in
          try predict(variation, image, mask)
        }
      }
      let raster = try assemble(depth: original.depth, colorEncoding: encoding, fill: .clear) { cell in
        let patches = try neighbours(of: cell, reach: 1).compactMap { candidate -> (IntRect, Patch)? in
          guard let bounds = saved[candidate] else { return nil }
          return (core(candidate), try read(candidate, bounds: bounds, directory: directory))
        }
        return { x, y in
          guard !self.protected.contains(x, y) else { return nil }
          var color = SIMD4<Float>.zero
          var weight: Float = 0
          for (owner, patch) in patches {
            guard let pixel = patch.pixel(x, y) else { continue }
            let w = Self.weight(x, start: owner.x, length: owner.width) * Self.weight(y, start: owner.y, length: owner.height)
            color += pixel * w
            weight += w
          }
          guard weight > 0 else { throw CraftError.invalid("A Generative Expand window left a gap in the border.") }
          let p = color / weight
          return Pixel(p.x, p.y, p.z, p.w)
        }
      }
      try FileManager.default.removeItem(at: directory)
      var layer = Layer(name: "Generative Expand", content: .raster(raster))
      layer.x = border.x
      layer.y = border.y
      layer.mask = mask
      return layer
    }
  }

  private func core(_ cell: Cell) -> IntRect {
    let x = border.x + cell.column * Self.side, y = border.y + cell.row * Self.side
    return IntRect(x: x, y: y, width: min(Self.side, border.x + border.width - x),
      height: min(Self.side, border.y + border.height - y))
  }

  private func rank(_ cell: Cell) -> Int {
    let block = core(cell)
    let horizontal = max(0, protected.x - block.x - block.width + 1, block.x - protected.x - protected.width + 1)
    let vertical = max(0, protected.y - block.y - block.height + 1, block.y - protected.y - protected.height + 1)
    return (max(horizontal, vertical) + Self.side - 1) / Self.side
  }

  private func neighbours(of cell: Cell, reach: Int) -> [Cell] {
    ((cell.row - reach)...(cell.row + reach)).flatMap { row in
      ((cell.column - reach)...(cell.column + reach)).map { Cell(column: $0, row: row) }
    }
  }

  private func expanded(_ rect: IntRect, by amount: Int) -> IntRect {
    IntRect(x: rect.x - amount, y: rect.y - amount,
      width: rect.width + 2 * amount, height: rect.height + 2 * amount)
      .clipped(toWidth: frame.width, height: frame.height)
  }

  private func intersection(_ a: IntRect, _ b: IntRect) -> IntRect? {
    let x = max(a.x, b.x), y = max(a.y, b.y)
    let right = min(a.x + a.width, b.x + b.width), bottom = min(a.y + a.height, b.y + b.height)
    guard right > x, bottom > y else { return nil }
    return IntRect(x: x, y: y, width: right - x, height: bottom - y)
  }

  private func generate(
    _ cell: Cell, original: CraftDocument, saved: [Cell: IntRect], directory: URL,
    predict: ([Float], [Float]) throws -> Surface
  ) throws -> IntRect {
    let write = expanded(core(cell), by: Self.overlap)
    let view = expanded(write, by: Self.side)
    let viewSize = IntRect(x: 0, y: 0, width: view.width, height: view.height)
    let historical = try neighbours(of: cell, reach: 2).compactMap { candidate -> (Cell, Patch)? in
      guard let bounds = saved[candidate], rank(candidate) < rank(cell),
        intersection(core(candidate), view) != nil else { return nil }
      return (candidate, try read(candidate, bounds: bounds, directory: directory))
    }
    let prior = Dictionary(uniqueKeysWithValues: historical)
    func previous(_ x: Int, _ y: Int) -> SIMD4<Float>? {
      guard border.contains(x, y) else { return nil }
      let owner = Cell(column: (x - border.x) / Self.side, row: (y - border.y) / Self.side)
      return prior[owner]?.pixel(x, y)
    }
    let known = intersection(view, protected)
    let crop = try known.map { box in
      let sample = IntRect(x: box.x - protected.x, y: box.y - protected.y, width: box.width, height: box.height)
      return try Renderer.composite(original, region: sample).cropped(to: sample)
    }
    var proxy = try CraftDocument(width: view.width, height: view.height, depth: original.depth)
    proxy.colorSpace = original.colorSpace
    proxy.workingICC = original.workingICC
    proxy.profileIsUntagged = original.profileIsUntagged
    var pixels = try Surface(width: view.width, height: view.height, depth: original.depth, colorEncoding: encoding)
    for y in 0..<view.height {
      try Task.checkCancellation()
      for x in 0..<view.width {
        let u = view.x + x, v = view.y + y
        let p: Pixel
        if let known, let crop, known.contains(u, v) {
          p = encoding == .linearRGB ? crop.linearPixel(x: u - known.x, y: v - known.y) : crop.pixel(x: u - known.x, y: v - known.y)
        } else if let sample = previous(u, v) {
          p = Pixel(sample.x, sample.y, sample.z, sample.w)
        } else {
          continue
        }
        if encoding == .linearRGB { pixels.setLinearPixel(x: x, y: y, p) }
        else { pixels.setPixel(x: x, y: y, p) }
      }
    }
    proxy.layers[0].content = .raster(pixels)
    let selection = try SelectionMask.sampledCoverage(width: view.width, height: view.height, regions: [viewSize]) { x, y in
      let u = view.x + x, v = view.y + y
      if protected.contains(u, v) { return 0 }
      return write.contains(u, v) || previous(u, v) == nil ? 255 : 0
    }
    proxy.setCoverageSelection(selection)
    let kept = known.map { IntRect(x: $0.x - view.x, y: $0.y - view.y, width: $0.width, height: $0.height) }
    let (recipe, _) = try LocalGenerativeFill.capture(proxy, protectedCanvas: kept)
    let generated = try recipe.patches(in: proxy) { try [predict($0, $1)] }[0]
    let absolute = IntRect(x: view.x + recipe.selection.x, y: view.y + recipe.selection.y,
      width: recipe.selection.width, height: recipe.selection.height)
    guard let bounds = intersection(write, absolute) else { throw CraftError.invalid("There is no generated border in this window.") }
    let patch = try generated.cropped(to: IntRect(x: bounds.x - absolute.x, y: bounds.y - absolute.y,
      width: bounds.width, height: bounds.height))
    try patch.rgbaData(depth: .f32, colorEncoding: encoding).write(to: file(cell, directory))
    return bounds
  }

  private func file(_ cell: Cell, _ folder: URL) -> URL {
    folder.appending(path: "\(cell.row)-\(cell.column).rgba")
  }

  private func read(_ cell: Cell, bounds: IntRect, directory: URL) throws -> Patch {
    let data = try Data(contentsOf: file(cell, directory), options: .mappedIfSafe)
    let count = bounds.width * bounds.height
    guard data.count == count * MemoryLayout<SIMD4<Float>>.stride else {
      throw CraftError.invalid("A staged Generative Expand window has an incomplete raster.")
    }
    var pixels = [SIMD4<Float>](repeating: .zero, count: count)
    _ = pixels.withUnsafeMutableBytes { data.copyBytes(to: $0) }
    return Patch(bounds: bounds, pixels: pixels)
  }

  private static func weight(_ point: Int, start: Int, length: Int) -> Float {
    let distance = max(0, start - point, point - start - length + 1)
    let t = max(0, 1 - Float(distance) / Float(overlap + 1))
    return t * t * (3 - 2 * t)
  }

  private func assemble(
    depth: PixelDepth, colorEncoding: SurfaceColorEncoding, fill: Pixel,
    sampler: (Cell) throws -> (Int, Int) throws -> Pixel?
  ) throws -> Surface {
    let builder = try Surface.PagedBuilder(width: border.width, height: border.height, depth: depth,
      fill: fill, colorEncoding: colorEncoding)
    let side = Surface.tileSide
    let groups = Dictionary(grouping: cells, by: \.row)
    for row in groups.keys.sorted() {
      var prepared: [(Int, Int, Surface.PagedBuilder.PreparedTile)] = []
      for cell in groups[row] ?? [] {
        let bounds = core(cell)
        let sample = try sampler(cell)
        for y in stride(from: 0, to: bounds.height, by: side) {
          for x in stride(from: 0, to: bounds.width, by: side) {
            try Task.checkCancellation()
            var tile = try Surface(width: min(side, bounds.width - x), height: min(side, bounds.height - y),
              depth: depth, fill: fill, colorEncoding: colorEncoding)
            for v in 0..<tile.height {
              for u in 0..<tile.width {
                guard let p = try sample(bounds.x + x + u, bounds.y + y + v) else { continue }
                if colorEncoding == .linearRGB { tile.setLinearPixel(x: u, y: v, p) }
                else { tile.setPixel(x: u, y: v, p) }
              }
            }
            prepared.append(((bounds.y - border.y + y) / side, (bounds.x - border.x + x) / side,
              try builder.prepareTile(tile)))
          }
        }
      }
      for (r, c, tile) in prepared.sorted(by: { ($0.0, $0.1) < ($1.0, $1.1) }) {
        try builder.append(tile, row: r, columns: c..<(c + 1))
      }
    }
    return try builder.finish()
  }
}
