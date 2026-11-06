import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum RegionRetouchAPI {
  static let commands = ["retouch.patch","retouch.move","retouch.redEye"]
  static var capabilities: [String:Any] {
    ["commands":commands,"maximumCanvasPixels":RegionRetouchPreparation.maximumCanvasPixels,
     "maximumRegionPixels":RegionRetouchPreparation.maximumRegionPixels,
     "target":"Unlocked ordinary raster layer; selection coverage, transparency protection and layer/mask geometry are preserved. RGB image target only.",
     "patch":"Selected region and integer dx/dy; source repairs the selection from the offset region, destination repairs the offset region. normal or contentAware with diffusion/structure/color and sampling controls.",
     "patternPatch":["parameter":"retouch.patch patternID instead of dx/dy; only layerID/patternID/diffusion/transparent are accepted in this branch.",
       "patterns":"regionRetouch.patterns lists saved document patterns before native-library patterns; immutable resource captured at request acceptance.",
       "maximumCanvasDimension":Surface.maxDimension,"maximumCanvasPixels":Surface.maxPixels,
       "maximumSolvePixels":PatternPatch.maximumRegionPixels,"maximumTransformedOutputPixels":PatternPatch.maximumRegionPixels,
       "sampling":"100% wrapping native pattern sampler at document origin; full-resolution selected-region healing, same Normal diffusion and transparent coverage. Exact Photoshop phase/alpha/solver/defaults unqualified.",
       "history":"Native Use Pattern and API share PatternPatch.prepare; one prepared Undo, selection/layer metadata and outside pixels retained. Source/busy/cancel/revocation guards apply."],
     "move":"Move fills the old selection; Extend keeps it. dx/dy are center offsets in document pixels; scale percentages and clockwise angle transform around the selection center. Output selection follows the moved region.",
     "redEye":"x/y/width/height bound the pupil search. Pupil Size controls its extent; Darken controls the correction. Selection coverage clips correction; neutral highlights and alpha are preserved.",
     "history":"Shared native preview and prepared edit; one undo/redo entry. Busy/stale/revoked requests never commit.",
     "limits":"Native independent algorithms; exact Photoshop pixels, full-region/canvas Patch/Move/RedEye capacity and mask/channel targets remain open. Pattern Patch bounded solve/output has separate capacity metadata. No dedicated published Adobe v2 retouch endpoint; these actionJSON descriptors remain unsupported."]
  }
  static func schema(_ key: String,command: String) -> [String:Any]? {
    switch key {
    case "patternID": ["type":"string","minLength":1,"maxLength":255]
    case "dx","dy": ["type":command == "retouch.patch" ? "integer":"number","minimum":-1_000_000,"maximum":1_000_000]
    case "mode": ["type":"string","enum":command == "retouch.patch" ? ["source","destination"]:["move","extend"],"default":command == "retouch.patch" ? "source":"move"]
    case "type": ["type":"string","enum":["normal","contentAware"],"default":"normal"]
    case "scaleX","scaleY": ["type":"number","minimum":1,"maximum":1000,"default":100]
    case "angle": ["type":"number","minimum":-360,"maximum":360,"default":0]
    case "diffusion","structure": ["type":"integer","minimum":1,"maximum":7,"default":key == "diffusion" ? 5:4]
    case "color": ["type":"integer","minimum":0,"maximum":10,"default":0]
    case "pupilSize": ["type":"number","minimum":1,"maximum":100,"default":50]
    case "darken": ["type":"number","minimum":0,"maximum":100,"default":50]
    case "transparent","sampleAllLayers": ["type":"boolean","default":false]
    case "seed": ["type":"integer","minimum":0,"maximum":UInt32.max,"default":1]
    case "x","y": ["type":"integer","minimum":-1_000_000,"maximum":1_000_000]
    case "width","height": ["type":"integer","minimum":1,"maximum":60000]
    default:nil
    }
  }
}
extension AutomationCommand {
  func regionRetouchOptions(patterns: [RasterPattern] = []) throws -> (id:UUID,request:RegionRetouchRequest,pattern:RasterPattern?) {
    guard let id = UUID(uuidString:try string("layerID")),RegionRetouchAPI.commands.contains(name) else { throw AutomationFailure(status:400,message:"Invalid retouching layer or command.") }
    var r = RegionRetouchRequest(kind:name == "retouch.patch" ? .patch:name == "retouch.move" ? .move:.redEye)
    let pattern: RasterPattern?
    if parameters["patternID"] != nil {
      guard r.kind == .patch, Set(parameters.keys).isSubset(of:["layerID","patternID","diffusion","transparent"]) else {
        throw AutomationFailure(status:400,message:"Pattern Patch accepts layerID, patternID, diffusion and transparent; no drag or Content-Aware settings.")
      }
      let key = try string("patternID")
      guard !key.isEmpty, key.utf8.count <= 255 else { throw AutomationFailure(status:400,message:"Invalid pattern ID.") }
      guard let found = patterns.first(where: { $0.id == key }) else { throw AutomationFailure(status:404,message:"Pattern not found in this document or native library.") }
      pattern = found
    } else { pattern = nil }
    if r.kind == .redEye {
      r.region = IntRect(x:try integer("x",range:-1_000_000...1_000_000),y:try integer("y",range:-1_000_000...1_000_000),width:try integer("width",range:1...60000),height:try integer("height",range:1...60000))
    } else if pattern == nil {
      r.dx = try number("dx",range:-1_000_000...1_000_000);r.dy = try number("dy",range:-1_000_000...1_000_000)
    }
    if parameters["mode"] != nil {
      let mode = try string("mode")
      if r.kind == .patch { guard let value = RegionRetouchRequest.PatchMode(rawValue:mode) else { throw AutomationFailure(status:400,message:"Unknown Patch mode.") };r.patchMode = value }
      else { guard let value = RegionRetouchRequest.MoveMode(rawValue:mode) else { throw AutomationFailure(status:400,message:"Unknown Move mode.") };r.moveMode = value }
    }
    if parameters["type"] != nil { guard let type = RegionRetouchRequest.PatchType(rawValue:try string("type")) else { throw AutomationFailure(status:400,message:"Unknown Patch type.") };r.patchType = type }
    let doubles: [(String,WritableKeyPath<RegionRetouchRequest,Double>,ClosedRange<Double>)] = [
      ("scaleX",\.scaleX,1...1000),("scaleY",\.scaleY,1...1000),("angle",\.angle,-360...360),("pupilSize",\.pupilSize,1...100),("darken",\.darken,0...100)]
    for (name,key,range) in doubles {
      if parameters[name] != nil { r[keyPath:key] = try number(name,range:range) }
    }
    let integers: [(String,WritableKeyPath<RegionRetouchRequest,Int>,ClosedRange<Double>)] = [
      ("diffusion",\.diffusion,1...7),("structure",\.structure,1...7),("color",\.color,0...10)]
    for (name,key,range) in integers {
      if parameters[name] != nil { r[keyPath:key] = try integer(name,range:range) }
    }
    let booleans: [(String,WritableKeyPath<RegionRetouchRequest,Bool>)] = [("transparent",\.transparent),("sampleAllLayers",\.sampleAllLayers)]
    for (name,key) in booleans {
      if let raw = parameters[name] { guard case .bool(let value) = raw else { throw AutomationFailure(status:400,message:"Invalid \(name).") };r[keyPath:key] = value }
    }
    if parameters["seed"] != nil { r.seed = UInt32(try integer("seed",range:0...Double(UInt32.max))) }
    do { try r.validate() } catch { throw AutomationFailure(status:400,message:error.localizedDescription) }
    return (id,r,pattern)
  }
}
