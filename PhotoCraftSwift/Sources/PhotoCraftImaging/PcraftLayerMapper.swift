import Foundation
import PhotoCraftCore

struct PcraftLayerMapper {
  let project: PcraftProject
  let namespace: Data
  let depth: PixelDepth
  var remainingBytes: Int
  private var count = 0
  init(project: PcraftProject, namespace: Data, depth: PixelDepth, remainingBytes: Int) {
    self.project = project; self.namespace = namespace; self.depth = depth
    self.remainingBytes = remainingBytes
  }
  mutating func layers(_ node: PcraftNode, parent: UUID?) throws -> [Layer] {
    var output: [Layer] = []
    for item in try node.array() {
      try Task.checkCancellation()
      count += 1
      guard count <= 512 else { throw item.unsupported("The native 512-layer limit was exceeded.") }
      try item.keys("id name visible locks blend opacity fill_opacity clipped mask vector_mask effects label content psd_blocks psd_id fill_cache link_group excluded_channels blend_if video")
      try item.defaultValue("fill_opacity", "1")
      let labelName = try item.field("label").string()
      guard let label = LayerColorLabel.allCases.first(where: { $0.title == labelName }), label.rawValue <= 7 else {
        throw item.unsupported("Unknown source layer color label.")
      }
      if let psdID = item.optional("psd_id"), try psdID.unsigned() > UInt32.max { throw psdID.invalid }
      try item.defaultValue("psd_blocks", "[]")
      for field in ["fill_cache", "link_group", "blend_if", "video"] { try item.defaultValue(field, "null") }
      try item.defaultValue("excluded_channels", "0")
      let effects = try item.field("effects")
      try effects.keys("enabled items psd_raw reference")
      _ = try effects.field("enabled").boolean()
      try effects.defaultValue("items", "[]")
      try effects.defaultValue("psd_raw", "null")
      try effects.defaultValue("reference", "null")
      let id = PcraftImport.identity(namespace, role: "layer", id: try item.field("id").unsigned())
      let content = try item.field("content")
      let blend = try item.field("blend").string()
      var layer: Layer
      switch try content.field("kind").string() {
      case "raster":
        try content.keys("kind surface")
        let surface = try content.field("surface")
        try PcraftSamples.validateSchema(surface)
        guard let source = project.surfaces[surface.path], try PcraftSamples.depth(source.sample) == depth else {
          throw content.unsupported("Raster depth must match the document.")
        }
        let placed = try PcraftSamples.placed(source, mask: false, budget: &remainingBytes)
        layer = Layer(name: try item.field("name").string(), content: .raster(placed.surface))
        layer.x = placed.x; layer.y = placed.y
      case "group":
        try content.keys("kind children expanded artboard")
        try content.defaultValue("artboard", "null")
        layer = Layer(name: try item.field("name").string(), content: .group(GroupContent(
          passThrough: blend == "PassThrough", expanded: try content.field("expanded").boolean())))
        output += try layers(content.field("children"), parent: id)
      default:
        throw content.unsupported("This layer content is not yet supported as editable native data.")
      }
      layer.id = id; layer.parentID = parent
      if label != .none { layer.colorLabel = label }
      layer.visible = try item.field("visible").boolean()
      layer.opacity = try item.field("opacity").float()
      layer.clipped = try item.field("clipped").boolean()
      if blend == "PassThrough" {
        guard case .group = layer.content else { throw item.unsupported("Pass Through requires a group.") }
      } else {
        guard let native = BlendMode.allCases.first(where: { $0.rawValue.replacingOccurrences(of: " ", with: "") == blend }) else {
          throw item.unsupported("Unknown blend mode '\(blend)'.")
        }
        layer.blendMode = native
      }
      let locks = try item.field("locks")
      try locks.keys("transparency pixels position artboard all")
      var protection = LayerProtection()
      for (key, flag) in [("transparency", LayerProtection.transparency), ("pixels", .image),
        ("position", .position), ("artboard", .autoNest), ("all", .all)] {
        if try locks.field(key).boolean() { protection.insert(flag) }
      }
      layer.protection = protection
      if let mask = item.optional("mask") {
        try mask.keys("surface enabled linked density feather")
        let surface = try mask.field("surface")
        try PcraftSamples.validateSchema(surface)
        guard let source = project.surfaces[surface.path] else { throw mask.invalid }
        let placed = try PcraftSamples.placed(source, mask: true, budget: &remainingBytes)
        layer.mask = placed.surface
        var properties = MaskProperties()
        properties.transform = .translation(Double(placed.x - layer.x), Double(placed.y - layer.y))
        properties.outside = placed.outside
        properties.enabled = try mask.field("enabled").boolean()
        properties.linked = try mask.field("linked").boolean()
        properties.density = try mask.field("density").float()
        properties.feather = Double(try mask.field("feather").float())
        layer.maskProperties = properties
      }
      if let vector = item.optional("vector_mask") { layer.vectorMask = try PcraftPaths.mask(vector) }
      output.append(layer)
    }
    return output
  }
}
