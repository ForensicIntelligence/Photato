import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension VanishingScene {
  var apiValue:[String:Any] { ["focalLength":focal,"center":["x":center.x,"y":center.y],"planes":frames.map{["corners":$0.corners.map{["x":$0.x,"y":$0.y]},"metricWidth":$0.width,"metricHeight":$0.height] as [String:Any]}] }
}
extension VanishingSettings {
  var apiValue:Any { (try? JSONSerialization.jsonObject(with:JSONEncoder().encode(self))) ?? NSNull() }
  static var pointSchema:[String:Any] { ["type":"object","additionalProperties":false,"required":["x","y"],"properties":Dictionary(uniqueKeysWithValues:["x","y"].map{($0,["type":"number","minimum":-1_000_000,"maximum":1_000_000] as [String:Any])})] }
  static var apiSchema:[String:Any] {
    let corners: [String: Any] = ["type":"array","minItems":4,"maxItems":4,"items":pointSchema]
    let orientation: [String: Any] = ["type":"number","enum":[-1,1]]
    let calibration: [String: Any] = ["type":"object","additionalProperties":false,
      "required":["corners","parentCorners","angle","depth","rotationSign"],"properties":[
        "corners":corners,"parentCorners":corners,
        "angle":["type":"number","minimum":0,"maximum":180],
        "depth":["type":"number","exclusiveMinimum":0],"rotationSign":orientation]]
    return ["type":"object","additionalProperties":false,"properties":["focalLength":["type":"number","minimum":0,"default":0,
      "description":"Finite focal length in pixels. Zero infers the camera or uses the longer canvas side. The resulting projection must be valid."],"center":pointSchema,
      "gridSize":["type":"number","minimum":gridSizeRange.lowerBound,"maximum":gridSizeRange.upperBound,
                  "default":defaultGridSize,"description":"Grid spacing shared by all planes."],
      "planes":["type":"array","maxItems":32,"default":[],"items":["type":"object","additionalProperties":false,"properties":[
        "corners":["type":"array","minItems":0,"maxItems":4,"items":pointSchema,"default":[]],"parent":["type":"integer","minimum":0,"maximum":30],"edge":["type":"string","enum":VanishingPlane.Edge.allCases.map(\.rawValue),"default":"top"],"angle":["type":"number","minimum":0,"maximum":180,"default":90],"depth":["type":"number","exclusiveMinimum":0,"default":1],"rotationSign":orientation,"calibration":calibration],"description":"Four convex corners in document pixels, or an earlier parent index with empty corners. Related planes recompute when their parent changes."]]]]
  }
  static var operationSchema:[String:Any] {
    let number:(Double,Double,Double)->[String:Any] = { ["type":"number","minimum":$0,"maximum":$1,"default":$2] }
    let color:[String:Any]=["type":"object","additionalProperties":false,"required":["r","g","b","a"],"properties":Dictionary(uniqueKeysWithValues:["r","g","b","a"].map{($0,number(0,1,$0 == "a" ? 1:0))})]
    let shared:[String:Any]=["plane":["type":"integer","minimum":0,"maximum":31,"default":0],"opacity":number(0,100,100),"clip":["type":"boolean","default":true],
      "heal":["type":"string","enum":VanishingOperation.Heal.allCases.map(\.rawValue),"default":"off"]]
    let variants=VanishingOperation.Kind.allCases.map { kind -> [String:Any] in
      var properties=shared;properties["kind"]=["const":kind.rawValue];var required=["kind"]
      if kind == .paste { properties["sourceLayerID"]=["type":"string","format":"uuid"];properties["at"]=pointSchema;properties["width"]=number(0.001,20,0.5);properties["angle"]=number(-360,360,0);required.append("sourceLayerID") }
      else { properties["points"]=["type":"array","minItems":1,"maxItems":4096,"items":pointSchema];properties["diameter"]=number(1,2000,40);properties["hardness"]=number(0,100,50);required.append("points")
        if kind == .clone { properties["sourcePoint"]=pointSchema;required.append("sourcePoint") } else { properties["color"]=color }
      }
      return ["type":"object","additionalProperties":false,"required":required,"properties":properties]
    }
    return ["type":"array","maxItems":256,"items":["oneOf":variants],"default":[]]
  }
  static var apiCapabilities:[String:Any] {
    ["command":"filter.vanishingPoint","settingsSchema":apiSchema,"operationsSchema":operationSchema,"nativeArchiveVersion":32,
     "narrowStrokeCoverage":"Brush and clone footprints that project to about a pixel thick or less use area coverage and honor plane clipping. Coverage work shares the Vanishing Point rendering budget.",
     "coordinates":"Corners and stroke/source points are document pixels. Paste at is plane(u,v), width is a fraction of metric plane width, rotation clockwise about paste origin. Focal length is in pixels; zero infers from the first plane or falls back to the longer canvas side.",
     "state":"Document and workspace state include resolved camera/plane corners and metric dimensions so clients can draw derived planes without reimplementing the solver.",
     "operations":"Create/save/edit planes with no operations; brush, clone and perspective paste with sourceLayerID (raw raster layer pixels, resolved before mutation). Sequential operations sample the visible composite plus earlier draft operations; each clone stroke takes an immutable source snapshot.",
     "heal":"Brush, clone and paste accept off, luminance or on. Luminance adjusts lighting. On adjusts lighting and color. The gradient-domain solve includes a one-pixel boundary within the 4-megapixel local repair budget.",
     "output":"The current raster layer can expand to cover the repair while keeping existing samples and masks in place. Use newLayer:true for a separate layer. Selection and transparency/image locks are honored. Smart Objects must be rasterized for the target. One cancellable undo transaction for the entire program.",
     "limits":"32 planes,256 operations,16,384 supplied points,4,096 points per stroke,128MiB embedded paste sources with up to 8,388,608 pixels, up to \(Surface.maxDimension) pixels per canvas side, 134,217,728 raster visits per program. Large canvases use a bounded overview. Existing API sharing limits also apply.",
     "fileInterchange":"PSD and PSB open supported Photoshop perspective planes and retain the original resource when geometry is unchanged. Edited and newly created planes are written as Photoshop resource 4000.",
     "unsupported":"Perspective marquee/measurement, multi-surface stroke wrapping, Adobe .vpe export and exact Adobe pixels remain unqualified or absent. Recorded Actions currently report Vanishing Point as unsupported; direct API and desktop are available.",
     "adobe":"No dedicated pinned v2 Vanishing Point operation. No invented route or unqualified actionJSON support."]
  }
}
extension AutomationCommand {
  func vanishingOptions(in document:CraftDocument) throws -> (UUID,VanishingProgram) {
    func fail(_ message:String)->AutomationFailure { .init(status:400,message:message) }
    guard let id=UUID(uuidString:try string("layerID")) else { throw fail("Invalid layerID.") }
    var p=VanishingProgram();p.settings=document.vanishingPoint ?? .init()
    if let value=parameters["newLayer"] { guard case .bool(let b)=value else { throw fail("newLayer must be boolean.") };p.newLayer=b }
    if let value=parameters["settings"] {
      guard case .object(let fields)=value,Set(fields.keys).isSubset(of:["planes","focalLength","center","gridSize"]) else { throw fail("Invalid plane settings.") }
      var raw:[String:Any]=["planes":[],"focalLength":0]
      if let size = p.settings.gridSize { raw["gridSize"] = size }
      for (k,v) in fields { raw[k]=v.jsonValue }
      if let items=raw["planes"] {
        guard let items=items as? [[String:Any]],items.count<=32 else { throw fail("Invalid planes.") }
        raw["planes"]=try items.map { value -> [String:Any] in
          guard Set(value.keys).isSubset(of:["corners","parent","edge","angle","depth","rotationSign","calibration"]) else { throw fail("Unknown plane field.") }
          if let rawCalibration = value["calibration"] {
            guard let calibration = rawCalibration as? [String:Any],
              Set(calibration.keys) == ["corners","parentCorners","angle","depth","rotationSign"] else {
              throw fail("Invalid related plane calibration.")
            }
          }
          var d:[String:Any]=["corners":[],"edge":"top","angle":90,"depth":1];d.merge(value){_,new in new};return d
        }
      }
      func pointsAreStrict(_ value:Any)->Bool { if let d=value as? [String:Any] { for (k,v) in d { if k == "center" { guard let q=v as? [String:Any],Set(q.keys)==["x","y"] else { return false } };if k == "corners" || k == "parentCorners" { guard let q=v as? [[String:Any]],q.allSatisfy({Set($0.keys)==["x","y"]}) else { return false } };if !pointsAreStrict(v) { return false } } };if let a=value as? [Any] { return a.allSatisfy(pointsAreStrict) };return true }
      guard pointsAreStrict(raw) else { throw fail("Invalid plane coordinates.") }
      do {
        p.settings = try JSONDecoder().decode(VanishingSettings.self,from:JSONSerialization.data(withJSONObject:raw))
        try p.settings.validate()
        if p.settings.gridSize == VanishingSettings.defaultGridSize { p.settings.gridSize = nil }
      } catch { throw fail(error.localizedDescription) }
    }
    if let value=parameters["operations"] {
      guard case .array(let items)=value,items.count<=256 else { throw fail("Invalid operations.") }
      p.operations=try items.map { item in
        guard case .object(let fields)=item,case .string(let name)=fields["kind"],let kind=VanishingOperation.Kind(rawValue:name) else { throw fail("Invalid operation kind.") }
        let allowed:Set<String>=kind == .paste ? ["kind","plane","at","width","angle","opacity","clip","sourceLayerID"]:kind == .clone ? ["kind","plane","points","sourcePoint","diameter","hardness","opacity","clip"]:["kind","plane","points","diameter","hardness","opacity","color","clip"]
        guard Set(fields.keys).isSubset(of:allowed.union(["heal"])) else { throw fail("Unknown or irrelevant operation field.") }
        if let heal = fields["heal"] {
          guard case .string(let mode) = heal, VanishingOperation.Heal(rawValue: mode) != nil else {
            throw fail("Heal must be off, luminance or on.")
          }
        }
        var raw=try JSONSerialization.jsonObject(with:JSONEncoder().encode(VanishingOperation(kind))) as! [String:Any]
        for (k,v) in fields where k != "sourceLayerID" { raw[k]=v.jsonValue }
        for key in ["at","sourcePoint"] { if let value=raw[key] { guard let point=value as? [String:Any],Set(point.keys)==["x","y"] else { throw fail("Invalid operation point.") } } }
        if let values=raw["points"] { guard let points=values as? [[String:Any]],points.allSatisfy({Set($0.keys)==["x","y"]}) else { throw fail("Invalid stroke points.") } }
        if let value=raw["color"] { guard let c=value as? [String:Any],Set(c.keys)==["r","g","b","a"] else { throw fail("Invalid paint color.") } }
        if case .object(let c)=fields["color"] { guard c.values.allSatisfy({ if case .number(let n)=$0 { return n.isFinite && (0...1).contains(n) };return false }) else { throw fail("Color channels must be numbers from0 to1.") } }
        var op:VanishingOperation
        do { op=try JSONDecoder().decode(VanishingOperation.self,from:JSONSerialization.data(withJSONObject:raw)) } catch { throw fail(error.localizedDescription) }
        if kind == .paste {
          guard case .string(let source)=fields["sourceLayerID"],let sourceID=UUID(uuidString:source),let layer=document.layers.first(where:{$0.id==sourceID}),case .raster(let pixels)=layer.content else { throw fail("Paste sourceLayerID must identify a raster layer in this document.") };op.source=pixels
        }
        return op
      }
    }
    do { try p.validate() } catch { throw fail(error.localizedDescription) };return (id,p)
  }
}
@MainActor extension VanishingWorkspace {
  var apiState:[String:Any] { ["settings":program.settings.apiValue,"scene":scene?.apiValue as Any? ?? NSNull(),"operationCount":program.operations.count,"newLayer":program.newLayer,"tool":tool.rawValue,"selectedPlane":selected,"pendingCorners":pending.count,"preview":preview,"rendering":rendering,"zoom":zoom,"showGrid":showGrid,"gridSize":gridSize,"canUndo":!undoStates.isEmpty || !pending.isEmpty,"canRedo":!redoStates.isEmpty,"heal":heal.rawValue,"selectedPasteHeal":selectedPasteHeal?.rawValue as Any? ?? NSNull(),"error":error as Any? ?? NSNull()] }
}
