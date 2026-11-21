import Foundation
import PhotoCraftCore
import PhotoCraftImaging

struct BackgroundArtworkPlacement: Codable, Sendable {
  let foregroundLayerID: UUID
  let fit: FrameFit

  static var schema: [String: Any] {
    var value = BrushAPI.object([
      "foregroundLayerID": VariablesAPI.uuid,
      "fit": BrushAPI.enumeration(FrameFit.allCases.map(\.rawValue))
    ], required: ["foregroundLayerID", "fit"])
    value["type"] = ["object", "null"]
    return value
  }
}

struct EmbeddedSourceOptions: Codable, Sendable {
  var transform: Transform2D?
  var fit = true
  var sizing = SmartObjectPlacementSizing.pixels
  var rasterize = false
  var layerID: UUID?
  var frameID: UUID?
  var frameFit = FrameFit.fill
  var preserveSize = true
  var allInstances = true
  var rawDevelopment: RawDevelopment?
  var background: BackgroundArtworkPlacement?
}

enum EmbeddedSourceAPI {
  static let path = "/v1/documents/{id}/smart-objects/source"
  static var sizingSchema: [String: Any] {
    ["type": "string", "enum": SmartObjectPlacementSizing.allCases.map(\.rawValue), "default": "pixels"]
  }
  static var schema: [String:Any] {
    var transform = AutomationCommand.frameSchema("transform");transform["type"] = ["object","null"]
    var raw = RawDevelopment.apiSchema;raw["type"] = ["object","null"]
    return BrushAPI.object(["transform":transform,"fit":BrushAPI.flag,"sizing":sizingSchema,"rasterize":BrushAPI.flag,
      "layerID":["type":["string","null"],"format":"uuid"],
      "frameID":["type":["string","null"],"format":"uuid"],
      "frameFit":["type":"string","enum":FrameFit.allCases.map(\.rawValue)],
      "preserveSize":BrushAPI.flag,"allInstances":BrushAPI.flag,"rawDevelopment":raw,
      "background":BackgroundArtworkPlacement.schema])
  }
  static func options(_ header: String?) throws -> EmbeddedSourceOptions {
    do {
      guard let header else {return .init()}
      guard header.utf8.count <= 8192 else {throw CraftError.invalid("Placement options exceed8KiB.")}
      let raw = try JSONDecoder().decode(AutomationValue.self,from:Data(header.utf8))
      var defaults = EmbeddedSourceOptions()
      if case .object(let fields) = raw,case .object = fields["rawDevelopment"] {defaults.rawDevelopment = RawDevelopment()}
      let merged = try BrushAPI.merge(raw,schema:schema,base:BrushAPI.json(defaults),path:"embeddedSource")
      let value = try JSONDecoder().decode(EmbeddedSourceOptions.self,from:JSONSerialization.data(withJSONObject:merged))
      try value.transform?.validated();try value.rawDevelopment?.validate()
      guard value.layerID == nil || value.frameID == nil else {throw CraftError.invalid("Choose replacement or frame placement, not both.")}
      if case .object(let fields) = raw {
        if value.background != nil,
          !Set(fields.keys).isDisjoint(with: ["layerID", "frameID", "transform", "fit", "sizing", "rasterize",
            "preserveSize", "allInstances", "frameFit"]) {
          throw CraftError.invalid("Background artwork uses its own placement options.")
        }
        let ordinary = value.layerID == nil && value.frameID == nil
        guard ordinary || (fields["fit"] == nil && fields["sizing"] == nil
          && fields["transform"] == nil && fields["rasterize"] == nil) else {
          throw CraftError.invalid("Fit, sizing, transform and rasterize apply to new layer placement only.")
        }
        guard value.layerID != nil || (fields["preserveSize"] == nil && fields["allInstances"] == nil) else {throw CraftError.invalid("preserveSize/allInstances apply to replacement only.")}
        guard value.frameID != nil || fields["frameFit"] == nil else {throw CraftError.invalid("frameFit requires frameID.")}
      }
      return value
    } catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
  static func prepare(_ data: Data,_ name: String,_ original: CraftDocument,_ options: EmbeddedSourceOptions,
    decoded: CraftDocument? = nil) throws -> Command {
    try prepare(.memory(data),name,original,options,decoded:decoded)
  }
  static func prepare(_ bytes: EmbeddedSourceBytes,_ name: String,_ original: CraftDocument,_ options: EmbeddedSourceOptions,
    decoded: CraftDocument? = nil) throws -> Command {
    let data = bytes.data
    guard !data.isEmpty,data.count <= SmartObject.maximumEmbeddedBytes(for: bytes) else {
      throw CraftError.invalid("Encoded Smart Object source exceeds its file format's limit.")
    }
    guard !PDFImport.recognizes(data) else {throw CraftError.invalid("Use the PDF placement endpoint to choose PDF artwork.")}
    if let background = options.background,
      BackgroundReplacement.foreground(in: original)?.id != background.foregroundLayerID {
      throw CraftError.invalid("The masked foreground is no longer available.")
    }
    var source = try decoded ?? SmartObjectIO.decode(bytes,fileName:name)
    if let settings = options.rawDevelopment {
      guard RawSourceIO.recognizes(data),let id = source.layers.first?.id else {throw CraftError.invalid("RAW settings require a camera RAW source.")}
      try RawSourceIO.command(in:source,layerID:id,settings:settings).apply(to:&source)
    }
    if let id = options.layerID {
      return try SmartObjectIO.replacement(in:original,layerID:id,source:source,original:bytes,fileName:name,
        preserveSize:options.preserveSize,allInstances:options.allInstances)
    }
    var layer = try SmartObjectIO.placed(document: source, original: bytes, fileName: name, in: original,
      fit: options.background == nil && options.fit, sizing: options.sizing)
    if let background = options.background {
      return try BackgroundReplacement.artwork(layer, fit: background.fit, in: original, foregroundID: background.foregroundLayerID)
    }
    if let id = options.frameID {return .frame(.replace(id,layer,fit:options.frameFit))}
    if let transform = options.transform {layer = try DocumentGeometry.transformLayer(layer,by:transform,in:original)}
    if options.rasterize { layer = try ArtworkPlacementPreparation.finish(layer, in: original, rasterize: true) }
    return .addLayer(layer)
  }
  static var stateSchema: [String:Any] {
    BrushAPI.object(["stage":["type":"string","enum":["preparing","choosingPDF","developingRaw","transform","committing","idle"]],
      "layerID":["type":["string","null"],"format":"uuid"],"sourceName":["type":["string","null"]],
      "mediaType":["type":["string","null"]]],required:["stage","layerID","sourceName","mediaType"])
  }
  static var capabilities: [String:Any] {
    ["method":"POST","path":path,"contentType":"application/octet-stream",
     "optionsHeader":"X-Photato-Placement-Options","schema":schema,"stateSchema":stateSchema,
     "revisionHeader":"Required X-Photato-Revision; stale/missing returns409.",
     "nameHeader":"Optional X-Photato-Name, default Contents.photato; at most240 printable ASCII bytes without path separators.",
     "result":"HTTP200 shared target state. New layer by default; layerID replaces content, frameID replaces frame artwork. One native Undo transaction.",
     "background":"Use background:{foregroundLayerID,fit} to place an embedded image below the active masked layer. fit is fill, fit or original. The original image and subject mask stay editable.",
     "source":"Original raster, native, supported PhotoCraft ZIP projects, PSD/PSB or supported camera RAW bytes remain embedded and downloadable. RAW settings are retained separately. PDF uses the existing pdf endpoint.",
     "initialTransform":"Optional document-coordinate delta after centering/fit, committed with placement in one edit. Set rasterize to true to bake the final geometry into a pixel layer. API defaults fit:true and rasterize:false are independent of General preferences. The desktop can offer a cancellable transform preview; RAW first opens native Camera Raw controls.",
     "sizing":"The desktop uses physical source size. API sizing:pixels retains the original pixel grid by default. Choose sizing:physical to match source inches in the destination PPI. Fit reduces oversized artwork after sizing.",
     "state":"Per-document embeddedPlacement exposes preparing, choosingPDF, developingRaw, transform, committing or idle. PDF-specific state remains separate.",
     "cancel":"POST /v1/documents/{id}/smart-objects/source/cancel with {operationID:UUID}; capabilities.embeddedSourceOperations maps active IDs by shared document UUID.",
     "maximumRGBSourcePixels":SmartObjectIO.maximumPagedRGBPixels,
     "maximumLocalDocumentSourceBytes":SmartObject.maximumFileBackedSourceBytes,
     "limits":"Transfers enabled, explicit target sharing,64MiB encoded source and256MiB owned content. Paged native/RGB sources admit the logical native extent; non-RGB/PDF and RAW retain their decoder limits. Format, physical scratch, dense capacity, cross-profile preparation and shared-document budgets remain independent; permission revocation/stale target/cancellation cannot commit.",
     "adobe":"Existing file-input/bounds/autoResize contracts continue through the shared native engine. PhotoCraft sources remain Photato-only; no new Adobe fields or endpoints.",
     "remaining":"Linked sources, general AI/SVG inputs, complete PSD/RAW fidelity, exact Photoshop pixels/defaults and live/platform acceptance."]
  }
}

extension AutomationService {
  func handleEmbeddedSource(_ request: AutomationRequest) async throws -> AutomationResponse? {
    let parts = request.path.split(separator:"/")
    guard request.method == "POST", (parts.count == 5 || parts.count == 6),
      parts[0] == "v1", parts[1] == "documents", parts[3] == "smart-objects", parts[4] == "source",
      request.path == "/"+parts.joined(separator:"/"), parts.count == 5 || parts[5] == "cancel" else {return nil}
    guard let id = UUID(uuidString:String(parts[2])),let share = shares.first(where:{$0.id == id}),
      let document = share.document else {throw AutomationFailure(status:404,message:"Shared document not found.")}
    if parts.count == 6 {
      guard request.body.count <= 4096,
        let fields = try? JSONSerialization.jsonObject(with:request.body) as? [String:Any],
        Set(fields.keys) == ["operationID"],let value = fields["operationID"] as? String,
        let operation = UUID(uuidString:value) else {throw AutomationFailure(status:400,message:"Provide one Embedded placement operationID.")}
      guard embeddedSourceOperations[id] == operation else {throw AutomationFailure(status:409,message:"Embedded placement operation changed.")}
      document.store.geometryTask?.cancel()
      return .json(["operationID":operation.uuidString,"cancellationRequested":true])
    }
    guard documentTransfersEnabled else {throw AutomationFailure(status:403,message:"Enable document transfers before placing artwork.")}
    try preflight(document)
    guard let expected = request.headers["x-photato-revision"],expected == revision(document.store) else {
      throw AutomationFailure(status:409,message:"Stale or missing Embedded placement revision.")
    }
    guard request.headers["content-type"]?.split(separator:";").first?.lowercased() == "application/octet-stream" else {
      throw AutomationFailure(status:415,message:"Send application/octet-stream source bytes.")
    }
    guard !request.body.isEmpty,request.body.count <= SmartObject.maximumSourceBytes else {
      throw AutomationFailure(status:413,message:"Embedded source must contain1 byte through64MiB.")
    }
    let options = try EmbeddedSourceAPI.options(request.headers["x-photato-placement-options"])
    if let background = options.background, document.store.backgroundReplacementSubject != background.foregroundLayerID {
      throw AutomationFailure(status: 422, message: "Select the masked foreground layer to import a background.")
    }
    let name = request.headers["x-photato-name"] ?? "Contents.photato"
    guard !name.trimmingCharacters(in:.whitespaces).isEmpty,name.utf8.count <= 240,
      name.utf8.allSatisfy({(32...126).contains($0)}),!name.contains("/"),!name.contains("\\") else {
      throw AutomationFailure(status:400,message:"Choose a source filename of at most240 printable ASCII bytes without path separators.")
    }
    let data = request.body,operation = UUID(),generation = documentTransferGeneration
    let prepare = embeddedSourcePreparation
    embeddedSourceOperations[id] = operation
    defer {if embeddedSourceOperations[id] == operation {embeddedSourceOperations.removeValue(forKey:id)}}
    try await executePreparedOperation(document:document,shareID:id,revision:expected,
      allowAuxiliary: options.background != nil, validateCommit:{[weak self] in
      guard let self,self.documentTransfersEnabled,self.documentTransferGeneration == generation else {
        throw AutomationFailure(status:409,message:"Source transfer permission changed.")
      }
    }) { original in
      try await prepare(data,name,original,options)
    }
    if options.background != nil { document.store.finishBackgroundReplacement() }
    else { document.store.selectedLayerIDs = Set(document.store.document.activeLayerID.map{[$0]} ?? []) }
    return .json(state(share,document:document))
  }
}
