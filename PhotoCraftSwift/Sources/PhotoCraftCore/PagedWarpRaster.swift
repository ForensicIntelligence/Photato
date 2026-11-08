import Foundation

/// Bounded output for the existing triangle/UV warp kernel. Triangle order,
/// barycentric arithmetic, pixel centers and sampling remain authoritative.
public enum PagedWarpRaster {
  public static let maximumPatchPixels = RasterGeometry.maximumPatchPixels
  public static let maximumVertices = 66_049
  public static let maximumTriangles = 131_072
  public static let maximumPatchVisits = 134_217_728

  fileprivate struct Triangle: Sendable {
    let a: Int, b: Int, c: Int, output: IntRect, input: IntRect
  }
  fileprivate struct Node: Sendable {
    let box: IntRect, left: Int, right: Int, first: Int, count: Int
  }
  fileprivate struct Index: Sendable {
    let nodes: [Node], order: [Int]
    init(_ boxes: [IntRect]) throws {
      var nodes: [Node] = [], order: [Int] = []
      func build(_ ids: [Int]) throws -> Int {
        try Task.checkCancellation()
        let box = ids.dropFirst().reduce(boxes[ids[0]]) { PagedWarpRaster.union($0, boxes[$1]) }
        let at = nodes.count
        nodes.append(Node(box: box, left: -1, right: -1, first: 0, count: 0))
        if ids.count <= 8 {
          nodes[at] = Node(box: box, left: -1, right: -1, first: order.count, count: ids.count)
          order += ids
        } else {
          let horizontal = box.width >= box.height
          let sorted = ids.sorted {
            let a = boxes[$0], b = boxes[$1]
            let aa = horizontal ? 2*a.x+a.width : 2*a.y+a.height
            let bb = horizontal ? 2*b.x+b.width : 2*b.y+b.height
            return aa == bb ? $0 < $1 : aa < bb
          }
          let middle = sorted.count/2
          let left = try build(Array(sorted[..<middle])), right = try build(Array(sorted[middle...]))
          nodes[at] = Node(box: box, left: left, right: right, first: 0, count: 0)
        }
        return at
      }
      if !boxes.isEmpty { _ = try build(Array(boxes.indices)) }
      self.nodes = nodes; self.order = order
    }
    func query(_ area: IntRect, boxes: (Int) -> IntRect) throws -> [Int] {
      guard !nodes.isEmpty else { return [] }
      var pending = [0], result: [Int] = []
      while let at = pending.popLast() {
        try Task.checkCancellation()
        let node = nodes[at]
        guard PagedWarpRaster.overlaps(node.box, area) else { continue }
        if node.left >= 0 { pending.append(node.left); pending.append(node.right) }
        else {
          for i in node.first..<(node.first+node.count) {
            let id = order[i]
            if PagedWarpRaster.overlaps(boxes(id), area) { result.append(id) }
          }
        }
      }
      return result.sorted()
    }
  }
  public final class Mapping: Sendable {
    public let bounds: IntRect
    fileprivate let vertices: [PathPoint], inputs: [PathPoint], triangles: [Triangle]
    fileprivate init(vertices: [PathPoint], inputs: [PathPoint], triangles: [[Int]], bounds: IntRect?) throws {
      guard !vertices.isEmpty, vertices.count == inputs.count, vertices.count <= PagedWarpRaster.maximumVertices,
        triangles.count <= PagedWarpRaster.maximumTriangles,
        (vertices+inputs).allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }),
        triangles.allSatisfy({ $0.count == 3 && $0.allSatisfy { vertices.indices.contains($0) } }) else {
        throw CraftError.invalid("Invalid paged warp triangle mapping.")
      }
      let x = bounds?.x ?? Int(floor(vertices.map(\.x).min()!+1e-9))
      let y = bounds?.y ?? Int(floor(vertices.map(\.y).min()!+1e-9))
      let width = bounds?.width ?? max(1, Int(ceil(vertices.map(\.x).max()!-1e-9))-x)
      let height = bounds?.height ?? max(1, Int(ceil(vertices.map(\.y).max()!-1e-9))-y)
      guard (-1_000_000...1_000_000).contains(x), (-1_000_000...1_000_000).contains(y),
        width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension else {
        throw CraftError.unsupported("Warp output exceeds the supported 300,000-pixel layer dimensions.")
      }
      self.bounds = IntRect(x: x, y: y, width: width, height: height)
      self.vertices = vertices; self.inputs = inputs
      self.triangles = triangles.map {
        Triangle(a: $0[0], b: $0[1], c: $0[2],
          output: PagedWarpRaster.box(vertices[$0[0]], vertices[$0[1]], vertices[$0[2]]),
          input: PagedWarpRaster.box(inputs[$0[0]], inputs[$0[1]], inputs[$0[2]]))
      }
    }
    func denseMapping() throws -> WarpRaster.Mapping {
      try WarpRaster.mapping(vertices: vertices, inputs: inputs, triangles: triangles.map { [$0.a,$0.b,$0.c] }, bounds: bounds)
    }
    fileprivate func patch(_ area: IntRect, index: Index) throws -> [PathPoint] {
      guard area.width > 0, area.height > 0, area.width <= PagedWarpRaster.maximumPatchPixels/area.height else {
        throw CraftError.invalid("Warp UV patches exceed their bounded working buffer.")
      }
      var uv = [PathPoint](repeating: .init(.nan, .nan), count: area.width*area.height), work = 0
      for id in try index.query(area, boxes: { triangles[$0].output }) {
        let triangle = triangles[id], p = vertices[triangle.a], q = vertices[triangle.b], r = vertices[triangle.c]
        let det = (q.x-p.x)*(r.y-p.y)-(r.x-p.x)*(q.y-p.y)
        guard abs(det) > 1e-10 else { continue }
        let clipped = PagedWarpRaster.intersection(triangle.output, area)
        guard clipped.width > 0, clipped.height > 0 else { continue }
        work += clipped.width*clipped.height
        guard work <= PagedWarpRaster.maximumPatchVisits else { throw CraftError.unsupported("Warp folds exceed the patch rendering work budget.") }
        for yy in clipped.y..<(clipped.y+clipped.height) {
          try Task.checkCancellation()
          for xx in clipped.x..<(clipped.x+clipped.width) {
            let dx = Double(xx)+0.5-p.x, dy = Double(yy)+0.5-p.y
            let v = (dx*(r.y-p.y)-dy*(r.x-p.x))/det
            let t = ((q.x-p.x)*dy-(q.y-p.y)*dx)/det, u = 1-v-t
            if min(u,v,t) >= -1e-9 {
              let aa = inputs[triangle.a], bb = inputs[triangle.b], cc = inputs[triangle.c]
              uv[(yy-area.y)*area.width+xx-area.x] = PathPoint(aa.x*u+bb.x*v+cc.x*t, aa.y*u+bb.y*v+cc.y*t)
            }
          }
        }
      }
      return uv
    }
    fileprivate func support(_ source: Surface, method: Resampling, clampEdges: Bool, full: Bool) throws -> [IntRect] {
      guard !triangles.isEmpty else{return []}
      guard !full, source.defaultPixel.hasSameBits(as: .clear), source.tileCount <= RasterGeometry.sparseGridSourceTileLimit else {
        return [IntRect(x: 0, y: 0, width: bounds.width, height: bounds.height)]
      }
      let halo=method == .nearest ? 0:2
      let supports = try source.projectedGeometrySupport(.identity,
        bounds: .init(x: 0, y: 0, width: source.width, height: source.height), halo: halo)
      guard !supports.isEmpty else{return []}
      let inputIndex=try Index(triangles.map(\.input))
      var ids = Set<Int>()
      for support in supports {
        // Neighbor kernels can read edge samples from slightly outside the
        // image; clamping can read them from anywhere in validated UV space.
        let x0=clampEdges && support.x==0 ? -1_000_001:support.x-halo
        let y0=clampEdges && support.y==0 ? -1_000_001:support.y-halo
        let x1=clampEdges && support.x+support.width==source.width ? 1_000_001:support.x+support.width+halo
        let y1=clampEdges && support.y+support.height==source.height ? 1_000_001:support.y+support.height+halo
        ids.formUnion(try inputIndex.query(.init(x:x0,y:y0,width:x1-x0,height:y1-y0), boxes: { triangles[$0].input }))
      }
      return ids.sorted().compactMap {
        let region = PagedWarpRaster.intersection(triangles[$0].output, bounds)
        guard region.width > 0, region.height > 0 else { return nil }
        return IntRect(x: region.x-bounds.x, y: region.y-bounds.y, width: region.width, height: region.height)
      }
    }
  }
  public static func mapping(_ warp: WarpDefinition, width: Int, height: Int, transform: Transform2D,
    projection: ProjectiveTransform? = nil) throws -> Mapping {
    try Task.checkCancellation(); try warp.validate(); try transform.validated()
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension else {
      throw CraftError.invalid("Invalid Warp source dimensions.")
    }
    let nx = min(256, max(16, (width+7)/8)), ny = min(256, max(16, (height+7)/8))
    var vertices: [PathPoint] = [], inputs: [PathPoint] = [], triangles: [[Int]] = []
    for j in 0...ny {
      try Task.checkCancellation()
      for i in 0...nx {
        let p = PathPoint(Double(i)*Double(width)/Double(nx), Double(j)*Double(height)/Double(ny))
        let warped = warp.point(p.x, p.y, width: Double(width), height: Double(height))
        let mapped = try projection.map { try $0.point(warped.x, warped.y) } ?? warped
        inputs.append(p); vertices.append(mapped.transformed(transform))
      }
    }
    for j in 0..<ny { for i in 0..<nx {
      let a = j*(nx+1)+i, b = a+1, c = a+nx+1, d = c+1
      triangles += [[a,b,d],[a,d,c]]
    } }
    return try Mapping(vertices: vertices, inputs: inputs, triangles: triangles, bounds: nil)
  }
  public static func mapping(vertices: [PathPoint], inputs: [PathPoint], triangles: [[Int]], bounds: IntRect? = nil) throws -> Mapping {
    try Mapping(vertices: vertices, inputs: inputs, triangles: triangles, bounds: bounds)
  }
  public static func render(_ source: Surface, using mapping: Mapping, method: Resampling, clampEdges: Bool = true) throws -> Surface {
    try output(source, mapping: mapping, method: method, clampEdges: clampEdges, mask: nil).0
  }
  public static func baked(_ layer: Layer, in document: CraftDocument, using mapping: Mapping, method: Resampling) throws -> Layer {
    guard case .raster(let source) = layer.content, layer.nativeMode == nil else {
      throw CraftError.unsupported("Paged Warp needs RGB raster samples without native component planes.")
    }
    var raw = layer
    let linked = layer.mask != nil && layer.effectiveMaskProperties.linked
    raw.maskProperties = layer.effectiveMaskProperties
    raw.maskProperties?.enabled = true; raw.maskProperties?.inverted = false
    raw.maskProperties?.density = 1; raw.maskProperties?.feather = 0
    let mask = try linked ? MaskSampler(layer: raw, feather: false, canvasSize: (document.width, document.height)) : nil
    let output = try output(source, mapping: mapping, method: method, clampEdges: true,
      mask: mask.map { ($0, layer.coordinateTransform, layer.mask!.depth) })
    var result = layer; result.content = .raster(output.0)
    result.x = mapping.bounds.x; result.y = mapping.bounds.y
    result.affine = nil; result.warp = nil; result.sourceProjection = nil; result.importedSmartAppearance = nil
    if linked {
      result.mask = output.1; result.maskProperties = layer.effectiveMaskProperties
      result.maskProperties?.transform = .identity
    } else if layer.mask != nil {
      var properties = layer.effectiveMaskProperties
      properties.transform = try result.coordinateTransform.inverted()*layer.maskCoordinateTransform
      result.maskProperties = properties
    }
    return result
  }
  private static func output(_ source: Surface, mapping: Mapping, method: Resampling, clampEdges: Bool,
    mask: (MaskSampler, Transform2D, PixelDepth)?) throws -> (Surface, Surface?) {
    try Task.checkCancellation(); try source.validated()
    let bounds = mapping.bounds, encoding: SurfaceColorEncoding = source.depth == .f32 ? .linearRGB : .sRGB
    let builder = try Surface.PagedBuilder(width: bounds.width, height: bounds.height, depth: source.depth, colorEncoding: encoding)
    let masks = try mask.map { try Surface.PagedBuilder(width: bounds.width, height: bounds.height, depth: $0.2, fill: .black) }
    let supports = try mapping.support(source, method: method, clampEdges: clampEdges, full: mask != nil)
    let index=try supports.isEmpty ? nil:Index(mapping.triangles.map(\.output))
    for region in GeometryPatchRegions(width: bounds.width, height: bounds.height, rectangles: supports) {
      let world = IntRect(x: bounds.x+region.x, y: bounds.y+region.y, width: region.width, height: region.height)
      let uv = try mapping.patch(world,index:index!)
      var patch = try Surface(width: region.width, height: region.height, depth: source.depth, colorEncoding: encoding)
      var maskPatch = try mask.map { try Surface(width: region.width, height: region.height, depth: $0.2, fill: .black) }
      for y in 0..<region.height {
        try Task.checkCancellation()
        for x in 0..<region.width {
          let point = uv[y*region.width+x], p = WarpRaster.sample(source, point, method: method, clampEdges: clampEdges)
          if source.depth == .f32 { patch.setLinearPixel(x: x, y: y, p) } else { patch.setPixel(x: x, y: y, p) }
          if let mask, point.x.isFinite {
            let p = point.transformed(mask.1), k = mask.0.coverage(x: p.x, y: p.y)
            maskPatch!.setPixel(x: x, y: y, Pixel(k,k,k,1))
          }
        }
      }
      try builder.append(patch, atX: region.x, atY: region.y)
      if let maskPatch { try masks!.append(maskPatch, atX: region.x, atY: region.y) }
    }
    return try (builder.finish(), masks?.finish())
  }
  fileprivate static func box(_ p: PathPoint, _ q: PathPoint, _ r: PathPoint) -> IntRect {
    let x = Int(floor(min(p.x,q.x,r.x))), y = Int(floor(min(p.y,q.y,r.y)))
    return IntRect(x: x, y: y, width: max(1, Int(ceil(max(p.x,q.x,r.x)))-x), height: max(1, Int(ceil(max(p.y,q.y,r.y)))-y))
  }
  fileprivate static func union(_ a: IntRect, _ b: IntRect) -> IntRect {
    let x = min(a.x,b.x), y = min(a.y,b.y)
    return IntRect(x: x, y: y, width: max(a.x+a.width,b.x+b.width)-x, height: max(a.y+a.height,b.y+b.height)-y)
  }
  fileprivate static func intersection(_ a: IntRect, _ b: IntRect) -> IntRect {
    let x = max(a.x,b.x), y = max(a.y,b.y)
    return IntRect(x: x, y: y, width: max(0,min(a.x+a.width,b.x+b.width)-x), height: max(0,min(a.y+a.height,b.y+b.height)-y))
  }
  fileprivate static func overlaps(_ a: IntRect, _ b: IntRect) -> Bool {
    a.x < b.x+b.width && b.x < a.x+a.width && a.y < b.y+b.height && b.y < a.y+a.height
  }
}
