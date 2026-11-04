import Foundation
import PhotoCraftCore

enum GeometryAPI {
  static let commands = ["document.resize", "document.fitImage", "document.canvasSize", "document.rotate", "document.resolution"]
  static let preparedCommands = commands + SelectionGeometryAPI.commands
  static let methods: [String: Resampling] = ["nearest": .nearest, "bilinear": .bilinear, "bicubic": .bicubic]
  static let turns: [String: CanvasTurn] = ["clockwise": .clockwise, "counterclockwise": .counterclockwise, "half": .half, "horizontal": .horizontal, "vertical": .vertical]
  @MainActor static func fitImageState(_ store: EditorStore) -> [String: Any] {
    let draft = store.fitImageDraft
    let options = draft.flatMap { try? $0.options() }
    let pending: Any = options.map { value -> Any in
      ["width":value.width,"height":value.height,"dontEnlarge":value.dontEnlarge,
        "method":methodName(value.method)]
    } ?? NSNull()
    return ["available":store.canBeginFitImage,"dialogOpen":store.geometrySheet == .fitImage,
      "pendingOptions":pending,"sourceChanged":draft.map{$0.source != store.document || $0.generation != store.layerPanelGeneration} ?? false]
  }
  static func methodName(_ value: Resampling) -> String {
    switch value { case .nearest:"nearest"; case .bilinear:"bilinear"; case .bicubic:"bicubic" }
  }
  static var fitImageStateSchema: [String: Any] {
    ["type":"object","required":["available","dialogOpen","pendingOptions","sourceChanged"],
      "properties":["available":BrushAPI.flag,"dialogOpen":BrushAPI.flag,"sourceChanged":BrushAPI.flag,
        "pendingOptions":["type":["object","null"],"properties":["width":schema("width"),"height":schema("height"),"dontEnlarge":schema("dontEnlarge"),"method":schema("method")]]]]
  }
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "width", "height": return ["type": "integer", "minimum": 1, "maximum": Surface.maxDimension]
    case "resolution": return ["type": "number", "minimum": 1, "maximum": 100000]
    case "method": return ["type": "string", "enum": methods.keys.sorted(), "description": "Defaults to nearest for Indexed/Bitmap; bicubic for component modes."]
    case "dontEnlarge": return ["type":"boolean", "default":false]
    case "anchor": return ["type": "string", "enum": CanvasAnchor.allCases.map(\.rawValue), "default": "center"]
    case "turn": return ["type": "string", "enum": turns.keys.sorted()]
    case "fill": return ["type": "array", "minItems": 4, "maxItems": 4, "items": ["type": "number", "minimum": 0, "maximum": 1], "description": "RGBA; omitted uses transparency where supported, otherwise white quantized to the current palette."]
    default: return [:]
    }
  }
  static var capabilities: [String: Any] { [
    "fitImage":["command":"document.fitImage", "units":"pixels", "defaultWidth":1024, "defaultHeight":1024,
      "defaultDontEnlarge":false, "actionsVersion":45,
      "behavior":"Resolve the bounding box independently for each input; keep proportions, round the dependent pixel dimension half up with a minimum of1, and optionally leave smaller images unchanged. Retains PPI and uses the native Image Size engine. A no-op may be recorded in Actions without adding Undo. The whole document, including saved channels and masks, is resized regardless of the current editing target.",
      "limits":"Existing geometry mode/storage budgets apply. Frame animation/video resizing is unsupported. Exact Photoshop rounding, Fit Image factory/remembered defaults, Automatic resampling and current live/physical-platform equivalence remain unqualified. No Adobe Fit Image route or action descriptor is advertised."],
    "largeRGB":["maximumDimension":Surface.maxDimension,"maximumPixels":Surface.maxPixels,
      "maximumPatchPixels":RasterGeometry.maximumPatchPixels,"sparseGridSourceTileFastPath":RasterGeometry.sparseGridSourceTileLimit,
      "pagedRasterOutput":true,"exactGridPermutations":true,"preservesSourceEncoding":true,"colouredCanvasExtensions":true,"pagedSavedChannels":true,
      "largeComposite":"Ungrouped raster/fill stacks with integer translations and document-aligned unfeathered raster masks, including inversion/density. General affine placement, groups, clipping, vector/feathered/offset masks and other layer content retain separate large-render limits.",
      "scratchMaximumBytes":RasterTileStore.defaultMaximumBytes,
      "notice":"Raster output streams immutable samples and index pages; grid transforms retain raw/default/HDR/hidden/signed-zero bits.16-bit/8-bit and encoded-sRGB interpolation retain the existing native kernel.32-bit linear interpolation now stays in its source encoding. These are native semantics, not Photoshop kernel equivalence or a physical frame-rate claim."],
    "largeNativeComponents":["maximumDimension":Surface.maxDimension,"maximumPixels":NativeModeRaster.maximumDocumentPixels,
      "minimumAffineAreaScale":Transform2D.minimumDeterminant,"methods":methods.keys.sorted(),"rawComponentOutput":true,"sourceRGBAPlaneRequired":false,"maximumResidentWriteCacheBlocksPerPlane":64,
      "scratchMaximumBytes":RasterTileStore.defaultMaximumBytes,"sparseNearestSupportMaximumBlocks":256,
      "trimImplicitGaps":true,"expandedReframe":true,"boundedDerivedProjection":true,
      "behavior":"Authoritative components use the shared premultiplied sample kernel and checked immutable block output. Nearest full-grid transforms and bounded sparse complete nearest transforms retain implicit defaults. Other interpolation evaluates all required output samples in bounded storage; a dense job may take a long time and remains cancellable. Trim evaluates stored blocks and implicit spans. Reframe selects the larger uniform region and checks scratch admission. Native viewport/channel caches stream bounded RGB patches.",
      "limits":"A logical300,000²canvas is distinct from dense physical storage/time. Scratch/I/O/cancellation failures discard the candidate. Full physical-platform,60fps, metadata/recovery, other component tools/profile/printing/interchange and exact Photoshop/cross-architecture kernel/default fidelity remain open. No new Adobe route or unqualified action descriptor."],
    "commands": commands, "restrictedMaximumPixels": PaletteQuantization.maximumPixels, "inkMaximumPixels": InkPlane.maximumPixels,
    "inkModes": "Duotone geometry transforms its gray source; Multichannel transforms each numeric ink plate. Grid transforms preserve exact8/16-bit samples. Saved alpha masks and selections transform with the canvas. Duotone extension uses gray background/paper; Multichannel extension requires paper (omitted or white fill). Off-canvas ink samples are discarded; Undo restores them.",
    "behavior": "Whole-document geometry uses the desktop commands and one prepared Undo transaction. Width/height are pixels; resolution is pixels/inch. Resolution-only changes never resample. Native color mode, palette and bit storage are retained.",
    "restricted": "Nearest sampling and integer crop/canvas/quarter-turn transforms preserve exact indices, including duplicate colors. Bilinear/bicubic results map back to the current palette or black/white. Bitmap extension is white; Indexed extension is transparent when available, otherwise white mapped to the table. Canvas shrinking discards outside samples; Undo restores them.",
    "limits": "8,388,608 output pixels in Indexed/Bitmap/Duotone/Multichannel. Large GRAY8 selections page their samples and index; dense extraction in remaining consumers retains its36MP guard and unsupported combinations fail atomically. Native component geometry uses bounded raw output; separate ink/restricted and remaining operation limits remain. Exact Photoshop resampling, automatic/Preserve Details variants and corresponding Adobe action descriptors remain unqualified. No Adobe route is added."] }
}

extension AutomationCommand {
  func geometryCommand(in document: CraftDocument) throws -> Command {
    switch name {
    case "selection.shape","selection.inverse","selection.feather":return try selectionGeometryCommand()
    case "document.resize", "document.fitImage":
      let method: Resampling
      if parameters["method"] != nil {
        guard let parsed = GeometryAPI.methods[try string("method")] else { throw AutomationFailure(status: 400, message: "Unknown resampling method.") }
        method = parsed
      } else { method = document.colorMode.isRestricted ? .nearest : .bicubic }
      if name == "document.fitImage" {
        return .fitImage(FitImageOptions(width:try integer("width",range:1...Double(Surface.maxDimension)),
          height:try integer("height",range:1...Double(Surface.maxDimension)),dontEnlarge:try pathFlag("dontEnlarge",false),method:method))
      }
      return .imageSize(try integer("width", range: 1...Double(Surface.maxDimension)), try integer("height", range: 1...Double(Surface.maxDimension)), try parameters["resolution"].map { _ in try number("resolution", range: 1...100000) } ?? document.pixelsPerInch, method)
    case "document.canvasSize":
      let anchor: CanvasAnchor
      if parameters["anchor"] != nil {
        guard let parsed = CanvasAnchor(rawValue: try string("anchor")) else { throw AutomationFailure(status: 400, message: "Unknown canvas anchor.") }
        anchor = parsed
      } else { anchor = .center }
      var fill: Pixel?
      if let raw = parameters["fill"] {
        guard case .array(let values) = raw, values.count == 4 else { throw AutomationFailure(status: 400, message: "Canvas fill requires four RGBA values.") }
        let rgba = try values.map { value -> Float in
          guard case .number(let n) = value, n.isFinite, (0...1).contains(n) else { throw AutomationFailure(status: 400, message: "Invalid canvas fill.") }
          return Float(n)
        }
        fill = Pixel(rgba[0], rgba[1], rgba[2], rgba[3])
      }
      return .canvasSize(try integer("width", range: 1...Double(Surface.maxDimension)), try integer("height", range: 1...Double(Surface.maxDimension)), anchor, fill)
    case "document.rotate":
      guard let turn = GeometryAPI.turns[try string("turn")] else { throw AutomationFailure(status: 400, message: "Unknown canvas turn.") }
      return .rotateCanvas(turn)
    case "document.resolution": return .resolution(try number("resolution", range: 1...100000))
    default: throw AutomationFailure(status: 400, message: "Unknown document geometry command.")
    }
  }
}
