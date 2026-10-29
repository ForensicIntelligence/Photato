import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum PDFImportAPI {
  static let inspectPath = "/v1/pdf/inspect"
  static let importPath = "/v1/documents/import/pdf"
  static let cancelPath = "/v1/documents/import/pdf/cancel"
  static let optionsHeader = "x-photato-pdf-options"
  static var schema: [String:Any] {
    ["type":"object","additionalProperties":false,"properties":[
      "pages":["type":"array","minItems":1,"maxItems":32,"uniqueItems":true,"items":["type":"integer","minimum":1,"maximum":4096]],
      "crop":["type":"string","enum":PDFImportSettings.Crop.allCases.map(\.rawValue)],
      "resolution":["type":"number","minimum":1,"maximum":10000],
      "width":["type":["integer","null"],"minimum":1,"maximum":Surface.maxDimension],
      "height":["type":["integer","null"],"minimum":1,"maximum":Surface.maxDimension],
      "constrainProportions":["type":"boolean"],"antialias":["type":"boolean"],
      "mode":["type":"string","enum":DocumentColorMode.componentModes.map(\.rawValue)],
      "depth":["type":"string","enum":PixelDepth.allCases.map(\.rawValue)]]]
  }
  static func options(_ value: String?) throws -> PDFImportSettings {
    do {
      guard let value else{return .init()}
      guard value.utf8.count <= 4096 else {throw CraftError.invalid("PDF import options exceed4KiB.")}
      let raw = try JSONDecoder().decode(AutomationValue.self,from:Data(value.utf8))
      let merged = try BrushAPI.merge(raw,schema:schema,base:BrushAPI.json(PDFImportSettings()),path:"pdfImport")
      let settings = try JSONDecoder().decode(PDFImportSettings.self,from:JSONSerialization.data(withJSONObject:merged))
      try settings.validate();return settings
    } catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
  static func password(_ value: String?) throws -> String? {
    guard let value else{return nil}
    guard value.utf8.count <= 2048,let bytes = Data(base64Encoded:value),bytes.count <= 1024,
      let password = String(data:bytes,encoding:.utf8),!password.contains("\0") else {
      throw AutomationFailure(status:400,message:"X-Photato-PDF-Password must be base64-encoded UTF-8, at most1024 decoded bytes.")
    }
    return password
  }
  static func thumbnailPages(_ value: String?) throws -> [Int] {
    guard let value else{return []}
    guard value.utf8.count <= 1024,let pages = try? JSONDecoder().decode([Int].self,from:Data(value.utf8)),
      pages.count <= 32,Set(pages).count == pages.count,pages.allSatisfy({(1...4096).contains($0)}) else {
      throw AutomationFailure(status:400,message:"X-Photato-PDF-Thumbnails must contain up to32 distinct page numbers as a JSON array.")
    }
    return pages
  }
  enum Prepared: Sendable {
    case inspection(PDFImportInfo,[Int:Data])
    case imageInspection([PDFImageInfo],[Int:Data])
    case documents([CraftDocument])
  }
  static var capabilities: [String:Any] {
    ["images":PDFImageImportAPI.capabilities,"inspect":["method":"POST","path":inspectPath,"result":"Page numbers, rotations and media/crop/bleed/trim/art box dimensions in oriented PDF points; encrypted flag; optional PNG thumbnails keyed by page number.",
                "thumbnailHeader":"X-Photato-PDF-Thumbnails: JSON array of up to32 distinct 1-based page numbers; each PNG fits160×160. Omit for metadata only."],
     "import":["method":"POST","path":importPath,"successStatus":201,"optionsHeader":"X-Photato-PDF-Options","schema":schema,
               "result":"{documents:[shared document state,...],count:integer}. All selected pages publish atomically as new unsaved editable documents; source PDF and existing documents remain unchanged."],
     "body":["contentType":"application/pdf","maxBytes":PDFImport.maximumSourceBytes],
     "nameHeader":"X-Photato-Name: optional1–240 printable ASCII characters; default Imported PDF. Multiple output names append source page numbers.",
     "passwordHeader":"X-Photato-PDF-Password: optional base64 UTF-8 password, at most1024 decoded bytes. Never included in document state, capabilities or persisted source association.",
     "cancel":["method":"POST","path":cancelPath,"body":["operationID":"Current UUID from pdfImportState.uploadOperationID"],"result":["operationID":"UUID","cancellationRequested":true]],
     "defaults":"First page; bounding crop;300ppi; constrained proportions; antialias;RGB8. Explicit pixel dimensions resize selected pages; missing dimensions use physical size/resolution. Defaults and exact Photoshop rendering remain unqualified.",
     "limits":"Transfer permission and current bearer token. Native32 output pages; API available share slots up to8,4MP/page,128MiB combined decoded/render budget. CoreGraphics cancellation is checked before/after a page render. Bounding uses raster alpha within Trim Box at requested resolution. Blank pages retain Trim Box.",
     "state":"pdfImportState reports native dialog/loading/rendering and active API operation ID. No file paths or passwords are exposed.",
     "stateSchema":BrushAPI.object(["content":["type":["string","null"],"enum":["pages","images",NSNull()]],"open":["type":"boolean"],"loading":["type":"boolean"],"rendering":["type":"boolean"],"uploadOperationID":["type":["string","null"],"format":"uuid"]],required:["content","open","loading","rendering","uploadOperationID"]),
     "inspectionResultSchema":inspectionSchema,
     "importResultSchema":BrushAPI.object(["count":["type":"integer","minimum":1,"maximum":8],"documents":["type":"array","minItems":1,"maxItems":8,"items":["type":"object","additionalProperties":true,"required":["id","revision","isModified"],"properties":["id":["type":"string","format":"uuid"],"revision":["type":"string"],"isModified":["type":"boolean"]]]]],required:["count","documents"]),
     "errors":["400":"Invalid headers/settings","401":"Authentication","403":"Transfers disabled","409":"Busy/cancelled/revoked/lifecycle changed","413":"Source size","415":"Content type","422":"PDF decode/password/unsupported dimensions","429":"Sharing capacity"],
     "remaining":"Full image color/depth/default/ordering fidelity, PDF-backed Smart Objects, Photoshop PDF editing data, custom import profiles, full metadata/annotation/form/large-file handling and exact/live/platform parity.",
     "adobe":"Photato PDF upload extension only. The pinned Adobe v2 contract has no corresponding desktop PDF selection/import route; existing Adobe operations are unchanged."]
  }
  static var inspectionSchema: [String:Any] {
    let box: [String:Any] = ["type":"array","minItems":2,"maxItems":2,"items":["type":"number","exclusiveMinimum":0]]
    let page = BrushAPI.object(["number":["type":"integer","minimum":1,"maximum":4096],"rotation":["type":"integer"],
      "boxes":BrushAPI.object(Dictionary(uniqueKeysWithValues:["media","crop","bleed","trim","art"].map{($0,box)}),required:["media","crop","bleed","trim","art"])],required:["number","rotation","boxes"])
    return BrushAPI.object(["pages":["type":"array","minItems":1,"maxItems":4096,"items":page],"encrypted":["type":"boolean"],
      "thumbnails":["type":"object","additionalProperties":BrushAPI.object(["contentType":["type":"string","const":"image/png"],"data":["type":"string","contentEncoding":"base64"]],required:["contentType","data"])]],required:["pages","encrypted","thumbnails"])
  }
}

extension AutomationService {
  var pdfImportState: [String:Any] {
    ["content":controller.documentOpening.pdfWorkspace?.content.rawValue as Any? ?? NSNull(),"open":controller.documentOpening.pdfWorkspace != nil,"loading":controller.documentOpening.pdfWorkspace?.loading ?? false,
     "rendering":controller.documentOpening.pdfWorkspace?.busy ?? false,"uploadOperationID":pdfImportOperationID?.uuidString as Any? ?? NSNull()]
  }
  func handlePDFImport(_ request: AutomationRequest) async throws -> AutomationResponse? {
    guard request.method == "POST",[PDFImportAPI.inspectPath,PDFImportAPI.importPath,PDFImportAPI.cancelPath,PDFImageImportAPI.inspectPath,PDFImageImportAPI.importPath].contains(request.path) else{return nil}
    guard documentTransfersEnabled else {throw AutomationFailure(status:403,message:"Enable document transfers before importing or inspecting PDF files.")}
    if request.path == PDFImportAPI.cancelPath {
      guard request.headers["content-type"]?.lowercased().split(separator:";").first == "application/json",
        let values = try? JSONDecoder().decode([String:AutomationValue].self,from:request.body),Set(values.keys) == ["operationID"],
        case .string(let raw) = values["operationID"],let id = UUID(uuidString:raw) else {throw AutomationFailure(status:400,message:"Supply a JSON object with the current PDF import operationID.")}
      guard id == pdfImportOperationID,let task = pdfImportTask else {throw AutomationFailure(status:409,message:"That PDF operation is no longer active.")}
      task.cancel();return .json(["operationID":id.uuidString,"cancellationRequested":true])
    }
    guard !documentTransferBusy,controller.canFinishMovieFrames else {throw AutomationFailure(status:409,message:"Finish document opening, closing or transfer before importing PDF pages.")}
    guard request.headers["content-type"]?.lowercased().split(separator:";").first == "application/pdf" else {throw AutomationFailure(status:415,message:"Use application/pdf for PDF inspection/import.")}
    guard !request.body.isEmpty,request.body.count <= PDFImport.maximumSourceBytes else {throw AutomationFailure(status:413,message:"Choose a PDF from1byte to64MiB.")}
    let imageMode = [PDFImageImportAPI.inspectPath,PDFImageImportAPI.importPath].contains(request.path)
    let inspecting = [PDFImportAPI.inspectPath,PDFImageImportAPI.inspectPath].contains(request.path)
    if inspecting,request.headers[PDFImportAPI.optionsHeader] != nil {throw AutomationFailure(status:400,message:"Render options apply to PDF import, not inspection.")}
    if !inspecting,request.headers["x-photato-pdf-thumbnails"] != nil {throw AutomationFailure(status:400,message:"Thumbnail selections apply to PDF inspection.")}
    let options = try imageMode ? PDFImportSettings():PDFImportAPI.options(request.headers[PDFImportAPI.optionsHeader])
    let imageOptions = try imageMode ? PDFImageImportAPI.options(request.headers[PDFImportAPI.optionsHeader]):PDFImageImportSettings()
    let selectedCount = imageMode ? imageOptions.images.count:options.pages.count
    let password = try PDFImportAPI.password(request.headers["x-photato-pdf-password"])
    let previews = try PDFImportAPI.thumbnailPages(request.headers["x-photato-pdf-thumbnails"])
    let name = request.headers["x-photato-name"] ?? "Imported PDF"
    guard !name.trimmingCharacters(in:.whitespaces).isEmpty,name.utf8.count <= 240,name.utf8.allSatisfy({(32...126).contains($0)}) else {throw AutomationFailure(status:400,message:"X-Photato-Name must contain1–240 printable ASCII characters.")}
    guard inspecting || shares.count+selectedCount <= 8 else {throw AutomationFailure(status:429,message:"Leave one sharing slot available for each imported PDF page.")}
    let transfer = documentTransferGeneration,expectedToken = token,service = generation
    let opening = controller.documentOpening.generation,closing = controller.documentClosing.state?.id
    let maintenance = controller.recoveryMaintenance.generation,discovery = controller.recoveryDiscovery.generation
    let id = UUID();pdfImportOperationID = id;documentTransferBusy = true
    let decoder = pdfPageDecoder,imageDecoder = pdfImageDecoder
    let job = Task.detached(priority:.userInitiated) { () throws -> PDFImportAPI.Prepared in
      if inspecting && imageMode {
        let info = try PDFImages.inspect(request.body,password:password)
        var thumbnails: [Int:Data] = [:]
        for number in previews {try Task.checkCancellation();thumbnails[number] = try PDFImages.thumbnail(request.body,image:number,password:password)}
        return .imageInspection(info,thumbnails)
      }
      if inspecting {
        let info = try PDFImport.inspect(request.body,password:password)
        var thumbnails: [Int:Data] = [:]
        for page in previews {try Task.checkCancellation();thumbnails[page] = try PDFImport.thumbnail(request.body,page:page,password:password)}
        return .inspection(info,thumbnails)
      }
      return .documents(try imageMode ? imageDecoder(request.body,name,imageOptions,password):decoder(request.body,name,options,password))
    };pdfImportTask = job
    defer {if pdfImportOperationID == id {pdfImportOperationID = nil;pdfImportTask = nil};documentTransferBusy = false}
    let result = try await withTaskCancellationHandler {try await job.value} onCancel:{job.cancel()}
    try Task.checkCancellation();guard !job.isCancelled else {throw CancellationError()}
    guard isRunning,token == expectedToken,generation == service,documentTransfersEnabled,documentTransferGeneration == transfer,
      controller.canFinishMovieFrames,controller.documentOpening.generation == opening,controller.documentClosing.state?.id == closing,
      controller.recoveryMaintenance.generation == maintenance,controller.recoveryDiscovery.generation == discovery else {
      throw AutomationFailure(status:409,message:"PDF import was cancelled, revoked or interrupted by a document operation.")
    }
    switch result {
    case .inspection(let info,let images):
      var object = try PDFImportJSON.object(info)
      object["thumbnails"] = Dictionary(uniqueKeysWithValues:images.map{(String($0.key),["contentType":"image/png","data":$0.value.base64EncodedString()])})
      return .json(object)
    case .imageInspection(let info,let images):
      let values = try JSONSerialization.jsonObject(with:JSONEncoder().encode(info))
      let thumbnails = Dictionary(uniqueKeysWithValues:images.map{(String($0.key),["contentType":"image/png","data":$0.value.base64EncodedString()])})
      return .json(["images":values,"thumbnails":thumbnails])
    case .documents(let models):
      guard models.count == selectedCount else {throw AutomationFailure(status:422,message:"PDF decoder returned an incomplete page selection.")}
      for model in models {try Self.checkLimits(model)}
      guard shares.count+models.count <= 8 else {throw AutomationFailure(status:429,message:"Document sharing capacity changed during PDF import.")}
      let created = models.map{CraftNSDocument(model:$0)}
      do {for document in created {controller.addDocument(document);try share(document)}} catch {
        for document in created {for share in shares.filter({$0.document === document}) {revoke(share.id)};controller.removeDocument(document)}
        throw error
      }
      for document in created {document.updateChangeCount(.changeDone);document.makeWindowControllers();document.showWindows()}
      let states = try created.map {document -> [String:Any] in
        guard let share = shares.first(where:{$0.document === document}) else {throw AutomationFailure(status:409,message:"PDF document sharing ended.")}
        return state(share,document:document)
      }
      return .json(["documents":states,"count":created.count],status:201)
    }
  }
}

private enum PDFImportJSON {
  static func object<T: Encodable>(_ value: T) throws -> [String:Any] {
    guard let object = try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any] else {throw CraftError.invalid("Invalid PDF inspection result.")}
    return object
  }
}
