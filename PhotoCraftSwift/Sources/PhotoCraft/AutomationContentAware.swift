import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension ContentAwareSettings {
  static var apiSchema: [String:Any] {
    ["type":"object","additionalProperties":false,"properties":[
      "sampling":["type":"string","enum":Sampling.allCases.map(\.rawValue),"default":"auto"],
      "colorAdaptation":["type":"string","enum":ColorAdaptation.allCases.map(\.rawValue),"default":"default"],
      "rotation":["type":"string","enum":Rotation.allCases.map(\.rawValue),"default":"none"],
      "scale":["type":"boolean","default":false],"mirror":["type":"boolean","default":false],"sampleAllLayers":["type":"boolean","default":false],
      "margin":["type":"integer","minimum":0,"maximum":100000,"default":64],"seed":["type":"integer","minimum":0,"maximum":UInt32.max,"default":1]]]
  }
  static var strokeSchema: [String:Any] {
    ["type":"array","maxItems":256,"items":["type":"object","additionalProperties":false,"required":["points"],"properties":[
      "target":["type":"string","enum":["sampling","selection"],"default":"sampling"],"kind":["type":"string","enum":["brush","lasso"],"default":"brush"],
      "add":["type":"boolean","default":false],"size":["type":"number","minimum":1,"maximum":5000,"default":30],
      "points":["type":"array","minItems":1,"maxItems":4096,"items":["type":"array","minItems":2,"maxItems":2,"items":["type":"number","minimum":-1000000,"maximum":1000000]]]]]]
  }
  static var apiCapabilities: [String:Any] {
    ["command":"contentAware.fill","settingsSchema":apiSchema,"strokeSchema":strokeSchema,"outputs":ContentAwareOutput.allCases.map(\.rawValue),
     "maximumCanvasPixels":ContentAwareInput.maximumCanvasPixels,"maximumSamplingPixelsIncludingAdaptations":ContentAwareSynthesis.maximumPixels,"maximumTotalStrokePoints":16384,
     "sampling":"auto uses a neighborhood of the selection; rectangular uses margin; custom uses a saved alpha channel and/or add sampling strokes. Selection strokes run first, then sampling strokes. Transparent pixels are excluded from source patches.",
     "history":"One cancellable native prepared edit. Current/new/duplicate output retains working profile and RGB8/16/32. Stale, busy or revoked requests do not publish results.",
     "limits":"Ordinary raster layer and RGB composite context. No Adobe proprietary result equivalence; Content-Aware Scale, crop fill and cross-document sampling remain separate. No dedicated published Photoshop v2 endpoint; content-aware actionJSON descriptors remain unsupported."]
  }
}
struct ContentAwareAPIOptions: Sendable {
  let id: UUID
  let settings: ContentAwareSettings
  let output: ContentAwareOutput
  let strokes: [ContentAwareStroke]
  let samplingID: UUID?
  func edit(_ document: CraftDocument) throws -> ContentAwareEdit {
    let input = try ContentAwareInput.prepare(document,layerID:id)
    let sampling = try samplingID.map { try document.channel(.alpha($0)).selection() }
    return try input.edit(settings:settings,output:output,strokes:strokes,sampling:sampling)
  }
}
extension AutomationCommand {
  func contentAwareOptions() throws -> ContentAwareAPIOptions {
    do {
      guard let id = UUID(uuidString:try string("layerID")) else { throw CraftError.invalid("Invalid layerID.") }
      let settings = try ContentAwareSettings.decodeJSON(JSONSerialization.data(withJSONObject:parameters["settings"]?.jsonValue ?? [:]))
      let output: ContentAwareOutput
      if parameters["output"] == nil { output = .new } else { guard let o = ContentAwareOutput(rawValue:try string("output")) else { throw CraftError.invalid("Unknown output.") }; output = o }
      var samplingID: UUID?
      if parameters["samplingChannelID"] != nil { guard let id = UUID(uuidString:try string("samplingChannelID")) else { throw CraftError.invalid("Invalid sampling channel ID.") }; samplingID = id }
      var strokes: [ContentAwareStroke] = []
      if let raw = parameters["strokes"] {
        guard let values = raw.jsonValue as? [[String:Any]], values.count <= 256 else { throw CraftError.invalid("Invalid strokes.") }
        for value in values {
          guard Set(value.keys).isSubset(of:["target","kind","add","size","points"]),value["points"] != nil else { throw CraftError.invalid("Invalid stroke parameters.") }
          var fields = try JSONSerialization.jsonObject(with:JSONEncoder().encode(ContentAwareStroke())) as! [String:Any]
          for (k,v) in value { fields[k] = v }
          let stroke = try JSONDecoder().decode(ContentAwareStroke.self,from:JSONSerialization.data(withJSONObject:fields)); try stroke.validate(); strokes.append(stroke)
        }
      }
      guard strokes.reduce(0,{ $0+$1.points.count }) <= 16384 else { throw CraftError.invalid("Too many stroke points.") }
      return ContentAwareAPIOptions(id:id,settings:settings,output:output,strokes:strokes,samplingID:samplingID)
    } catch { throw AutomationFailure(status:400,message:error.localizedDescription) }
  }
}
