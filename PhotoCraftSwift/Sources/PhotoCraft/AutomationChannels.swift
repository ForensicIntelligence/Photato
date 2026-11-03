import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Explicit Photato channel operations; no invented Adobe routes or action descriptors.
enum ChannelAPI {
  static let actions = ["create","createSpot","configure","delete","duplicate","rename","move","saveSelection","loadSelection","quickMask","quickMaskOptions","options","stroke","fill","invert","filter"]
  static let fields: [String:String] = ["source":"Selection source {kind,id or component}; mutually exclusive with target","newDocument":"Save Selection creates a standalone channel-only document; requires transfers and returns201","sourceDocumentID":"Explicitly shared source document UUID for save/load","sourceRevision":"Required current source revision for cross-document save/load","action":"Channel operation","spot":"Spot ink {color:[r,g,b],solidity:0...1}; null converts to alpha","target":"Alpha UUID or quickMask","name":"Channel name","index":"Zero-based order","mode":"Selection combination","invert":"Invert loaded selection","enabled":"Quick Mask enabled","value":"Grayscale ink, 0–1","opacity":"Paint or overlay opacity","size":"Brush diameter","hardness":"Brush hardness","points":"Stroke samples","filter":"Raster filter","overlayColor":"RGB overlay color","indicates":"maskedAreas or selectedAreas"]
  static var photoshopCapabilities:[String:Any] {[
    "formats":["psd","psb"],"modes":["RGB8/16/32","Grayscale8/16/32","CMYK8/16","Lab8/16"],"maximumTotalChannels":56,
    "preserves":["alpha/spot planes","Quick Mask and initially-empty flag","Unicode names","channel IDs","supported display records","unchanged Float32 spot gray words"],
    "nativeRetentionVersion":77,"compression":["raw","rle","zip","zipPrediction"],
    "routes":["POST /v1/documents/import","GET /v1/documents/{id}/file.psd","GET /v1/documents/{id}/file.psb","document.saveAs","existing PSD/PSB job inputs/outputs"],
    "limits":"56 total process/transparency/saved/Quick Mask planes. Opacity/Solidity store whole percentages and changed display colors use16-bit RGB; supported imported records reuse exact bytes. New native-density-to-Float32-gray conversion has format rounding; imported unmodified source gray is retained exactly. Private color-book records, TIFF extra-plane mapping, multiple visible spots/Merge/print policy and full Photoshop/platform/output qualification remain open. Native-mode raster and file/API/scratch budgets apply separately."
  ]}
  static var capabilities: [String:Any] { ["selectionWorkflow":["quickMaskVisibility":"channel.view target quickMask accepts optional visible boolean. The eye only hides/shows its overlay; Quick Mask mode, edit target, pixels, history and tool cursors are retained. quickMaskVisible state is false without an active mask. Visibility is document-local session state, scoped to the temporary mask identity; a new mask starts visible. Brush strokes on a hidden Quick Mask return422 without modifying coverage; show it before painting. Other hidden-target tool contexts retain separate qualification.","luminosity":"Composite sources use document ICC interpretation and captured workingGray. The relative/BPC standard sRGB-to-DotGain20 RGB8 pair uses a verified precompiled full transform, covering every RGB8 input. Other RGB matrix/shaper plus gray curves are evaluated directly from standard ICC fields; complex/absolute/nonzero-black-point transforms use ColorSync with full Photoshop CMM fidelity still open. Default8/16 gray is Dot Gain20;32 gray is linear. Color Settings changes before commit reject atomically.","sources":SelectionChannelSourceAPI.kinds,"sourceSchema":SelectionChannelSourceAPI.schema,"newDocument":["action":"saveSelection","newDocument":true,"nativeArchiveVersion":85,"resultStatus":201,"requiresDocumentTransfers":true,"model":"Multichannel with auxiliary mask channels and no printing or image layers.8/16-bit PSD/PSB and all-depth native85 preservation.32-bit standalone PSD is unavailable, matching the observed Photoshop save failure; use Photato."],"combination":"Channel Add uses a+b-round(a*b/255), Subtract uses a-round(a*b/255), Intersect uses round(a*b/255) at8-bit selection precision; geometric selection-tool combinations are separate.","crossDocument":"saveSelection/loadSelection accept sourceDocumentID/sourceRevision for explicitly shared, equal-size source snapshots. Only the destination changes, with one Undo; changed/closed/revoked sources reject atomically.","quickMaskOptions":"quickMaskOptions changes persistent shared display defaults and an active mask; quickMask accepts optional overlayColor/opacity/indicates for entry. Q, double-click options and Option-click indication are native controls.","reference":"docs/QUICK_MASK_SELECTION_REFERENCES.json"],"transformCommand":"channel.transform","transformActionsVersion":36,"editCommand":"channel.edit","viewCommand":"channel.view","actions":actions,"maximumAlphaChannels":CraftDocument.maximumAlphaChannels,"photoshopInterchange":photoshopCapabilities,"storage":"Native20 alpha/Quick Mask and native76 auxiliary spot channels at document depth; native files retain alpha channels and temporary Quick Mask. Large selection coverage uses native64 paging.","spotChannels":["archiveVersion":76,"create":"createSpot starts with selection density or empty paper; optional value supplies uniform initial density.","configure":"Atomic name/options/spot metadata; alpha/spot conversion preserves editing gray. Solidity changes preview only. The original raw density convention is zero=paper, one=ink.","view":"Select spot gray or overlay via channel.view; overlay uses the licensed source overprint equation for the selected channel.","limits":"No simultaneous auxiliary spot visibility, spot Merge, color-library catalog or semantic channel Actions beyond transforms36yet; full Photoshop prepress qualification remains open."],"painting":"For spots, black adds ink, white removes it and gray adds partial density. For alpha, black protects; white selects. selectedAreas reverses displayed gray and paint interpretation without changing stored coverage. Existing selection limits channel painting.","filters":"Channel filtering rejects Camera Raw, Puppet Warp and Perspective Warp, which require an RGB image target.","largePresentation":["maximumBufferPixels":RasterPreviewRequest.maximumPixels,"apiMaximumSide":2048,"channelPreview":"RGB components, alpha gray/overlay and Quick Mask use the shared bounded native projection. Numeric coverage ignores source alpha; overlays reduce composite and coverage before display mixing.","layerMaskResources":["layers/{layerID}/mask-gray.png","layers/{layerID}/mask-overlay.png"],"maskSampling":"Raw editable mask at document-space pixel centers; reduced masks sample output-cell centers. General rich-stack composition and Photoshop preview-filter fidelity remain open."],"interchange":"PSD/PSB ordinary-mode alpha/spot/Quick Mask planes, names, display records and identifiers are retained; Float32 spots keep source gray for exact unchanged words (native77). Unsupported color-book records, TIFF auxiliary mapping and full Photoshop preview/print qualification remain open. Flat image exports contain the image composite only.","adobe":"No dedicated published channel or mask-preview endpoint. Channel actionJSON descriptors remain explicitly unsupported; no Adobe route is invented."] }
  static var spotSchema:[String:Any] { ["anyOf":[["type":"null"],["type":"object","additionalProperties":false,"required":["color","solidity"],"properties":["color":["type":"array","minItems":3,"maxItems":3,"items":["type":"number","minimum":0,"maximum":1]],"solidity":["type":"number","minimum":0,"maximum":1]]]]] }
  static func state(_ channel:AlphaChannel)->[String:Any] {
    ["id":channel.id.uuidString,"name":channel.name,"opacity":channel.options.opacity,"indicates":channel.options.indicates.rawValue,"color":[channel.options.color.r,channel.options.color.g,channel.options.color.b],"kind":channel.spot == nil ? "alpha":"spot","psd":["identifier":channel.psdIdentifier.map{Int($0) as Any} ?? NSNull(),"retainedDisplay":channel.psdDisplay != nil,"retainedFloat32SpotGray":channel.psdSpotGray != nil,"quickMaskInitiallyEmpty":channel.psdQuickMaskInitiallyEmpty.map{$0 as Any} ?? NSNull()],"spot":channel.spot.map{["color":[$0.color.r,$0.color.g,$0.color.b],"solidity":$0.solidity]as[String:Any]} ?? NSNull()]
  }
  static func parameterSchema(_ key: String) -> [String:Any]? {
    switch key {
    case "spot":return spotSchema
    case "source":return SelectionChannelSourceAPI.schema
    case "newDocument":return ["type":"boolean","default":false]
    case "sourceDocumentID":return ["type":"string","format":"uuid"]
    case "sourceRevision":return ["type":"string","minLength":1,"maxLength":256]
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
  func channelEdit(document: CraftDocument,defaults:ChannelDisplayOptions = .init(),allowExternalSource:Bool = false) throws -> Command {
    let action = try string("action")
    guard parameters["source"] == nil else{throw AutomationFailure(status:422,message:"A selection source requires native imaging preparation.")}
    guard !(try pathFlag("newDocument",false)) else{throw AutomationFailure(status:422,message:"Creating a selection document requires the shared document lifecycle.")}
    guard allowExternalSource || (parameters["sourceDocumentID"] == nil && parameters["sourceRevision"] == nil) else {
      throw AutomationFailure(status:422,message:"Cross-document selection transfers require an explicitly shared source lease.")
    }
    let allowed: [String:Set<String>] = [
      "create":["name","value"],"createSpot":["name","value","spot"],"configure":["target","name","overlayColor","opacity","indicates","spot"],"delete":["target"],"duplicate":["target","name"],"rename":["target","name"],"move":["target","index"],
      "saveSelection":["target","name","mode","sourceDocumentID","sourceRevision","newDocument"],"loadSelection":["target","mode","invert","sourceDocumentID","sourceRevision"],"quickMask":["enabled","overlayColor","opacity","indicates"],
      "options":["target","overlayColor","opacity","indicates"],"stroke":["target","points","size","hardness","opacity","value"],
      "fill":["target","value","opacity"],"invert":["target"],"filter":["target","filter"]]
    guard let keys = allowed[action], Set(parameters.keys).subtracting(["action"]).isSubset(of:keys) else { throw AutomationFailure(status:400,message:"Unknown channel action or parameter for this action.") }
    func flag(_ key: String, default fallback: Bool = false) throws -> Bool {
      guard let raw = parameters[key] else { return fallback }; guard case .bool(let v) = raw else { throw AutomationFailure(status:400,message:"\(key) must be boolean.") }; return v
    }
    func value(_ key: String, default fallback: Double, range: ClosedRange<Double> = 0...1) throws -> Double { parameters[key] == nil ? fallback:try number(key,range:range) }
    func alpha() throws -> UUID { guard case .alpha(let id) = try channelTarget() else { throw AutomationFailure(status:400,message:"This action requires an alpha channel UUID.") }; return id }
    func mode() throws -> SelectionMode { guard parameters["mode"] != nil else { return .replace }; guard let mode = SelectionMode(rawValue:try string("mode")) else { throw AutomationFailure(status:400,message:"Invalid selection mode.") }; return mode }
    func spot()throws->SpotInk? {
      guard let raw=parameters["spot"] else{return nil};if case .null=raw{return nil}
      guard case .object(let fields)=raw,Set(fields.keys)==Set(["color","solidity"]),case .array(let color)=fields["color"],color.count==3,case .number(let solidity)=fields["solidity"],solidity.isFinite,(0...1).contains(solidity)else{throw AutomationFailure(status:400,message:"spot requires RGB color and solidity.")}
      let rgb=try color.map{value->Float in guard case .number(let n)=value,n.isFinite,(0...1).contains(n)else{throw AutomationFailure(status:400,message:"Invalid spot color.")};return Float(n)}
      return SpotInk(color:Pixel(rgb[0],rgb[1],rgb[2]),solidity:Float(solidity))
    }
    let name = try parameters["name"].map { _ in try string("name") }
    let command: ChannelCommand
    switch action {
    case "createSpot":
      let ink=try spot() ?? SpotInk()
      command = .create(try document.newSpotChannel(name:name ?? "Spot Color",ink:ink,density:parameters["value"] == nil ? nil:Float(number("value",range:0...1))))
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
      command = try .quickMask(flag("enabled"),channelDisplayOptions(document.quickMask?.options ?? defaults))
    case "options","configure":
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
      if action == "configure" {
        let id=try alpha(),old=try document.channel(.alpha(id))
        command = .configure(id,name ?? old.name,options,parameters["spot"] == nil ? old.spot:try spot())
      }else{command = .options(target,options)}
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
