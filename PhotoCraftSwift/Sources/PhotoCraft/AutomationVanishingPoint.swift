import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension VanishingScene {
  func apiValue(settings: VanishingSettings) -> [String:Any] {
    let lines = (settings.measurements ?? []).enumerated().map { index,line -> [String:Any] in
      let frame = frames[line.plane]
      func point(_ p: PathPoint) -> [String:Double] { ["x":p.x,"y":p.y] }
      return ["plane":line.plane,"root":measurementRoot(for:line.plane),
        "start":point(frame.point(line.start)),"end":point(frame.point(line.end)),
        "length":measurementLength(line,settings:settings) as Any? ?? NSNull(),
        "angleDegrees":measurementAngle(line,settings:settings,excluding:index) as Any? ?? NSNull()]
    }
    return ["focalLength":focal,"center":["x":center.x,"y":center.y],
      "planes":frames.enumerated().map { index, frame in
        let grid = gridIntervals(for:index,settings:settings)
        return ["corners":frame.corners.map{["x":$0.x,"y":$0.y]},"metricWidth":frame.width,"metricHeight":frame.height,
          "measurementRoot":measurementRoot(for:index),"gridIntervals":["x":grid.x,"y":grid.y]]
      },"measurements":lines]
  }
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
    let planeIndex: [String:Any] = ["type":"integer","minimum":0,"maximum":31]
    let measurement: [String:Any] = ["type":"object","additionalProperties":false,
      "required":["plane","start","end"],"properties":["plane":planeIndex,"start":pointSchema,"end":pointSchema]]
    let scale: [String:Any] = ["type":"object","additionalProperties":false,
      "required":["root","pixelsPerUnit","linkedToGrid"],"properties":["root":planeIndex,"linkedToGrid":["type":"boolean"],
        "pixelsPerUnit":["type":"number","minimum":measurementScaleRange.lowerBound,"maximum":measurementScaleRange.upperBound]]]
    return ["type":"object","additionalProperties":false,"properties":["focalLength":["type":"number","minimum":0,"default":0,
      "description":"Finite focal length in pixels. Zero infers the camera or uses the longer canvas side. The resulting projection must be valid."],"center":pointSchema,
      "gridSize":["type":"number","minimum":gridSizeRange.lowerBound,"maximum":gridSizeRange.upperBound,
                  "default":defaultGridSize,"description":"Grid spacing shared by all planes."],
      "measurements":["type":"array","maxItems":maximumMeasurements,"items":measurement,
        "description":"Measurements use rectified plane coordinates for start and end. An empty array clears the list."],
      "measurementScales":["type":"array","maxItems":32,"items":scale,
        "description":"Each root plane may define a shared scale and grid link for all connected planes."],
      "planes":["type":"array","maxItems":32,"default":[],"items":["type":"object","additionalProperties":false,"properties":[
        "corners":["type":"array","minItems":0,"maxItems":4,"items":pointSchema,"default":[]],"parent":["type":"integer","minimum":0,"maximum":30],"edge":["type":"string","enum":VanishingPlane.Edge.allCases.map(\.rawValue),"default":"top"],"angle":["type":"number","minimum":0,"maximum":180,"default":90],"depth":["type":"number","exclusiveMinimum":0,"default":1],"rotationSign":orientation,"calibration":calibration],"description":"Four convex corners in document pixels, or an earlier parent index with empty corners. Related planes recompute when their parent changes."]]]]
  }
  static var measurementCalibrationSchema: [String:Any] {
    ["type":"object","additionalProperties":false,"required":["index","length"],"properties":[
      "index":["type":"integer","minimum":0,"maximum":maximumMeasurements-1],
      "length":["type":"number","exclusiveMinimum":0]]]
  }
  static var operationSchema:[String:Any] {
    let number:(Double,Double,Double)->[String:Any] = { ["type":"number","minimum":$0,"maximum":$1,"default":$2] }
    let color:[String:Any]=["type":"object","additionalProperties":false,"required":["r","g","b","a"],"properties":Dictionary(uniqueKeysWithValues:["r","g","b","a"].map{($0,number(0,1,$0 == "a" ? 1:0))})]
    let shared:[String:Any]=["plane":["type":"integer","minimum":0,"maximum":31,"default":0],"opacity":number(0,100,100),"clip":["type":"boolean","default":true],
      "heal":["type":"string","enum":VanishingOperation.Heal.allCases.map(\.rawValue),"default":"off"]]
    let rect: [String:Any] = ["type":"object","additionalProperties":false,"required":["plane","lower","upper"],
      "properties":["plane":["type":"integer","minimum":0,"maximum":31],"lower":pointSchema,"upper":pointSchema,
        "wrap":["type":"boolean","default":false]]]
    let variants=VanishingOperation.Kind.allCases.map { kind -> [String:Any] in
      var properties=shared;properties["kind"]=["const":kind.rawValue];var required=["kind"]
      switch kind {
      case .paste:
        properties["sourceLayerID"]=["type":"string","format":"uuid"];properties["at"]=pointSchema;properties["width"]=number(0.001,20,0.5);properties["angle"]=number(-360,360,0);required.append("sourceLayerID")
      case .marquee:
        properties.removeValue(forKey:"plane")
        let range = VanishingMarqueeTransfer.featherRange
        properties["marquee"] = ["type":"object","additionalProperties":false,"required":["source","destination"],
          "properties":["source":rect,"destination":rect,"feather":number(range.lowerBound,range.upperBound,1)]]
        properties["angle"] = number(-360,360,0)
        required.append("marquee")
      case .brush,.clone:
        properties["points"]=["type":"array","minItems":1,"maxItems":4096,"items":pointSchema];properties["diameter"]=number(1,2000,40);properties["hardness"]=number(0,100,50);required.append("points")
        properties["wrap"]=["type":"boolean","default":false]
        properties["strokeSelection"] = rect
        if kind == .clone {
          properties["sourcePoint"]=pointSchema
          properties["sourcePlane"]=["type":"integer","minimum":0,"maximum":31,
            "description":"Donor plane for a wrapped Stamp source that extends beyond the visible plane."]
          required.append("sourcePoint")
          return ["type":"object","additionalProperties":false,"required":required,"properties":properties,
            "if":["required":["sourcePlane"]],"then":["required":["wrap"],"properties":["wrap":["const":true]]]]
        }
        properties["color"]=color
      }
      return ["type":"object","additionalProperties":false,"required":required,"properties":properties]
    }
    return ["type":"array","maxItems":256,"items":["oneOf":variants],"default":[]]
  }
  static var apiCapabilities:[String:Any] {
    ["command":"filter.vanishingPoint","settingsSchema":apiSchema,"operationsSchema":operationSchema,"measurementCalibrationSchema":measurementCalibrationSchema,"nativeArchiveVersion":32,
     "narrowStrokeCoverage":"Brush and clone footprints that project to about a pixel thick or less use area coverage and honor plane clipping. Coverage work shares the Vanishing Point rendering budget.",
     "coordinates":"Corners and stroke/source points are document pixels. Paste at is plane(u,v), width is a fraction of metric plane width, rotation clockwise about paste origin. Zero focal length first uses measured orthogonal axes across a usable linked hinge, then infers from the first plane or uses the longer canvas side.",
     "state":"Document and workspace state include resolved camera, plane corners and grid intervals, projected measurement endpoints, calibrated lengths, and angles in degrees.",
     "renderMeasurements":"Set renderMeasurements:true to write raster annotations with calibrated distances and angles. The existing newLayer option controls destination. Editable lines remain with the document and each apply takes one undo step.",
     "measurement":"Desktop Measure and API settings keep editable lines in a plane, including visible points outside the plane. The command can calibrate a selected line to a known length. Connected planes share the root's calibration and optional grid link.",
     "operations":"Create/save/edit planes with no operations; brush, clone and perspective paste with sourceLayerID (raw raster layer pixels, resolved before mutation). Sequential operations sample the visible composite plus earlier draft operations; each clone stroke takes an immutable source snapshot.",
     "marquee":"Lower and upper are rectified fractions of each rectangle's anchor plane. Set wrap:true individually on source and destination to continue that rectangle across linked surfaces. The destination angle rotates around its center in rectified space. Feather uses the projected selection boundary without feathering internal hinges. Each patch samples the visible composite and preceding operations using bicubic interpolation.",
     "strokeWrapping":"Set wrap:true on Brush or Stamp to continue through linked faces. Clip bounds the destination independently. Wrapped Stamp can use sourcePlane to identify an extrapolated donor and samples the visible image and earlier operations from an immutable snapshot. Omitting wrap preserves single-plane API edits.",
     "strokeSelection":"Supply a strokeSelection rectangle to constrain Brush or Stamp output. Its lower and upper coordinates are rectified fractions of its anchor plane. The rectangle’s wrap flag follows linked faces independently of stroke wrapping. Stamp can sample outside the selection.",
     "heal":"Brush, clone and paste accept off, luminance or on. Luminance adjusts lighting. On adjusts lighting and color. The gradient-domain solve includes a one-pixel boundary within the 4-megapixel local repair budget.",
     "output":"The current raster layer can expand to cover the repair while keeping existing samples and masks in place. Use newLayer:true for a separate layer. Selection and transparency/image locks are honored. Smart Objects must be rasterized for the target. One cancellable undo transaction for the entire program.",
     "limits":"32 planes,256 operations,16,384 supplied points,4,096 points per stroke,128MiB embedded paste sources with up to 8,388,608 pixels, up to \(Surface.maxDimension) pixels per canvas side, 134,217,728 raster visits per program. Large canvases use a bounded overview. Existing API sharing limits also apply.",
     "fileInterchange":"PSD and PSB open supported Photoshop perspective planes and editable measurements. Unchanged perspective data retains its original resource. New planes and measurements are written as Photoshop resource 4000.",
     "sceneExport":["command":"vanishingPoint.export","formats":VanishingSceneExport.Format.allCases.map(\.rawValue),
       "mediaType":"application/zip","maximumBytes":VanishingSceneExport.maximumBytes,
       "files":"3DS includes its VPE companion. Both options include a rectified PNG for every plane.",
       "camera":"Connected planes share geometry along their hinge. Independent planes share the reconstructed camera."],
     "unsupported":"DXF export and exact Adobe pixels, stroke coverage and scene dimensions remain open. Recorded Actions currently report Vanishing Point as unsupported.",
     "adobe":"No dedicated pinned v2 Vanishing Point operation. No invented route or unqualified actionJSON support."]
  }
}
extension AutomationCommand {
  func vanishingOptions(in document:CraftDocument) throws -> (UUID,VanishingProgram) {
    func fail(_ message:String)->AutomationFailure { .init(status:400,message:message) }
    guard let id=UUID(uuidString:try string("layerID")) else { throw fail("Invalid layerID.") }
    var p=VanishingProgram();p.settings=document.vanishingPoint ?? .init()
    if let value=parameters["newLayer"] { guard case .bool(let b)=value else { throw fail("newLayer must be boolean.") };p.newLayer=b }
    if let value = parameters["renderMeasurements"] {
      guard case .bool(let enabled) = value else { throw fail("renderMeasurements must be boolean.") }
      if enabled { p.renderMeasurements = true }
    }
    if let value=parameters["settings"] {
      guard case .object(let fields)=value,Set(fields.keys).isSubset(of:["planes","focalLength","center","gridSize","measurements","measurementScales"]) else { throw fail("Invalid plane settings.") }
      let established = p.settings
      let geometrySupplied = fields["planes"] != nil || fields["focalLength"] != nil || fields["center"] != nil
      var raw = geometrySupplied ? ["planes":[],"focalLength":0] : established.apiValue as? [String:Any] ?? [:]
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
      if let value = raw["measurements"] {
        guard let lines = value as? [[String:Any]],lines.count <= VanishingSettings.maximumMeasurements,
          lines.allSatisfy({ Set($0.keys) == ["plane","start","end"] }) else { throw fail("Invalid measurements.") }
      }
      if let value = raw["measurementScales"] {
        guard let scales = value as? [[String:Any]],scales.count <= 32,
          scales.allSatisfy({ Set($0.keys) == ["root","pixelsPerUnit","linkedToGrid"] }) else {
          throw fail("Invalid measurement scales.")
        }
      }
      func pointsAreStrict(_ value:Any)->Bool { if let d=value as? [String:Any] { for (k,v) in d { if ["center","start","end"].contains(k) { guard let q=v as? [String:Any],Set(q.keys)==["x","y"] else { return false } };if k == "corners" || k == "parentCorners" { guard let q=v as? [[String:Any]],q.allSatisfy({Set($0.keys)==["x","y"]}) else { return false } };if !pointsAreStrict(v) { return false } } };if let a=value as? [Any] { return a.allSatisfy(pointsAreStrict) };return true }
      guard pointsAreStrict(raw) else { throw fail("Invalid plane coordinates.") }
      do {
        p.settings = try JSONDecoder().decode(VanishingSettings.self,from:JSONSerialization.data(withJSONObject:raw))
        if p.settings.planes == established.planes {
          if fields["measurements"] == nil { p.settings.measurements = established.measurements }
          if fields["measurementScales"] == nil { p.settings.measurementScales = established.measurementScales }
        }
        if p.settings.measurements?.isEmpty == true { p.settings.measurements = nil }
        if p.settings.measurementScales?.isEmpty == true { p.settings.measurementScales = nil }
        try p.settings.validate()
        if p.settings.gridSize == VanishingSettings.defaultGridSize { p.settings.gridSize = nil }
      } catch { throw fail(error.localizedDescription) }
    }
    if let calibration = parameters["measurementCalibration"] {
      guard case .object(let fields) = calibration, Set(fields.keys) == ["index","length"],
        case .number(let ordinal) = fields["index"],
        let index = Int(exactly:ordinal),
        case .number(let length) = fields["length"] else { throw fail("Invalid measurementCalibration.") }
      do {
        let scene = try VanishingScene(p.settings,width:document.width,height:document.height)
        let scale = try scene.measurementScale(calibrating:index,to:length,settings:p.settings)
        p.settings.setMeasurementScale(scale)
      } catch { throw fail(error.localizedDescription) }
    }
    if let value=parameters["operations"] {
      guard case .array(let items)=value,items.count<=256 else { throw fail("Invalid operations.") }
      func validRectangle(_ value: Any?) -> Bool {
        guard let rect = value as? [String:Any],Set(rect.keys).isSubset(of:["plane","lower","upper","wrap"]),
          rect["plane"] != nil,!(rect["wrap"] is NSNull),
          let lower = rect["lower"] as? [String:Any],Set(lower.keys) == ["x","y"],
          let upper = rect["upper"] as? [String:Any],Set(upper.keys) == ["x","y"] else { return false }
        return true
      }
      p.operations=try items.map { item in
        guard case .object(let fields)=item,case .string(let name)=fields["kind"],let kind=VanishingOperation.Kind(rawValue:name) else { throw fail("Invalid operation kind.") }
        let allowed: Set<String>
        switch kind {
        case .paste: allowed = ["kind","plane","at","width","angle","opacity","clip","sourceLayerID"]
        case .clone: allowed = ["kind","plane","points","sourcePoint","sourcePlane","diameter","hardness","opacity","clip","wrap","strokeSelection"]
        case .brush: allowed = ["kind","plane","points","diameter","hardness","opacity","color","clip","wrap","strokeSelection"]
        case .marquee: allowed = ["kind","marquee","angle","opacity","clip"]
        }
        guard Set(fields.keys).isSubset(of:allowed.union(["heal"])) else { throw fail("Unknown or irrelevant operation field.") }
        if let wrap = fields["wrap"] {
          guard case .bool = wrap else { throw fail("Stroke wrap must be a boolean.") }
        }
        if let plane = fields["sourcePlane"] {
          guard case .number(let value) = plane,Int(exactly:value) != nil else { throw fail("Invalid linked Stamp source plane.") }
        }
        if let heal = fields["heal"] {
          guard case .string(let mode) = heal, VanishingOperation.Heal(rawValue: mode) != nil else {
            throw fail("Heal must be off, luminance or on.")
          }
        }
        var raw=try JSONSerialization.jsonObject(with:JSONEncoder().encode(VanishingOperation(kind))) as! [String:Any]
        for (k,v) in fields where k != "sourceLayerID" { raw[k]=v.jsonValue }
        for key in ["at","sourcePoint"] { if let value=raw[key] { guard let point=value as? [String:Any],Set(point.keys)==["x","y"] else { throw fail("Invalid operation point.") } } }
        if let values=raw["points"] { guard let points=values as? [[String:Any]],points.allSatisfy({Set($0.keys)==["x","y"]}) else { throw fail("Invalid stroke points.") } }
        if kind == .marquee {
          guard var patch = raw["marquee"] as? [String:Any],
            Set(patch.keys).isSubset(of:["source","destination","feather"]) else { throw fail("Invalid marquee patch.") }
          guard validRectangle(patch["source"]),validRectangle(patch["destination"]) else {
            throw fail("Invalid marquee rectangle.")
          }
          if patch["feather"] == nil { patch["feather"] = 1 }
          raw["marquee"] = patch
          raw["plane"] = (patch["destination"] as? [String:Any])?["plane"]
        }
        if let selection = raw["strokeSelection"],!validRectangle(selection) { throw fail("Invalid stroke selection rectangle.") }
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
  var apiState:[String:Any] {
    let bounds = activeMarquee.map { rect -> [String:Any] in
      ["plane":rect.plane,"lower":["x":rect.lower.x,"y":rect.lower.y],"upper":["x":rect.upper.x,"y":rect.upper.y],
        "wrap":rect.wrap == true]
    }
    return ["settings":program.settings.apiValue,"scene":scene?.apiValue(settings:program.settings) as Any? ?? NSNull(),"operationCount":program.operations.count,"newLayer":program.newLayer,"tool":tool.rawValue,"selectedPlane":selected,"pendingCorners":pending.count,"preview":preview,"rendering":rendering,"zoom":zoom,"showGrid":showGrid,"gridSize":gridSize,"showMeasurements":showMeasurements,"canExportScene":canExportScene,"exportingScene":exportingScene,"renderMeasurements":renderMeasurements,"selectedMeasurement":selectedMeasurement as Any? ?? NSNull(),
      "pendingMeasurement":pendingMeasurement != nil,"canUndo":canUndo,"canRedo":canRedo,"heal":heal.rawValue,"selectedPasteHeal":selectedPasteHeal?.rawValue as Any? ?? NSNull(),"error":error as Any? ?? NSNull(),
      "marquee":bounds as Any? ?? NSNull(),"marqueeMoveMode":marqueeMoveMode.rawValue,"floatingMarquee":floatingMarqueeOperation != nil,
      "allowMultiSurfaceOperations":allowMultiSurfaceOperations,"allowMultiSurfaceMarquee":allowMultiSurfaceOperations,
      "clipOperationsToSurfaceEdges":clip]
  }
}


extension AutomationService {
  func exportVanishingScene(_ command: AutomationCommand, document: CraftNSDocument,
    shareID: UUID) async throws -> AutomationResponse
  {
    guard documentTransfersEnabled else {
      throw AutomationFailure(status:403,message:"Enable document transfers before exporting a Vanishing Point scene.")
    }
    guard !documentTransferBusy else {
      throw AutomationFailure(status:429,message:"A document transfer is already in progress.")
    }
    try preflight(document)
    guard let format = try VanishingSceneExport.Format(rawValue:command.string("format")) else {
      throw AutomationFailure(status:400,message:"Choose 3ds or vpe for Vanishing Point export.")
    }
    let store = document.store, source = store.document
    let expectedToken = token, expectedTransfer = documentTransferGeneration, expectedRevision = command.revision
    documentTransferBusy = true
    defer { documentTransferBusy = false }
    let worker = Task.detached(priority:.userInitiated) {
      let output = try VanishingSceneExport.render(source,format:format)
      return (name:output.name,bytes:try output.zip())
    }
    let output = try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
    prune()
    guard !Task.isCancelled, isRunning, documentTransfersEnabled, token == expectedToken,
      documentTransferGeneration == expectedTransfer, document.closeWorkflowID == nil,
      revision(store) == expectedRevision, store.document == source,
      shares.contains(where:{$0.id == shareID && $0.document === document}) else {
      throw AutomationFailure(status:409,message:"Vanishing Point export was revoked or its source changed.")
    }
    return .init(status:200,contentType:"application/zip",body:output.bytes,
      headers:["Content-Disposition":"attachment; filename=\"\(output.name)-scene.zip\""])
  }
}
