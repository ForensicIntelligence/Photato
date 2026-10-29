import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum MovieFramesAPI {
  static let header = "x-photato-movie-frames"
  static let cancelPath = "/v1/documents/import/movie-frames/cancel"
  static var schema: [String:Any] {
    ["type":"object","additionalProperties":false,"properties":[
      "selectedRange":["type":"boolean"],"start":["type":"number","minimum":0,"maximum":86400],
      "end":["type":"number","exclusiveMinimum":0,"maximum":86400],
      "every":["type":"integer","minimum":1,"maximum":10000],"makeAnimation":["type":"boolean"]]]
  }
  static func options(_ value: String?) throws -> MovieFrameImportOptions? {
    guard let value else{return nil}
    do {
      guard value.utf8.count <= 4096 else {throw CraftError.invalid("Movie frame options exceed4KiB.")}
      let raw = try JSONDecoder().decode(AutomationValue.self,from:Data(value.utf8))
      let merged = try BrushAPI.merge(raw,schema:schema,base:BrushAPI.json(MovieFrameImportOptions()),path:"movieFrames")
      let result = try JSONDecoder().decode(MovieFrameImportOptions.self,from:JSONSerialization.data(withJSONObject:merged));try result.validate();return result
    } catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
  static var capabilities: [String:Any] {
    ["method":"POST","path":"/v1/documents/import","header":"X-Photato-Movie-Frames","schema":schema,
     "result":"HTTP201 shared new unsaved document. Each selected frame is an editable raster layer; makeAnimation adds precise per-frame visibility/delays. Other documents and the uploaded source are unchanged.",
     "selection":"Defaults: whole movie, every1, makeAnimationtrue. selectedRange uses presentation timestamps in[start,end) seconds; every is counted from the first eligible frame. Kept frames last until the next kept timestamp or range end. Filtering occurs before output allocation; a subset of a longer movie may fit within output limits.",
     "cancel":["method":"POST","path":cancelPath,"body":["operationID":"UUID from movieFramesImportState.uploadOperationID"]],
     "limits":"Transfer permission; supported MOV/MP4 up to64MiB; API4MP/64layers/128MiB. Native512 layers or256 with animation and1GiB. Native SDR sRGB16 pixels; source audio is not part of a frame animation. No arbitrary filesystem paths.",
     "colorPolicy":"The decoder creates new sRGB image layers. Omit X-Photato-Color-Decision for this workflow; ordinary movie opening retains its separate color-policy behavior.",
     "open":"Exact Photoshop range/default/depth/codec behavior, HDR, larger media, live UI and platform parity remain unqualified.",
     "adobe":"No dedicated movie-frame import endpoint in the pinned public Adobe v2 contract; no new Adobe route or descriptor is invented."]
  }
}
extension AutomationService {
  func cancelMovieFramesImport(_ request: AutomationRequest) throws -> AutomationResponse? {
    guard request.method == "POST",request.path == MovieFramesAPI.cancelPath else{return nil}
    guard documentTransfersEnabled else {throw AutomationFailure(status:403,message:"Enable document transfers before cancelling a movie-frame upload.")}
    guard let values = try? JSONDecoder().decode([String:AutomationValue].self,from:request.body),Set(values.keys) == ["operationID"],case .string(let raw) = values["operationID"],let id = UUID(uuidString:raw) else {throw AutomationFailure(status:400,message:"Supply the current movie-frame import operationID.")}
    guard movieFramesImportOperationID == id,let worker = movieFramesImportTask else {throw AutomationFailure(status:409,message:"That movie-frame import is no longer active.")}
    worker.cancel();return .json(["operationID":id.uuidString,"cancellationRequested":true])
  }
}
