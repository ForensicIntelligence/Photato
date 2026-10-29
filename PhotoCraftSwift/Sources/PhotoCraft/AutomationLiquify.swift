import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension LiquifySettings {
  static var apiSchema: [String:Any] {
    let percent: [String:Any] = ["type":"number","minimum":0,"maximum":100]
    let coordinate: [String:Any] = ["type":"number","minimum":-1_000_000,"maximum":1_000_000]
    let geometry = faceGeometrySchema
    let face: [String:Any] = ["type":"object","additionalProperties":false,"required":["geometry"],"properties":["geometry":geometry,"parameters":["type":"object","additionalProperties":false,"properties":Dictionary(uniqueKeysWithValues:LiquifyFaceParameter.allCases.map { ($0.rawValue,["type":"number","minimum":-100,"maximum":100] as [String:Any]) })]]]
    let point: [String:Any] = ["type":"array","minItems":2,"maxItems":3,"prefixItems":[coordinate,coordinate,["type":"number","minimum":0,"maximum":1]],"items":false]
    let stroke: [String:Any] = ["type":"object","additionalProperties":false,"properties":["tool":["type":"string","enum":LiquifyTool.allCases.map(\.rawValue),"default":"forwardWarp"],"size":["type":"number","minimum":1,"maximum":15000,"default":100],"density":percent,"pressure":percent,"rate":percent,"amount":percent,"points":["type":"array","maxItems":32768,"items":point]]]
    return ["type":"object","additionalProperties":false,"properties":["width":["type":"integer","minimum":0,"maximum":65536,"default":0],"height":["type":"integer","minimum":0,"maximum":65536,"default":0],"meshSize":["type":"number","anyOf":[["const":0],["minimum":1,"maximum":64]],"default":0],"strokes":["type":"array","maxItems":2048,"items":stroke],"faces":["type":"array","maxItems":16,"items":face]]]
  }
  static var faceGeometrySchema: [String:Any] {
    let rect: [String:Any] = ["type":"array","minItems":4,"maxItems":4,"items":["type":"number","minimum":0,"maximum":1]]
    return ["type":"object","additionalProperties":false,"required":["bounds","leftEye","rightEye","nose","mouth"],"properties":Dictionary(uniqueKeysWithValues:["bounds","leftEye","rightEye","nose","mouth"].map { ($0,rect) })]
  }
  static var faceResultSchema: [String:Any] {
    ["type":"object","additionalProperties":false,"required":["revision","width","height","faces"],
     "properties":["revision":["type":"string"],"width":["type":"integer","minimum":1,"maximum":65536],
       "height":["type":"integer","minimum":1,"maximum":65536],"faces":["type":"array","maxItems":16,"items":faceGeometrySchema]]]
  }
  static var apiCapabilities: [String:Any] {
    ["schema":apiSchema,"tools":LiquifyTool.allCases.map(\.rawValue),"faceControls":LiquifyFaceParameter.allCases.map(\.rawValue),
     "faceDetectionCommand":"liquify.faces","faceDetectionResultSchema":faceResultSchema,"maximumTotalPoints":32768,"maximumProgramBytes":LiquifyMeshFile.maximumBytes,
     "meshFile":["extension":LiquifyMeshFile.fileExtension,"format":"PhotatoLiquify","version":1,"settings":"Same object as filter.liquify"],
     "coordinates":"Layer pixels, y down. Smart Objects use their placed filter canvas. Saved width/height scale to future target dimensions; zero means current dimensions. Faces use normalized rectangles. Brush defaults: size100,density50,pressure100,rate80. Point pressure defaults1. Globals take no points; lasso amount0 thaws and1 freezes; reconstructAll amount defaults100. Faces are applied after strokes and respect freeze masks.",
     "history":"filter.apply and smartFilter.set use the native undo transaction. liquify.faces returns normalized geometry without editing history.",
     "limits":"8,388,608 pixels;250million mesh-node visits. Independent native face warps; no Photoshop .msh, PSD Smart Filter mesh interchange or Adobe Liquify action descriptor support. Exact Photoshop numerical parity remains unqualified."]
  }
}
extension AutomationService {
  func detectLiquifyFaces(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws -> [String:Any] {
    guard let layerID = UUID(uuidString:try command.string("layerID")) else { throw AutomationFailure(status:400,message:"Invalid layerID.") }
    let filterID: UUID?
    if command.parameters["filterID"] != nil {
      guard let parsed = UUID(uuidString:try command.string("filterID")) else { throw AutomationFailure(status:400,message:"Invalid filterID.") }; filterID = parsed
    } else { filterID = nil }
    guard !previewBusy else { throw AutomationFailure(status:429,message:"An image analysis is already running.") }
    previewBusy = true; defer { previewBusy = false }
    let snapshot = document.store.document, expectedGeneration = generation, expectedToken = token
    let detector = liquifyFaceDetector
    let worker = Task.detached(priority:.userInitiated) {
      let input = try LiquifyInput.prepare(document:snapshot,layerID:layerID,filterID:filterID)
      let faces = try await detector.faces(in:input.pixels)
      return (input.width,input.height,faces)
    }
    let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    prune()
    guard !Task.isCancelled, isRunning, token == expectedToken, generation == expectedGeneration,
      command.revision == revision(document.store), shares.contains(where: { $0.id == shareID }) else {
      throw AutomationFailure(status:409,message:"Document changed or sharing ended during face detection.")
    }
    try preflight(document)
    return ["revision":command.revision,"width":result.0,"height":result.1,"faces":try JSONSerialization.jsonObject(with:JSONEncoder().encode(result.2))]
  }
}
