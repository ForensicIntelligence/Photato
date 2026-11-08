import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension SmartObject {
  var apiState: [String: Any] {
    ["sourceID": sourceID.uuidString, "revision": revision, "fileName": fileName,
      "mediaType": mediaType, "byteLength": data.count, "width": width, "height": height,
      "layerComps": layerComps.map { BrushAPI.json($0) } ?? NSNull(),
      "resolution": resolution, "embedded": linkedSource==nil,"linked":linkedSource != nil,"originalAvailable":!data.isEmpty,"sourceByteLength":linkedSource?.byteLength ?? UInt64(data.count), "pdfSource": pdfSource.map { BrushAPI.json($0) } ?? NSNull(), "stackMode": stackMode?.rawValue ?? "none", "rawDevelopment": rawDevelopment.map { (try? JSONSerialization.jsonObject(with:JSONEncoder().encode($0))) ?? NSNull() } ?? NSNull()]
  }
  static var apiLayerStateSchema: [String: Any] {
    ["type": "object", "properties": [
      "kind": ["type": "string"],
      "sourceSmartObject":SourceSmartObjectAPI.stateSchema,
      "transform": ["type": "object", "required": ["a", "b", "c", "d", "tx", "ty"],
        "properties": Dictionary(uniqueKeysWithValues: ["a", "b", "c", "d", "tx", "ty"].map { ($0, ["type": "number"]) })],
      "smartObject": ["anyOf": [["type": "null"], ["type": "object",
        "required": ["sourceID", "revision", "fileName", "mediaType", "byteLength", "width", "height", "resolution", "embedded"],
        "properties": ["sourceID": ["type": "string", "format": "uuid"], "revision": ["type": "string"],
          "fileName": ["type": "string"], "mediaType": ["type": "string"], "byteLength": ["type": "integer"],
          "width": ["type": "integer"], "height": ["type": "integer"], "resolution": ["type": "number"], "embedded": ["type": "boolean"],"linked":["type":"boolean"],"originalAvailable":["type":"boolean"],"sourceByteLength":["type":"integer","minimum":0], "layerComps": SmartObjectLayerCompAPI.stateSchema, "pdfSource": ["anyOf":[["type":"null"],PDFSmartObjectSource.apiSchema]], "stackMode": ImageStackSettings.modeSchema, "rawDevelopment": ["anyOf":[["type":"null"],RawDevelopment.apiSchema]]]]]]]]
  }
  static var apiCapabilities: [String: Any] {
    ["rasterizationPreparation":["command":"layer.rasterize","native":"Native Rasterize and the Photato API use the same SmartObjectIO rasterization command and detached prepared transaction. Ordinary layers and retained PDF sources render/convert pixels away from the main actor. One Undo; source/session validation and cancellation prevent partial or stale edits.","state":"Existing geometryBusy/progress/error/history state and guards apply. Native submission is asynchronous; callers await the existing geometry task before reading committed content.","limits":"No rendering kernel, command, archive, Actions version or Adobe descriptor change. Exact Photoshop output/default/platform/capacity and physical presentation/performance remain unqualified."],"sourceProjectImport":SourceSmartObjectAPI.capabilities, "embedded": true, "linked": true, "maximumSourceBytes": maximumSourceBytes,
      "maximumSourcePixels": SmartObjectIO.maximumCanvasPixels,
      "largeRGBSources":["logicalMaximumPixels":SmartObjectIO.maximumPagedRGBPixels,
        "maximumDimension":Surface.maxDimension,"maximumOwnedContentBytes":256*1_024*1_024,
        "maximumEncodedSourceBytes":maximumSourceBytes,
        "limits":"Paged native/RGB input and editable conversion retain independent format, source-byte, owned-heap and physical scratch limits. maximumSourcePixels remains the common non-RGB/PDF preparation limit; dense maximum capacity and full Photoshop/platform parity remain open."],
      "layerCompSelection": SmartObjectLayerCompAPI.capabilities,
      "convertToLayers": ["command":"smartObject.convertToLayers", "parameterSchema":AutomationCommand.definitions.first(where:{$0.name=="smartObject.convertToLayers"})!.schema,
        "native":"Layer > Smart Objects > Convert to Layers and the Layers context menu use SmartObjectUnpack through the same detached, source-bound prepared transaction as the API. One Undo/Redo for all selected instances.",
        "state":"Existing document layers/group hierarchy, Smart Object, type/shape/style/pattern metadata and busy/history/error/revision state; no new document representation or archive version.",
        "behavior":"Restore source layer coordinates and selected source Layer Comp. Discard the outer source transform, warp, projection, stack mode and Smart Filters. Multiple source layers become an isolated group. General outer blending/masks/styles are retained on a folder when they cannot be folded into a single layer. Nested sources and conflicting pattern identities are remapped without overwriting existing assets.",
        "availability":"Selected unlocked RGB Smart Objects with retained original bytes; static RGB sources with matching working profiles. Source decoding and validation occur during preparation. Linked source paths are never read. Missing/corrupt sources, unsupported mode/profile/temporal/PDF/RAW/artboard/variable transfers and capacity violations reject atomically.",
        "recording":"Portable Actions replay is not implemented for this source-decoding operation; recording reports unsupported rather than recording Rasterize.",
        "adobe":"No dedicated endpoint in the pinned Firefly v2 contract. UXP/actionJSON runtime or descriptor conformance is not claimed.",
        "qualification":"Adobe documents component restoration/grouping and transform/Smart Filter removal. Exact placement, outer attachments/defaults, numerical output and live/platform/capacity qualification remain open."],
      "layerStateSchema": apiLayerStateSchema, "pdfSourceSchema": PDFSmartObjectSource.apiSchema, "pdfNativeArchiveVersion": 62, "pdfPlacement": PDFSmartObjectAPI.capabilities, "sourcePlacement": EmbeddedSourceAPI.capabilities, "sourceEditing":PDFSourceEditAPI.capabilities,"linkedSourceEditing":LinkedSourceFileAPI.capabilities,
      "pdfPSDInterchange": ["read":true,"write":true,"containers":["psd","psb"],"sourceBytesPreserved":true,
        "selection":"PDF pages, crop boxes, source dimensions/resolution, shared identity and affine placement. Embedded PDF image selection and non-default antialias policies require native saving.",
        "routes":"Existing document import, file.psd/file.psb export and Adobe v2 resource jobs use the same native codec.",
        "limits":"PDF render/source budgets; no linked files, PDF Warp or full Photoshop output/default/platform equivalence claim."],
      "commands": [SmartObjectLayerCompAPI.name, "smartObject.stackMode", "layer.transform", "smartObject.convert", "smartObject.convertToLayers", "smartObject.place", "smartObject.replace", "smartObject.copy", "smartObject.resetTransform", "layer.rasterize"],
      "sourceDownload": "/v1/documents/{documentID}/smart-objects/{layerID}/source",
      "sourceInput": "smartObject.place/replace take sourceDocumentID/sourceRevision from an explicitly shared document and embed an editable Photato snapshot. sourcePlacement uploads original file bytes without converting their format; pdfPlacement offers PDF page/image selection.",
      "history": "One native transaction; ordinary duplicates share replacements. copy creates independent content. allInstances defaults to true.",
      "linkedArtwork": LinkedArtworkAPI.capabilities,
      "limitations": "Embedded raster/native/PSD/RAW sources and retained PDF page/image sources. PDF uses native62; filtered and affine rendering reuses the native engine. PSD/PSB retains PDF page sources under pdfPSDInterchange limits. PDF Warp, full editable PDF/PSD interchange, PDF source-editor live acceptance, linked PSD exact fidelity, nested source monitoring, package and general AI/SVG import remain unqualified or pending."]
  }
}

extension AutomationCommand {
  func smartObjectCommand(document: CraftDocument, source: CraftDocument? = nil) throws -> Command {
    func id() throws -> UUID {
      guard let id = UUID(uuidString: try string("layerID")), document.layers.contains(where: { $0.id == id }) else {
        throw AutomationFailure(status: 404, message: "Layer not found.")
      }
      return id
    }
    func flag(_ key: String, _ fallback: Bool) throws -> Bool {
      guard let value = parameters[key] else { return fallback }
      guard case .bool(let flag) = value else { throw AutomationFailure(status: 400, message: "\(key) must be boolean.") }
      return flag
    }
    switch name {
    case "smartObject.stackMode":
      let text = try string("mode")
      guard text == "none" || ImageStackMode(rawValue:text) != nil else { throw AutomationFailure(status:400,message:"Unknown stack mode.") }
      return try ImageStack.command(in:document,layerID:id(),mode:ImageStackMode(rawValue:text))
    case "layer.transform":
      let t = try Transform2D(a: number("a", range: -1_000_000...1_000_000), b: number("b", range: -1_000_000...1_000_000),
        c: number("c", range: -1_000_000...1_000_000), d: number("d", range: -1_000_000...1_000_000),
        tx: number("tx", range: -1_000_000...1_000_000), ty: number("ty", range: -1_000_000...1_000_000))
      try t.validated()
      return .transform(try id(), t, .bicubic)
    case "smartObject.convert", "smartObject.convertToLayers":
      guard case .array(let values) = parameters["layerIDs"], (1...LayerLimits.maximumLayers).contains(values.count) else {
        throw AutomationFailure(status: 400, message: "Select one to 8,000 layer UUIDs.")
      }
      let ids = try values.map { value -> UUID in
        guard case .string(let text) = value, let id = UUID(uuidString: text) else {
          throw AutomationFailure(status: 400, message: "Invalid layer UUID.")
        }
        return id
      }
      guard Set(ids).count == ids.count else { throw AutomationFailure(status: 400, message: "Duplicate layer UUID.") }
      if name == "smartObject.convertToLayers" { return try SmartObjectUnpack.command(in: document, selected: Set(ids)) }
      return try SmartObjectIO.convert(in: document, selected: Set(ids))
    case "frame.place":
      guard let source else { throw AutomationFailure(status:404,message:"Source document is not shared.") }
      return try .frame(.replace(id(), SmartObjectIO.placed(data: NativeArchive.encodeChunked(source), fileName: "Contents.photato", in: document), fit: frameFit()))
    case "smartObject.place":
      guard let source else { throw AutomationFailure(status: 404, message: "Source document is not shared.") }
      var options = EmbeddedSourceOptions();options.fit = try flag("fit",true)
      if let transform = parameters["transform"] {
        guard case .object(let fields) = transform,Set(fields.keys) == ["a","b","c","d","tx","ty"] else {throw AutomationFailure(status:400,message:"Transform requires a,b,c,d,tx,ty.")}
        let header = try JSONSerialization.data(withJSONObject:["transform":transform.jsonValue])
        options.transform = try EmbeddedSourceAPI.options(String(decoding:header,as:UTF8.self)).transform
      }
      return try EmbeddedSourceAPI.prepare(NativeArchive.encodeChunked(source),"Contents.photato",document,options,decoded:source)
    case "smartObject.replace":
      guard let source else { throw AutomationFailure(status: 404, message: "Source document is not shared.") }
      return try SmartObjectIO.replacement(in: document, layerID: id(), source: source,
        preserveSize: flag("preserveSize", true), allInstances: flag("allInstances", true))
    case "smartObject.copy": return .independentSmartObjectCopy(try id())
    case "smartObject.resetTransform": return .resetSmartObjectTransform(try id())
    case "layer.rasterize":
      let layerID = try id()
      let layer = document.layers.first { $0.id == layerID }!
      return try SmartObjectIO.rasterizationCommand(layer,in:document)
    default: throw AutomationFailure(status: 422, message: "Unsupported Smart Object command.")
    }
  }
}

extension AutomationService {
  func executeSmartObject(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws {
    var source: CraftDocument?
    var sourceShareID: UUID?
    var sourceRevision: String?
    if command.name == "frame.place" || command.name == "smartObject.place" || command.name == "smartObject.replace" {
      guard let id = UUID(uuidString: try command.string("sourceDocumentID")),
        let shared = shares.first(where: { $0.id == id }), let sourceDoc = shared.document else {
        throw AutomationFailure(status: 404, message: "Source document is not shared.")
      }
      try preflight(sourceDoc)
      let expected = try command.string("sourceRevision")
      guard revision(sourceDoc.store) == expected else { throw AutomationFailure(status: 409, message: "Source document changed.") }
      source = sourceDoc.store.document; sourceShareID = id; sourceRevision = expected
    }
    let snapshot = source, capturedID = sourceShareID, capturedRevision = sourceRevision
    try await executePreparedOperation(document: document, shareID: shareID, revision: command.revision,
      validateCommit: { [weak self] in
        if let capturedID {
          guard let self, let doc = self.shares.first(where: { $0.id == capturedID })?.document,
            self.revision(doc.store) == capturedRevision else {
            throw AutomationFailure(status: 409, message: "Source changed or sharing was revoked.")
          }
        }
      }, prepare: { original in try command.smartObjectCommand(document: original, source: snapshot) })
  }
}
