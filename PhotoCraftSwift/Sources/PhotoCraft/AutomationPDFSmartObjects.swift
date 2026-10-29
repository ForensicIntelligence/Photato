import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension PDFSmartObjectSource {
  static var apiSchema: [String:Any] {
    BrushAPI.object([
      "page":["type":"integer","minimum":1,"maximum":4096],
      "image":["type":["integer","null"],"minimum":1,"maximum":4096],
      "crop":["type":"string","enum":Crop.allCases.map(\.rawValue)],
      "x":["type":"number","minimum":0,"maximum":1_000_000],
      "y":["type":"number","minimum":0,"maximum":1_000_000],
      "width":["type":"number","exclusiveMinimum":0,"maximum":1_000_000],
      "height":["type":"number","exclusiveMinimum":0,"maximum":1_000_000],
      "antialias":["type":"boolean"]],required:["page","crop","x","y","width","height","antialias"])
  }
}

struct PDFSmartObjectOptions: Codable, Sendable {
  var page = 1
  var image: Int?
  var transform: Transform2D?
  var crop = PDFImportSettings.Crop.bounding
  var resolution = 72.0
  var antialias = true
  var fit = true
  var layerID: UUID?
  var preserveSize = true
  var allInstances = true
  var settings: PDFImportSettings {
    var value = PDFImportSettings();value.pages = [page];value.crop = crop
    value.resolution = resolution;value.antialias = antialias;return value
  }
}

enum PDFSmartObjectAPI {
  static var schema: [String:Any] {
    var transform = AutomationCommand.frameSchema("transform");transform["type"] = ["object","null"]
    return BrushAPI.object([
      "transform":transform,
      "page":["type":"integer","minimum":1,"maximum":4096],
      "image":["type":["integer","null"],"minimum":1,"maximum":4096],
      "crop":["type":"string","enum":PDFImportSettings.Crop.allCases.map(\.rawValue)],
      "resolution":["type":"number","minimum":1,"maximum":10000],
      "antialias":BrushAPI.flag,"fit":BrushAPI.flag,
      "layerID":["type":["string","null"],"format":"uuid"],
      "preserveSize":BrushAPI.flag,"allInstances":BrushAPI.flag])
  }
  static func options(_ header: String?) throws -> PDFSmartObjectOptions {
    do {
      guard let header else {return .init()}
      guard header.utf8.count <= 4096 else {throw CraftError.invalid("PDF placement options exceed4KiB.")}
      let raw = try JSONDecoder().decode(AutomationValue.self,from:Data(header.utf8))
      let merged = try BrushAPI.merge(raw,schema:schema,base:BrushAPI.json(PDFSmartObjectOptions()),path:"pdfSmartObject")
      let value = try JSONDecoder().decode(PDFSmartObjectOptions.self,from:JSONSerialization.data(withJSONObject:merged))
      try value.settings.validate()
      if let image = value.image,!(1...4096).contains(image) {throw CraftError.invalid("Choose an embedded image from1 through4096.")}
      try value.transform?.validated()
      if case .object(let fields) = raw {
        guard value.image == nil || (fields["page"] == nil && fields["crop"] == nil) else {
          throw CraftError.invalid("Choose either a page/crop or one embedded image.")
        }
        guard value.layerID == nil ? fields["preserveSize"] == nil && fields["allInstances"] == nil : fields["fit"] == nil else {
          throw CraftError.invalid("fit applies to placement; preserveSize/allInstances apply to replacement.")
        }
        guard value.layerID == nil || fields["transform"] == nil else {throw CraftError.invalid("Initial transform applies to placement only.")}
      }
      return value
    } catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
  static func prepare(_ data: Data,_ name: String,_ original: CraftDocument,_ options: PDFSmartObjectOptions) throws -> Command {
    if let layerID = options.layerID {
      return try PDFSmartObjectIO.replacement(data,fileName:name,in:original,layerID:layerID,
        settings:options.settings,image:options.image,preserveSize:options.preserveSize,allInstances:options.allInstances)
    }
    var layer = try PDFSmartObjectIO.placed(data,fileName:name,in:original,settings:options.settings,image:options.image,fit:options.fit)
    if let transform = options.transform {layer = try DocumentGeometry.transformLayer(layer,by:transform,in:original)}
    _ = try PDFSmartObjectIO.renderedLayer(layer,in:original)
    return .addLayer(layer)
  }
  static var capabilities: [String:Any] {
    ["method":"POST","path":"/v1/documents/{id}/smart-objects/pdf",
     "contentType":"application/pdf","optionsHeader":"X-Photato-PDF-Options","schema":schema,
     "revisionHeader":"Required X-Photato-Revision for the shared target; stale/missing returns409.",
     "nameHeader":"Optional X-Photato-Name filename; default Contents.pdf; at most240 printable ASCII bytes without path separators.",
     "result":"HTTP200 shared target state. Missing layerID adds a centered embedded Smart Object; layerID replaces that source. One native Undo transaction.",
     "defaults":"Page1, bounding crop,72ppi, antialias, fit placement; replacement preserves size and updates shared instances. Exact Adobe defaults remain unqualified.",
     "source":"Original PDF bytes, selected page and fixed point-space crop are retained in native62. Enlargement re-renders vectors. Source download returns the original whole PDF.",
     "cancel":"POST /v1/documents/{id}/smart-objects/pdf/cancel with {operationID:UUID}; active IDs are in capabilities.pdfSmartObjectOperations, keyed by shared document UUID.",
     "limits":"Transfers must be enabled. Source64MiB;8MP native source/render budget plus shared-document limits before atomic commit. Encrypted sources reject; passwords are not persisted.",
     "selection":"Select page/crop or image (1…4096); image excludes page/crop fields and retains intrinsic image dimensions. Both retain the original PDF source.",
     "initialTransform":"Optional placement-only transform {a,b,c,d,tx,ty} applies in document coordinates after centering/fit, in the same Undo transaction. Native preview uses the same geometry; per-document pdfPlacement reports chooser/transform state.",
     "remaining":"PDF Warp, editable PSD/PDF source editing, linked files, large-file memory and exact/live/platform qualification.",
     "adobe":"Existing create-composite/edit Smart Object file inputs accept PDF through this engine, with autoResize source matching. No new Adobe routes or page-selection fields."]
  }
}

extension AutomationService {
  func handlePDFSmartObject(_ request: AutomationRequest) async throws -> AutomationResponse? {
    let parts = request.path.split(separator:"/")
    guard request.method == "POST", (parts.count == 5 || parts.count == 6),
      parts[0] == "v1", parts[1] == "documents", parts[3] == "smart-objects", parts[4] == "pdf",
      request.path == "/"+parts.joined(separator:"/"), parts.count == 5 || parts[5] == "cancel" else {return nil}
    guard let id = UUID(uuidString:String(parts[2])),let share = shares.first(where:{$0.id == id}),
      let document = share.document else {throw AutomationFailure(status:404,message:"Shared document not found.")}
    if parts.count == 6 {
      guard request.body.count <= 4096,
        let fields = try? JSONSerialization.jsonObject(with:request.body) as? [String:Any],
        Set(fields.keys) == ["operationID"],let value = fields["operationID"] as? String,
        let operation = UUID(uuidString:value) else {throw AutomationFailure(status:400,message:"Provide one PDF placement operationID.")}
      guard pdfSmartObjectOperations[id] == operation else {throw AutomationFailure(status:409,message:"PDF placement operation changed.")}
      document.store.geometryTask?.cancel()
      return .json(["operationID":operation.uuidString,"cancellationRequested":true])
    }
    guard documentTransfersEnabled else {throw AutomationFailure(status:403,message:"Enable document transfers before placing PDF artwork.")}
    try preflight(document)
    guard let expected = request.headers["x-photato-revision"],expected == revision(document.store) else {
      throw AutomationFailure(status:409,message:"Stale or missing PDF placement revision.")
    }
    guard request.headers["content-type"]?.split(separator:";").first?.lowercased() == "application/pdf" else {
      throw AutomationFailure(status:415,message:"Send application/pdf source bytes.")
    }
    guard !request.body.isEmpty,request.body.count <= PDFImport.maximumSourceBytes else {
      throw AutomationFailure(status:413,message:"PDF source must contain1 byte through64MiB.")
    }
    let options = try PDFSmartObjectAPI.options(request.headers["x-photato-pdf-options"])
    let name = request.headers["x-photato-name"] ?? "Contents.pdf"
    guard !name.trimmingCharacters(in:.whitespaces).isEmpty,name.utf8.count <= 240,
      name.utf8.allSatisfy({(32...126).contains($0)}),!name.contains("/"),!name.contains("\\") else {
      throw AutomationFailure(status:400,message:"Choose a PDF filename of at most240 printable ASCII bytes without path separators.")
    }
    let data = request.body,operation = UUID(),generation = documentTransferGeneration
    let prepare = pdfSmartObjectPreparation
    pdfSmartObjectOperations[id] = operation
    defer {if pdfSmartObjectOperations[id] == operation {pdfSmartObjectOperations.removeValue(forKey:id)}}
    try await executePreparedOperation(document:document,shareID:id,revision:expected,validateCommit:{[weak self] in
      guard let self,self.documentTransfersEnabled,self.documentTransferGeneration == generation else {
        throw AutomationFailure(status:409,message:"PDF transfer permission changed.")
      }
    }) { original in
      try await prepare(data,name,original,options)
    }
    document.store.selectedLayerIDs = Set(document.store.document.activeLayerID.map{[$0]} ?? [])
    return .json(state(share,document:document))
  }
}
