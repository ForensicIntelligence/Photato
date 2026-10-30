import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum PDFSourceEditAPI {
  static var stateSchema: [String:Any] {
    let fields: [String:Any] = ["sessionID":["type":"string","format":"uuid"],"sourceID":["type":"string","format":"uuid"],
      "layerID":["type":"string","format":"uuid"],"sourceRevision":["type":"string"],"fileName":["type":"string"],
      "stage":["type":"string","enum":["opening","watching","reading","waiting","updating","conflict","error","stopped"]],
      "message":["type":"string"],"workingCopyRetained":["const":true]]
    return ["type":"array","items":BrushAPI.object(fields,required:Array(fields.keys).sorted())]
  }
  static var capabilities: [String:Any] {
    ["method":"POST","path":"/v1/documents/{id}/smart-objects/{layerID}/source","contentType":"application/pdf",
     "requiredHeaders":["X-Photato-Revision","X-Photato-Source-Revision"],
     "bodySchema":["type":"string","contentMediaType":"application/pdf","minLength":1,"maxLength":SmartObject.maximumSourceBytes],
     "stateSchema":stateSchema,"result":"HTTP200 document state; all shared source instances update in one Undo transaction. An identical source is a no-op.",
     "selection":"Retains page/image index, crop mode, resolution, antialias setting, source filename/identity and instance transforms. Missing pages/images reject atomically.",
     "sourceDownload":"GET the same path to retrieve original source bytes before editing.",
     "cancel":["method":"POST","path":"/v1/documents/{id}/smart-objects/{layerID}/source/cancel","schema":BrushAPI.object(["operationID":["type":"string","format":"uuid"]],required:["operationID"])],
     "stopEditing":["method":"POST","path":"/v1/documents/{id}/smart-objects/{layerID}/source/stop-editing","schema":BrushAPI.object(["sessionID":["type":"string","format":"uuid"]],required:["sessionID"])],
     "state":"Document pdfSourceEditing lists native editor sessions without local paths. capabilities.pdfSourceUpdateOperations lists active uploads by shared document UUID.",
     "desktop":"Edit Contents opens a durable PDF working copy in the associated macOS app. Atomic/in-place saves update shared instances after current edits finish. Source conflicts require explicit Apply Saved PDF. Closing/stopping retains the working copy.",
     "limits":"Explicit sharing and document transfers;64MiB upload; source/image/render budgets; stale source/document, locked instances, cancellation and transfer revocation cannot commit.",
     "adobe":"Existing v2 edit Smart Object file resources use the same PDF embedding/replacement engine with published autoResize/instance semantics. Editor sessions are Photato-specific; no new Adobe route.",
     "remaining":"Live editor handoff acceptance, restart recovery UI, PDF annotation rendering/full vector editing/interchange, linked sources, exact Photoshop and platform fidelity."]
  }
}

extension AutomationService {
  func handlePDFSourceUpdate(_ request: AutomationRequest) async throws -> AutomationResponse? {
    let parts = request.path.split(separator:"/")
    guard request.method == "POST",[6,7].contains(parts.count),parts[0] == "v1",parts[1] == "documents",
      parts[3] == "smart-objects",parts[5] == "source",request.path == "/"+parts.joined(separator:"/"),
      parts.count == 6 || ["cancel","stop-editing"].contains(parts[6]) else {return nil}
    guard let id = UUID(uuidString:String(parts[2])),let layerID = UUID(uuidString:String(parts[4])),
      let share = shares.first(where:{$0.id == id}),let document = share.document else {
      throw AutomationFailure(status:404,message:"Shared document or layer not found.")
    }
    let store = document.store
    if parts.count == 7 {
      let key = parts[6] == "cancel" ? "operationID":"sessionID"
      guard request.body.count <= 4096,let fields = try? JSONSerialization.jsonObject(with:request.body) as? [String:Any],
        Set(fields.keys) == [key],let value = fields[key] as? String,let token = UUID(uuidString:value) else {
        throw AutomationFailure(status:400,message:"Provide one \(key).")
      }
      if key == "operationID" {
        guard let op = pdfSourceUpdateOperations[id],op.id == token,op.layerID == layerID else {throw AutomationFailure(status:409,message:"PDF update operation changed.")}
        store.geometryTask?.cancel();return .json([key:token.uuidString,"cancellationRequested":true])
      }
      guard let editor = store.pdfSourceEditors.values.first(where:{$0.id == token && $0.layerID == layerID}) else {
        throw AutomationFailure(status:409,message:"PDF editing session changed.")
      }
      store.stopPDFSourceEditing(editor.sourceID);return .json(state(share,document:document))
    }
    guard documentTransfersEnabled else {throw AutomationFailure(status:403,message:"Enable document transfers before updating PDF sources.")}
    try preflight(document)
    guard let expected = request.headers["x-photato-revision"],expected == revision(store),
      let expectedSource = request.headers["x-photato-source-revision"],
      let source = store.document.layers.first(where:{$0.id == layerID})?.smartObject,source.pdfSource != nil,
      source.revision == expectedSource else {throw AutomationFailure(status:409,message:"Stale or missing PDF source/document revision.")}
    guard request.headers["content-type"]?.split(separator:";").first?.lowercased() == "application/pdf" else {
      throw AutomationFailure(status:415,message:"Send application/pdf source bytes.")
    }
    guard !request.body.isEmpty,request.body.count <= SmartObject.maximumSourceBytes else {throw AutomationFailure(status:413,message:"PDF source must contain1 byte through64MiB.")}
    if request.body == source.data {return .json(state(share,document:document))}
    let bytes = request.body,operation = UUID(),generation = documentTransferGeneration,prepare = pdfSourceUpdatePreparation
    pdfSourceUpdateOperations[id] = (operation,layerID)
    defer {if pdfSourceUpdateOperations[id]?.id == operation {pdfSourceUpdateOperations.removeValue(forKey:id)}}
    try await executePreparedOperation(document:document,shareID:id,revision:expected,validateCommit:{[weak self] in
      guard let self,self.documentTransfersEnabled,self.documentTransferGeneration == generation else {throw AutomationFailure(status:409,message:"Source transfer permission changed.")}
    }) {original in try await prepare(bytes,original,layerID,expectedSource)}
    return .json(state(share,document:document))
  }
}
