import Foundation
import PhotoCraftCore

enum PcraftPaths {
  static func named(_ source: PcraftNode, namespace: Data) throws -> [NamedPath]? {
    var paths: [NamedPath] = []
    for (index, item) in try (source.optional("paths")?.array() ?? []).enumerated() {
      try item.keys("name path psd_raw")
      try item.defaultValue("psd_raw", "null")
      var named = NamedPath(name: try item.field("name").string(), path: try path(item.field("path")), isWorkPath: false)
      named.id = PcraftImport.identity(namespace, role: "path", id: UInt64(index))
      paths.append(named)
    }
    if let work = source.optional("work_path") {
      var named = NamedPath(path: try path(work))
      named.id = PcraftImport.identity(namespace, role: "workPath", id: 0)
      paths.append(named)
    }
    return paths.isEmpty ? nil : paths
  }
  static func mask(_ node: PcraftNode) throws -> VectorMask {
    try node.keys("path enabled linked density feather")
    var mask = VectorMask(path: try path(node.field("path")))
    mask.enabled = try node.field("enabled").boolean()
    mask.linked = try node.field("linked").boolean()
    mask.density = try node.field("density").float()
    mask.feather = Double(try node.field("feather").float())
    try mask.validate()
    return mask
  }
  static func path(_ node: PcraftNode) throws -> VectorPath {
    try node.keys("subpaths fill_rule inverted")
    let fill = try node.optional("fill_rule")?.string() ?? "NonZero"
    guard ["NonZero", "EvenOdd"].contains(fill) else { throw node.unsupported("Unknown path fill rule.") }
    let components = try node.field("subpaths").array().map { component in
      try component.keys("closed knots op")
      let op = try component.optional("op")?.string() ?? "Combine"
      guard let operation = PathOperation(rawValue: op) else { throw component.unsupported("Unknown path operation.") }
      let knots = try component.field("knots").array().map { knot in
        try knot.keys("anchor in_ctrl out_ctrl smooth")
        return PathKnot(try point(knot.field("anchor")), incoming: try point(knot.field("in_ctrl")),
          outgoing: try point(knot.field("out_ctrl")), smooth: try knot.optional("smooth")?.boolean() ?? false)
      }
      return PathComponent(knots: knots, closed: try component.field("closed").boolean(), operation: operation)
    }
    let result = VectorPath(components: components, fillRule: fill == "EvenOdd" ? .evenOdd : .nonZero,
      inverted: try node.optional("inverted")?.boolean() ?? false)
    try result.validate()
    return result
  }
  private static func point(_ node: PcraftNode) throws -> PathPoint {
    try node.keys("x y")
    return PathPoint(try node.field("x").double(), try node.field("y").double())
  }
}
