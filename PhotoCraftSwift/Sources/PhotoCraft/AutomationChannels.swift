import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Explicit Photato channel operations; no invented Adobe routes or action descriptors.
enum ChannelAPI {
  static let actions = ["create","delete","duplicate","rename","move","saveSelection","loadSelection","quickMask","options","stroke","fill","invert","filter"]
  static let fields: [String:String] = ["action":"Channel operation","target":"Alpha UUID or quickMask","name":"Channel name","index":"Zero-based order","mode":"Selection combination","invert":"Invert loaded selection","enabled":"Quick Mask enabled","value":"Grayscale ink, 0–1","opacity":"Paint or overlay opacity","size":"Brush diameter","hardness":"Brush hardness","points":"Stroke samples","filter":"Raster filter","overlayColor":"RGB overlay color","indicates":"maskedAreas or selectedAreas"]
  static var capabilities: [String:Any] { ["editCommand":"channel.edit","viewCommand":"channel.view","actions":actions,"maximumAlphaChannels":CraftDocument.maximumAlphaChannels,"storage":"Native20 grayscale at document depth; native files retain alpha channels and temporary Quick Mask. Large selection coverage uses native64 paging.","painting":"Black protects; white selects. selectedAreas reverses displayed gray and paint interpretation without changing stored coverage. Existing selection limits channel painting.","filters":"Channel filtering rejects Camera Raw, Puppet Warp and Perspective Warp, which require an RGB image target.","largePresentation":["maximumBufferPixels":RasterPreviewRequest.maximumPixels,"apiMaximumSide":2048,"channelPreview":"RGB components, alpha gray/overlay and Quick Mask use the shared bounded native projection. Numeric coverage ignores source alpha; overlays reduce composite and coverage before display mixing.","layerMaskResources":["layers/{layerID}/mask-gray.png","layers/{layerID}/mask-overlay.png"],"maskSampling":"Raw editable mask at document-space pixel centers; reduced masks sample output-cell centers. General rich-stack composition and Photoshop preview-filter fidelity remain open."],"interchange":"PSD/PSB channel interchange and spot ink are pending; export rejects channel-bearing documents instead of dropping masks. Flat image exports contain the image composite only.","adobe":"No dedicated published channel or mask-preview endpoint. Channel actionJSON descriptors remain explicitly unsupported; no Adobe route is invented."] }
  static func parameterSchema(_ key: String) -> [String:Any]? {
    switch key {
    case "action": return ["type":"string","enum":actions]
    case "target": return ["type":"string","pattern":"^(quickMask|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$"]
    case "index": return ["type":"integer","minimum":0,"maximum":51]
    case "indicates": return ["type":"string","enum":ChannelDisplayOptions.Indicates.allCases.map(\.rawValue)]
    case "overlayColor": return ["type":"array","minItems":3,"maxItems":3,"items":["type":"number","minimum":0,"maximum":1]]
    case "enabled","invert","overlay": return ["type":"boolean"]
    default: return nil
    }
  }
}
extension AutomationCommand {
  func channelTarget() throws -> ChannelPlaneTarget {
    let name = try string("target")
    if name == "quickMask" { return .quickMask }
    guard let id = UUID(uuidString:name) else { throw AutomationFailure(status:400,message:"Invalid channel target.") }
    return .alpha(id)
  }
  func channelEdit(document: CraftDocument) throws -> Command {
    let action = try string("action")
    let allowed: [String:Set<String>] = [
      "create":["name","value"],"delete":["target"],"duplicate":["target","name"],"rename":["target","name"],"move":["target","index"],
      "saveSelection":["target","name","mode"],"loadSelection":["target","mode","invert"],"quickMask":["enabled"],
      "options":["target","overlayColor","opacity","indicates"],"stroke":["target","points","size","hardness","opacity","value"],
      "fill":["target","value","opacity"],"invert":["target"],"filter":["target","filter"]]
    guard let keys = allowed[action], Set(parameters.keys).subtracting(["action"]).isSubset(of:keys) else { throw AutomationFailure(status:400,message:"Unknown channel action or parameter for this action.") }
    func flag(_ key: String, default fallback: Bool = false) throws -> Bool {
      guard let raw = parameters[key] else { return fallback }; guard case .bool(let v) = raw else { throw AutomationFailure(status:400,message:"\(key) must be boolean.") }; return v
    }
    func value(_ key: String, default fallback: Double, range: ClosedRange<Double> = 0...1) throws -> Double { parameters[key] == nil ? fallback:try number(key,range:range) }
    func alpha() throws -> UUID { guard case .alpha(let id) = try channelTarget() else { throw AutomationFailure(status:400,message:"This action requires an alpha channel UUID.") }; return id }
    func mode() throws -> SelectionMode { guard parameters["mode"] != nil else { return .replace }; guard let mode = SelectionMode(rawValue:try string("mode")) else { throw AutomationFailure(status:400,message:"Invalid selection mode.") }; return mode }
    let name = try parameters["name"].map { _ in try string("name") }
    let command: ChannelCommand
    switch action {
    case "create":
      let gray = Float(try value("value",default:0))
      command = .create(AlphaChannel(name:name ?? document.suggestedChannelName,pixels:try Surface(width:document.width,height:document.height,depth:document.depth,fill:Pixel(gray,gray,gray))))
    case "delete": command = try .delete(alpha())
    case "duplicate": command = try .duplicate(alpha(),name)
    case "rename": command = try .rename(alpha(),string("name"))
    case "move": command = try .move(alpha(),integer("index",range:0...51))
    case "saveSelection": command = try .saveSelection(parameters["target"] == nil ? nil:alpha(),name,mode())
    case "loadSelection": command = try .load(channelTarget(),mode(),flag("invert"))
    case "quickMask":
      guard parameters["enabled"] != nil else { throw AutomationFailure(status:400,message:"enabled is required.") }
      command = try .quickMask(flag("enabled"),document.quickMask?.options ?? .init())
    case "options":
      let target = try channelTarget(); var options = try document.channel(target).options
      if parameters["opacity"] != nil { options.opacity = Float(try number("opacity",range:0...1)) }
      if parameters["indicates"] != nil {
        guard let v = ChannelDisplayOptions.Indicates(rawValue:try string("indicates")) else { throw AutomationFailure(status:400,message:"Invalid indicates.") }; options.indicates = v
      }
      if let color = parameters["overlayColor"] {
        guard case .array(let a) = color, a.count == 3 else { throw AutomationFailure(status:400,message:"overlayColor requires three RGB numbers.") }
        let values = try a.map { v -> Float in guard case .number(let n) = v, n.isFinite, (0...1).contains(n) else { throw AutomationFailure(status:400,message:"Invalid overlay color.") }; return Float(n) }
        options.color = Pixel(values[0],values[1],values[2])
      }
      command = .options(target,options)
    case "stroke":
      guard case .array(let raw) = parameters["points"], !raw.isEmpty, raw.count <= 4096 else { throw AutomationFailure(status:400,message:"Supply 1–4096 stroke points.") }
      let points = try raw.map { v -> StrokePoint in
        guard case .object(let p) = v, Set(p.keys).isSubset(of:["x","y","pressure"]) else { throw AutomationFailure(status:400,message:"Invalid point.") }
        func n(_ key: String) throws -> Double { guard case .number(let n) = p[key], n.isFinite, abs(n) <= 1_000_000 else { throw AutomationFailure(status:400,message:"Invalid point coordinate.") }; return n }
        let pressure = p["pressure"] == nil ? 1:try n("pressure")
        guard (0...1).contains(pressure) else { throw AutomationFailure(status:400,message:"Invalid pressure.") }
        return try StrokePoint(x:n("x"),y:n("y"),pressure:Float(pressure))
      }
      var brush = Brush(); brush.size = try value("size",default:20,range:0.5...2048); brush.hardness = Float(try value("hardness",default:1)); brush.opacity = Float(try value("opacity",default:1))
      let gray = Float(try value("value",default:0)); brush.color = Pixel(gray,gray,gray)
      command = try .stroke(channelTarget(),points,brush)
    case "fill": command = try .fill(channelTarget(),Float(number("value",range:0...1)),Float(value("opacity",default:1)))
    case "invert": command = try .invert(channelTarget())
    case "filter":
      guard let raw = parameters["filter"] else { throw AutomationFailure(status:400,message:"filter is required.") }
      command = try .filter(channelTarget(),RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject:raw.jsonValue)))
    default: throw AutomationFailure(status:400,message:"Unknown channel action.")
    }
    return .channel(command)
  }
}
