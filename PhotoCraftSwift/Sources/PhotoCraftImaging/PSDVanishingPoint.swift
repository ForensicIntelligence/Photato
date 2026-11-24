import Foundation
import PhotoCraftCore

/// Photoshop image resource 4000 stores perspective planes as relations of four rays.
enum PSDVanishingPoint {
  static let id = 4000
  static let importedKey = "psdVanishingPoint"
  private static let maximumPayload = 64 * 1024

  private struct Cursor {
    let words: [Substring]
    var offset = 0
    mutating func next() throws -> Substring {
      guard words.indices.contains(offset) else { throw invalid() }
      defer { offset += 1 }
      return words[offset]
    }
    mutating func integer<T: FixedWidthInteger>(_ type: T.Type = Int.self) throws -> T {
      guard let value = T(try next()) else { throw invalid() }
      return value
    }
    mutating func number() throws -> Double {
      guard let value = Double(try next()), value.isFinite else { throw invalid() }
      return value
    }
    mutating func point() throws -> PathPoint { try .init(number(), number()) }
  }

  private struct Ray {
    let origin: PathPoint
    let vanisher: PathPoint
    let endpoint: Bool
    let axis: Int
    let tag: Int

    var line: SIMD3<Double> {
      let dx = vanisher.x-origin.x, dy = vanisher.y-origin.y
      let length = hypot(dx,dy)
      return length > 0 ? .init(dy/length,-dx/length,(dx*origin.y-dy*origin.x)/length) : .zero
    }
  }

  private struct Plane {
    let grid: Double
    let identity: UInt32
    let parent: UInt32
    let angle: Double?
    let rays: [Int: Ray]

    func corners() throws -> [PathPoint] {
      try [(3,5),(5,7),(7,1),(1,3)].map { a,b in
        let l = rays[a]!.line, r = rays[b]!.line
        let w = l.x*r.y-l.y*r.x
        guard abs(w)>1e-12 else { throw invalid() }
        let point = PathPoint((l.y*r.z-l.z*r.y)/w,(l.z*r.x-l.x*r.z)/w)
        guard point.x.isFinite, point.y.isFinite else { throw invalid() }
        return point
      }
    }

    func rootCorners() throws -> [PathPoint] {
      let ring = try corners()
      let sides = [5,7,1,3]
      let widthAxis = min(rays[1]!.axis,rays[7]!.axis)
      let cross = (ring[1].x-ring[0].x)*(ring[2].y-ring[0].y)-(ring[1].y-ring[0].y)*(ring[2].x-ring[0].x)
      let step = cross > 0 ? 1 : -1
      let candidates = (0..<4).filter { rays[sides[step>0 ? $0 : ($0+3)%4]]!.axis == widthAxis }
      guard let start = candidates.min(by:{ ring[$0].x+ring[$0].y < ring[$1].x+ring[$1].y }) else { throw invalid() }
      return (0..<4).map { ring[(start+4+$0*step)%4] }
    }
  }

  private struct Resource {
    let planes: [Plane]
    let footer: [String]
  }

  private static func invalid() -> CraftError { .invalid("Invalid Photoshop perspective plane resource.") }

  private static func isVanishingPoint(_ block: PSDImageResources.Block) -> Bool {
    guard block.id == id, block.data.count >= 7,
      let prefix = String(data:block.data.prefix(4),encoding:.ascii)?.lowercased() else { return false }
    return prefix == "tnaf" || prefix == "fant"
  }

  private static func decode(_ data: Data) throws -> Resource {
    guard data.count <= maximumPayload, let source = String(data:data,encoding:.ascii) else { throw invalid() }
    var input = Cursor(words:source.split(whereSeparator: \.isWhitespace))
    let header = try input.next().dropFirst(4)
    guard let version = Int(header), version == 101 || version == 203 else { throw invalid() }
    let relations: Int = try input.integer()
    guard (1...32).contains(relations) else { throw invalid() }
    var planes: [Plane] = []
    var identities = Set<UInt32>()
    for _ in 0..<relations {
      try Task.checkCancellation()
      let grid = try input.number()
      let count: Int = try input.integer()
      guard grid > 0, count > 0, count <= 32-planes.count else { throw invalid() }
      var family = Set<UInt32>()
      for index in 0..<count {
        let identity = try input.integer(UInt32.self)
        let parent = try input.integer(UInt32.self)
        guard identity != 0, identities.insert(identity).inserted,
          index == 0 ? parent == 0 : family.contains(parent) else { throw invalid() }
        family.insert(identity)
        let angle: Double?
        if version == 203 {
          let degrees = try input.number()
          let selector: Int = try input.integer()
          _ = try input.point()
          guard (0...2).contains(selector), (-180...180).contains(degrees) else { throw invalid() }
          angle = index == 0 ? nil : degrees
        } else {
          angle = nil
        }
        var rays: [Int: Ray] = [:]
        for _ in 0..<4 {
          let origin = try input.point(), vanisher = try input.point()
          let endpoint: Int = try input.integer()
          let axis: Int = try input.integer()
          let tag: Int = try input.integer()
          guard (0...1).contains(endpoint), (0...2).contains(axis), [1,3,5,7].contains(tag),
            rays[tag] == nil, origin != vanisher else { throw invalid() }
          rays[tag] = .init(origin:origin,vanisher:vanisher,endpoint:endpoint == 1,axis:axis,tag:tag)
        }
        guard rays[1]!.axis == rays[5]!.axis, rays[3]!.axis == rays[7]!.axis,
          rays[1]!.axis != rays[7]!.axis else { throw invalid() }
        planes.append(.init(grid:grid,identity:identity,parent:parent,angle:angle,rays:rays))
      }
    }
    let footer = input.words.dropFirst(input.offset).map(String.init)
    guard footer.isEmpty || (version == 203 && footer.count == 2 + 3*relations && footer.first == "201"
      && footer.dropFirst().allSatisfy({ Double($0)?.isFinite == true })) else { throw invalid() }
    return Resource(planes:planes,footer:footer)
  }

  private static func points(_ edge: VanishingPlane.Edge) -> (parentA: Int,parentB: Int,childA: Int,childB: Int) {
    switch edge {
    case .top: (0,1,3,2)
    case .right: (1,2,0,3)
    case .bottom: (2,3,1,0)
    case .left: (3,0,2,1)
    }
  }

  private static func linkedCorners(_ ring: [PathPoint], parent: [PathPoint])
    throws -> (VanishingPlane.Edge,[PathPoint])
  {
    func distance(_ a: PathPoint,_ b: PathPoint) -> Double { hypot(a.x-b.x,a.y-b.y) }
    var best: (edge: VanishingPlane.Edge, corners: [PathPoint], distance: Double)?
    for edge in VanishingPlane.Edge.allCases {
      let p = points(edge)
      for first in 0..<4 {
        for order in [1,-1] {
          var q=(0..<4).map { ring[(first+4+order*$0)%4] }
          let a=parent[p.parentA], b=parent[p.parentB]
          let error=distance(a,q[p.childA])+distance(b,q[p.childB])
          if best.map({error < $0.distance}) ?? true {
            q[p.childA]=a
            q[p.childB]=b
            best=(edge,q,error)
          }
        }
      }
    }
    let maximum = (parent+ring).reduce(0.0) { max($0,abs($1.x),abs($1.y)) }
    guard let best, best.distance <= max(0.06,maximum*0.000012) else { throw invalid() }
    return (best.edge,best.corners)
  }

  private static func settings(_ resource: Resource, width: Int, height: Int) throws -> VanishingSettings {
    var result = VanishingSettings()
    let center = PathPoint(Double(width)/2,Double(height)/2)
    result.center = center
    let roots = try resource.planes.filter { $0.parent == 0 }.map { try $0.rootCorners() }
    result.focalLength = roots.lazy.compactMap { VanishingScene.inferredFocal($0,center:center) }.first
      ?? Double(max(width,height))
    var indices: [UInt32:Int] = [:]
    for item in resource.planes {
      try Task.checkCancellation()
      let plane: VanishingPlane
      if item.parent == 0 {
        plane = .init(corners:try item.rootCorners())
      } else {
        guard let parent = indices[item.parent] else { throw invalid() }
        let scene = try VanishingScene(result,width:width,height:height)
        let (edge,corners)=try linkedCorners(item.corners(),parent:scene.frames[parent].corners)
        plane = try scene.calibratedPlane(parent:parent,edge:edge,corners:corners,angleFromCoplanar:item.angle)
      }
      indices[item.identity]=result.planes.count
      result.planes.append(plane)
    }
    _ = try VanishingScene(result,width:width,height:height)
    return result
  }

  static func read(_ resources: [PSDImageResources.Block], width: Int, height: Int) throws -> VanishingSettings? {
    let candidates = resources.filter(isVanishingPoint)
    guard candidates.count == 1 else { return nil }
    do { return try settings(decode(candidates[0].data),width:width,height:height) }
    catch let error as CancellationError { throw error }
    catch { return nil } // Unrecognized versions and geometry stay intact as opaque resources.
  }

  private struct Axis {
    let vanisher: PathPoint?
    let label: Int
  }

  private static func projectedDirection(_ vector: SIMD3<Double>, scene: VanishingScene) -> PathPoint? {
    guard abs(vector.z) > 1e-10 * max(1,abs(vector.x),abs(vector.y)) else { return nil }
    let result = PathPoint(scene.center.x+scene.focal*vector.x/vector.z,scene.center.y+scene.focal*vector.y/vector.z)
    return result.x.isFinite && result.y.isFinite ? result : nil
  }

  private static func axisDirections(_ corners: [PathPoint]) -> [SIMD3<Double>] {
    func product(_ a: SIMD3<Double>,_ b: SIMD3<Double>) -> SIMD3<Double> {
      .init(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)
    }
    func line(_ a: PathPoint,_ b: PathPoint) -> SIMD3<Double> {
      product(.init(a.x,a.y,1),.init(b.x,b.y,1))
    }
    return [product(line(corners[0],corners[1]),line(corners[3],corners[2])),
            product(line(corners[0],corners[3]),line(corners[1],corners[2]))]
  }

  private static func vanishingPoint(_ value: SIMD3<Double>) -> PathPoint? {
    guard abs(value.z) > 1e-12 * max(1,abs(value.x),abs(value.y)) else { return nil }
    return .init(value.x/value.z,value.y/value.z)
  }

  private static func rays(_ q: [PathPoint], axes: [Axis]) -> [Ray] {
    func distance(_ p: PathPoint,_ vp: PathPoint) -> Double { hypot(p.x-vp.x,p.y-vp.y) }
    func edge(_ start: Int,_ axis: Int) -> Int { start % 2 == axis ? start : (start+3)%4 }
    func farther(_ start: Int,_ axis: Int) -> Bool {
      guard let vp = axes[axis].vanisher else { return true }
      let first=edge(start,axis), second=(first+1)%4
      let other = first == start ? second : first
      return distance(q[start],vp) >= distance(q[other],vp)
    }
    let primary = [2,1,3,0].first { farther($0,0) && farther($0,1) } ?? 2
    var output: [Ray] = []
    for axis in 0..<2 {
      let axisRecord=axes[axis]
      let base=edge(primary,axis)
      let firstTag = axisRecord.label < axes[1-axis].label ? 1 : 7
      for (side,tag) in [(base,firstTag),((base+2)%4,firstTag == 1 ? 5 : 3)] {
        let next=(side+1)%4
        let start = tag == firstTag ? primary : (farther(side,axis) ? side : next)
        let end = start == side ? next : side
        output.append(Ray(origin:q[start],vanisher:axisRecord.vanisher ?? q[end],
          endpoint:axisRecord.vanisher == nil,axis:axisRecord.label,tag:tag))
      }
    }
    return [1,5,7,3].compactMap { tag in output.first { $0.tag == tag } }
  }

  private static func encode(_ document: VanishingSettings, width: Int, height: Int, previous: Resource?) throws -> Data {
    let scene = try VanishingScene(document,width:width,height:height)
    let roots = document.planes.indices.filter { document.planes[$0].parent == nil }
    let grids = previous?.planes.filter { $0.parent == 0 }.map(\.grid) ?? []
    var tokens = ["tNaF203",String(roots.count)]
    var labels: [Int:[Int]] = [:]
    func visit(_ node: Int) -> [Int] {
      [node] + document.planes.indices.filter { document.planes[$0].parent == node }.flatMap(visit)
    }
    func decimal(_ value: Double) -> String {
      if value.isFinite, abs(value) < 1e15, value == value.rounded() { return String(Int64(value)) }
      return String(format:"%.12g",locale:Locale(identifier:"en_US_POSIX"),value)
    }
    // Photoshop's point reader consumes a blank line following each pair.
    func point(_ p: PathPoint) { tokens += [decimal(p.x),decimal(p.y),""] }
    for (ordinal,root) in roots.enumerated() {
      let family = visit(root)
      tokens += [decimal(grids.indices.contains(ordinal) ? grids[ordinal] : 100),String(family.count)]
      for index in family {
        try Task.checkCancellation()
        let plane=document.planes[index], q=scene.frames[index].corners
        let vanishing = axisDirections(q).map(vanishingPoint)
        let axes: [Int]
        tokens += [String(index+1),String(plane.parent.map{$0+1} ?? 0)]
        if let parent=plane.parent, let parentAxes=labels[parent] {
          let seam: Int
          switch plane.edge {
          case .top,.bottom: seam=0
          case .left,.right: seam=1
          }
          let next=(0...2).first { !parentAxes.contains($0) }!
          axes = seam==0 ? [parentAxes[0],next] : [next,parentAxes[1]]
          let measured = try scene.calibratedPlane(parent:parent,edge:plane.edge,corners:q,
            angleFromCoplanar:180-plane.angle)
          let signed=(180-plane.angle)*(plane.rotationSign ?? measured.rotationSign ?? 1)
          let p=scene.frames[parent].points
          let h=p[1]-p[0], v=p[3]-p[0]
          let normal=SIMD3(h.y*v.z-h.z*v.y,h.z*v.x-h.x*v.z,h.x*v.y-h.y*v.x)
          tokens += [decimal(signed),String(next)]
          point(projectedDirection(normal,scene:scene) ?? vanishing[1-seam] ?? q[(seam+1)%4])
        } else {
          axes=[0,1]
          tokens += ["-1","0"]
          point(vanishing[0] ?? q[1])
        }
        labels[index]=axes
        let records = rays(q,axes:(0..<2).map{ Axis(vanisher:vanishing[$0],label:axes[$0]) })
        for ray in records {
          point(ray.origin)
          point(ray.vanisher)
          tokens += [ray.endpoint ? "1" : "0",String(ray.axis),String(ray.tag)]
        }
      }
    }
    if let footer = previous?.footer, footer.count == 2 + 3*roots.count {
      tokens += footer
    } else {
      // Version 201 workspace settings include a value and a pair per relation.
      tokens += ["201"] + Array(repeating:"100",count:roots.count) + ["0"]
      for _ in roots { tokens += ["100","0"] }
    }
    return Data((tokens.joined(separator:"\n")+"\n").utf8)
  }

  /// Preserve the original recognized record when the edit only changes pixels.
  static func applying(to data: Data, document: CraftDocument) throws -> Data {
    let hasImportedPlane = document.sourceMetadata?[importedKey] != nil
    guard document.vanishingPoint != nil || hasImportedPlane else { return data }
    let blocks = try PSDImageResources.blocks(data)
    let candidates = blocks.filter(isVanishingPoint)
    guard let settings = document.vanishingPoint, !settings.planes.isEmpty else {
      if !hasImportedPlane { return data }
      return blocks.filter { !isVanishingPoint($0) }.reduce(into:Data()) { $0.append($1.raw) }
    }
    guard candidates.count <= 1,
      !blocks.contains(where:{ $0.id == id && !isVanishingPoint($0) }) else {
      throw CraftError.unsupported("The PSD already contains an unrecognized perspective resource.")
    }
    let existing = candidates.first
    let previous: Resource?
    if let existing {
      do { previous = try decode(existing.data) }
      catch let error as CancellationError { throw error }
      catch { throw CraftError.unsupported("The PSD perspective resource can't be edited in this version.") }
    } else {
      previous = nil
    }
    if let previous,
      try self.settings(previous,width:document.width,height:document.height) == settings {
      return data
    }
    let payload = try encode(settings,width:document.width,height:document.height,previous:previous)
    let block = try PSDImageResources.replacing(existing,id:id,payload:payload)
    return blocks.filter { !isVanishingPoint($0) }.reduce(into:Data()) { $0.append($1.raw) } + block
  }
}
