import Foundation
import PhotoCraftCore

final class PcraftLayerMapper {
  let document:CraftDocument
  var smartSources:[String:PcraftSmartObjects.Decoded]=[:]
  var linkedSmartSources:[String:PSDSmartObjects.File]?
  let project: PcraftProject
  let namespace: Data
  let depth: PixelDepth
  var remainingBytes: Int
  let patterns: [RasterPattern]
  let dpi:Double
  let canvas: IntRect
  private var count = 0
  init(project: PcraftProject, document:CraftDocument, namespace: Data, depth: PixelDepth, remainingBytes: Int, patterns: [RasterPattern] = [], dpi:Double=72, canvas: IntRect = .init(x:0,y:0,width:1,height:1)) {
    self.document=document; self.project = project; self.namespace = namespace; self.depth = depth
    self.remainingBytes = remainingBytes; self.patterns = patterns; self.canvas = canvas;self.dpi=dpi
  }
  @inline(never) func layers(_ node: PcraftNode, parent: UUID?) throws -> [Layer] {
    var output: [Layer] = []
    for item in try node.array() {
      try Task.checkCancellation()
      count += 1
      guard count <= LayerLimits.maximumLayers else { throw item.unsupported("The native \(LayerLimits.maximumLayers)-layer limit was exceeded.") }
      try item.keys("id name visible locks blend opacity fill_opacity clipped mask vector_mask effects label content psd_blocks psd_id fill_cache link_group excluded_channels blend_if video")
      let fillOpacity = try item.optional("fill_opacity")?.float() ?? 1
      guard (0...1).contains(fillOpacity) else { throw item.invalid }
      let labelName = try item.field("label").string()
      guard let label = LayerColorLabel.allCases.first(where: { $0.title == labelName }), label.rawValue <= 7 else {
        throw item.unsupported("Unknown source layer color label.")
      }
      if let psdID = item.optional("psd_id"), try psdID.unsigned() > UInt32.max { throw psdID.invalid }
      try item.defaultValue("psd_blocks", "[]")
      for field in ["fill_cache", "link_group", "blend_if", "video"] { try item.defaultValue(field, "null") }
      try item.defaultValue("excluded_channels", "0")
      let effects = try item.field("effects")
      let id = PcraftImport.identity(namespace, role: "layer", id: try item.field("id").unsigned())
      let content = try item.field("content")
      let blend = try item.field("blend").string()
      var layer: Layer
      switch try content.field("kind").string() {
      case "smart":
        layer=try PcraftSmartObjects.layer(content,name:item.field("name").string(),project:project,namespace:namespace,parent:document,budget:&remainingBytes,sources:&smartSources,linkedFiles:&linkedSmartSources)
      case "text":
        layer=try PcraftText.layer(content,name:item.field("name").string(),project:project,depth:depth,dpi:dpi,budget:&remainingBytes)
      case "shape":
        layer=try PcraftShapes.layer(content,name:item.field("name").string(),project:project,patterns:patterns,depth:depth,canvas:canvas,budget:&remainingBytes)
      case "adjustment":
        try content.keys("kind adjustment")
        let node = try content.field("adjustment")
        if case .object(let fields)=node.value,fields.keys.sorted()==["Exposure"] {
        try node.keys("Exposure")
        let values = try node.field("Exposure")
        try values.keys("exposure offset gamma")
        let settings = try ExposureAdjustment(exposure:values.field("exposure").float(),offset:values.field("offset").float(),gammaCorrection:values.field("gamma").float())
        try settings.validate()
        layer = Layer(name:try item.field("name").string(),content:.adjustment(.classic(.exposure(settings))))
        } else {
          let settings=try PcraftAdjustments.read(node)
          _ = try SourceAdjustmentTransfer(settings,depth:depth)
          layer=Layer(name:try item.field("name").string(),content:.adjustment(.source(settings)))
        }
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
      case "fill":
        try content.keys("kind fill")
        layer = Layer(name: try item.field("name").string(), content: try PcraftFills.content(content.field("fill"), patterns: patterns))
      case "group":
        try content.keys("kind children expanded artboard")
        var group = GroupContent(passThrough:blend == "PassThrough",expanded:try content.field("expanded").boolean())
        var boardBounds:IntRect?
        if let board = content.optional("artboard") {
          guard parent == nil else { throw board.unsupported("Artboards must be top-level groups.") }
          let mapped = try PcraftArtboards.read(board);group.artboard = mapped.0;boardBounds = mapped.1
        }
        layer = Layer(name:try item.field("name").string(),content:.group(group))
        if let boardBounds { layer.x = boardBounds.x;layer.y = boardBounds.y }
        output += try layers(content.field("children"), parent: id)
      default:
        throw content.unsupported("This layer content is not yet supported as editable native data.")
      }
      layer.id = id; layer.parentID = parent
      if label != .none { layer.colorLabel = label }
      layer.visible = try item.field("visible").boolean()
      layer.opacity = try item.field("opacity").float()
      layer.style=try PcraftEffects.read(effects,fillOpacity:fillOpacity,layer:layer,document:document,project:project,budget:&remainingBytes)
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
        properties.transform = try layer.coordinateTransform.inverted() * .translation(Double(placed.x),Double(placed.y))
        properties.outside = placed.outside
        properties.enabled = try mask.field("enabled").boolean()
        properties.linked = try mask.field("linked").boolean()
        properties.density = try mask.field("density").float()
        properties.feather = Double(try mask.field("feather").float())
        layer.maskProperties = properties
      }
      if let vector = item.optional("vector_mask") { layer.vectorMask = try PcraftPaths.mask(vector) }
      if case .patternFill(let fill) = layer.content, fill.linked, layer.mask != nil || layer.vectorMask != nil {
        throw content.unsupported("Linked pattern masks require the source frame-anchor mapping before import.")
      }
      output.append(layer)
    }
    return output
  }
}
