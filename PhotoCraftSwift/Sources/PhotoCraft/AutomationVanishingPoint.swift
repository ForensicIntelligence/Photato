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
    ["type":"object","additionalProperties":false,"properties":["focalLength":["type":"number","minimum":0,"maximum":100_000,"default":0],"center":pointSchema,
      "planes":["type":"array","maxItems":32,"default":[],"items":["type":"object","additionalProperties":false,"properties":[
        "corners":["type":"array","minItems":0,"maxItems":4,"items":pointSchema,"default":[]],"parent":["type":"integer","minimum":0,"maximum":30],"edge":["type":"string","enum":VanishingPlane.Edge.allCases.map(\.rawValue),"default":"top"],"angle":["type":"number","minimum":0,"maximum":180,"default":90],"depth":["type":"number","minimum":0.05,"maximum":20,"default":1]],"description":"Four convex corners in document pixels, or an earlier parent index with empty corners. Related planes recompute when their parent changes."]]]]
  }
  static var operationSchema:[String:Any] {
    let number:(Double,Double,Double)->[String:Any] = { ["type":"number","minimum":$0,"maximum":$1,"default":$2] }
    let color:[String:Any]=["type":"object","additionalProperties":false,"required":["r","g","b","a"],"properties":Dictionary(uniqueKeysWithValues:["r","g","b","a"].map{($0,number(0,1,$0 == "a" ? 1:0))})]
    let shared:[String:Any]=["plane":["type":"integer","minimum":0,"maximum":31,"default":0],"opacity":number(0,100,100),"clip":["type":"boolean","default":true]]
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
     "coordinates":"Corners and stroke/source points are document pixels. Paste at is plane(u,v), width is a fraction of metric plane width, rotation clockwise about paste origin. Focal length is in pixels; zero infers from the first plane or falls back to the longer canvas side.",
     "state":"Document and workspace state include resolved camera/plane corners and metric dimensions so clients can draw derived planes without reimplementing the solver.",
     "operations":"Create/save/edit planes with no operations; brush, clone and perspective paste with sourceLayerID (raw raster layer pixels, resolved before mutation). Sequential operations sample the visible composite plus earlier draft operations; each clone stroke takes an immutable source snapshot.",
     "output":"Current raster layer or newLayer:true; original placement/masks preserved, selection and transparency/image locks honored. Smart Objects must be rasterized for the target. One cancellable prepared undo transaction for the entire program.",
     "limits":"32 planes,256 operations,16,384 supplied points,4,096 points per stroke,128MiB embedded paste sources,8,388,608 canvas/target pixels,134,217,728 raster visits. Existing API sharing limits also apply.",
     "unsupported":"Perspective marquee/measurement, healing, multi-surface stroke wrapping, Adobe .vpe/PSD plane metadata and exact Adobe pixels remain unqualified or absent. Recorded Actions currently report Vanishing Point as unsupported; direct API and desktop are available.",
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
      guard case .object(let fields)=value,Set(fields.keys).isSubset(of:["planes","focalLength","center"]) else { throw fail("Invalid plane settings.") }
      var raw:[String:Any]=["planes":[],"focalLength":0];for (k,v) in fields { raw[k]=v.jsonValue }
      if let items=raw["planes"] {
        guard let items=items as? [[String:Any]],items.count<=32 else { throw fail("Invalid planes.") }
        raw["planes"]=try items.map { value -> [String:Any] in
          guard Set(value.keys).isSubset(of:["corners","parent","edge","angle","depth"]) else { throw fail("Unknown plane field.") }
          var d:[String:Any]=["corners":[],"edge":"top","angle":90,"depth":1];d.merge(value){_,new in new};return d
        }
      }
      func pointsAreStrict(_ value:Any)->Bool { if let d=value as? [String:Any] { for (k,v) in d { if k == "center" { guard let q=v as? [String:Any],Set(q.keys)==["x","y"] else { return false } };if k == "corners" { guard let q=v as? [[String:Any]],q.allSatisfy({Set($0.keys)==["x","y"]}) else { return false } };if !pointsAreStrict(v) { return false } } };if let a=value as? [Any] { return a.allSatisfy(pointsAreStrict) };return true }
      guard pointsAreStrict(raw) else { throw fail("Invalid plane coordinates.") }
      do { p.settings=try JSONDecoder().decode(VanishingSettings.self,from:JSONSerialization.data(withJSONObject:raw));try p.settings.validate() } catch { throw fail(error.localizedDescription) }
    }
    if let value=parameters["operations"] {
      guard case .array(let items)=value,items.count<=256 else { throw fail("Invalid operations.") }
      p.operations=try items.map { item in
        guard case .object(let fields)=item,case .string(let name)=fields["kind"],let kind=VanishingOperation.Kind(rawValue:name) else { throw fail("Invalid operation kind.") }
        let allowed:Set<String>=kind == .paste ? ["kind","plane","at","width","angle","opacity","clip","sourceLayerID"]:kind == .clone ? ["kind","plane","points","sourcePoint","diameter","hardness","opacity","clip"]:["kind","plane","points","diameter","hardness","opacity","color","clip"]
        guard Set(fields.keys).isSubset(of:allowed) else { throw fail("Unknown or irrelevant operation field.") }
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
  var apiState:[String:Any] { ["settings":program.settings.apiValue,"scene":scene?.apiValue as Any? ?? NSNull(),"operationCount":program.operations.count,"newLayer":program.newLayer,"tool":tool.rawValue,"selectedPlane":selected,"pendingCorners":pending.count,"preview":preview,"rendering":rendering,"zoom":zoom,"showGrid":showGrid,"gridSize":gridSize,"canUndo":!undoStates.isEmpty || !pending.isEmpty,"canRedo":!redoStates.isEmpty,"error":error as Any? ?? NSNull()] }
}
