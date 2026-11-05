import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum AutomationValue: Decodable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case array([Self])
  case object([String: Self])
  case null
  init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() {
      self = .null
    } else if let b = try? value.decode(Bool.self) {
      self = .bool(b)
    } else if let s = try? value.decode(String.self) {
      self = .string(s)
    } else if let n = try? value.decode(Double.self) {
      self = .number(n)
    } else if let a = try? value.decode([Self].self) {
      self = .array(a)
    } else {
      self = .object(try value.decode([String: Self].self))
    }
  }
}

struct AutomationCommand: Sendable {
  struct Definition {
    let name: String
    let parameters: [String: String]
    let description: String
    var optionalParameters: Set<String> = []
    var schema: [String: Any] {
      var properties: [String: Any] = [:]
      for key in parameters.keys {
        if name == MaskManagementAPI.command { properties[key] = MaskManagementAPI.schema(key); continue }
        if name == GradientFillAPI.command { properties[key] = GradientFillAPI.schema(key); continue }
        if TextFindAPI.commands.contains(name) {properties[key]=TextFindAPI.schema(key);continue}
        if AdvancedStyleAPI.commands.contains(name) {properties[key]=AdvancedStyleAPI.schema(key);continue}
        if LinkedArtworkAPI.commands.contains(name) {properties[key]=LinkedArtworkAPI.schema(key);continue}
        if ChannelArithmeticAPI.commands.contains(name) {properties[key]=ChannelArithmeticAPI.schema(key);continue}
        if name == "smartObject.place",key == "transform" {properties[key] = AutomationCommand.frameSchema(key);continue}
        if ImageProcessorAPI.commands.contains(name) {properties[key] = ImageProcessorAPI.schema(key);continue}
        if ScanCropAPI.commands.contains(name) {properties[key] = ScanCropAPI.schema(key);continue}
        if TimelineAudioAPI.commands.contains(name) { properties[key] = TimelineAudioAPI.schema(key,command:name); continue }
        if TimelineWorkspaceAPI.commands.contains(name) { properties[key] = TimelineWorkspaceAPI.schema(key); continue }
        if VideoRenderAPI.commands.contains(name) { properties[key] = VideoRenderAPI.schema(key); continue }
        if LayerFilesAPI.commands.contains(name) { properties[key] = LayerFilesAPI.schema(key); continue }
        if ImageExportAPI.commands.contains(name) { properties[key] = ImageExportAPI.schema(key, preferences: name == "export.preferences"); continue }
        if LayerCompsAPI.commands.contains(name) { properties[key] = LayerCompsAPI.schema(key); continue }
        if VariablesAPI.commands.contains(name) { properties[key] = VariablesAPI.schema(key); continue }
        if ImageSequenceAPI.commands.contains(name) { properties[key] = ImageSequenceAPI.schema(key); continue }
        if name == VideoKeyframeAPI.name { properties[key]=VideoKeyframeAPI.schema(key);continue }
        if VideoAPI.commands.contains(name) { properties[key] = VideoAPI.schema(key,command:name); continue }
        if AnimationAPI.commands.contains(name) { properties[key] = AnimationAPI.schema(key); continue }
        if ColorProfileAPI.commands.contains(name) { properties[key] = ColorProfileAPI.schema(key); continue }
        if PrintAPI.commands.contains(name) { properties[key] = PrintAPI.schema(key); continue }
        if ProofAPI.commands.contains(name) { properties[key] = ProofAPI.settings; continue }
        if InkChannelAPI.commands.contains(name) { properties[key] = InkChannelAPI.schema(key, command: name); continue }
        if InkModeAPI.commands.contains(name) { properties[key] = InkModeAPI.schema(key); continue }
        if RestrictedModeAPI.commands.contains(name) { properties[key] = RestrictedModeAPI.schema(key, command: name); continue }
        if DocumentModeAPI.commands.contains(name) { properties[key] = DocumentModeAPI.schema(key); continue }
        if ClassicToneAPI.commands.contains(name){properties[key]=ClassicToneAPI.schema(key);continue}
        if let kind=ProceduralAPI.kind(name) {properties[key]=ProceduralAPI.schema(key,kind:kind);continue}
        if AdjustmentBrushAPI.commands.contains(name) {properties[key]=AdjustmentBrushAPI.schema(key);continue}
        if PaintingAPI.commands.contains(name) {properties[key]=PaintingAPI.schema(key);continue}
        if name == RetouchStrokeAPI.name { properties[key] = RetouchStrokeAPI.schema(key); continue }
        if name.hasPrefix("brush.") || name == "paint.stroke" { properties[key]=BrushAPI.schema(key);continue }
        if FontAPI.commands.contains(name){properties[key]=FontAPI.schema(key);continue}
        if PathAPI.commands.contains(name) {properties[key]=PathAPI.schema(key);continue}
        if ShapeAPI.commands.contains(name) { properties[key]=ShapeAPI.schema(key);continue }
        if name.hasPrefix("frame.") { properties[key] = AutomationCommand.frameSchema(key); continue }
        if name == "file.info" { properties[key] = FileInfoAPI.schema(key); continue }
        if name.hasPrefix("guides.") {properties[key]=GuideAPI.schema(key);continue}
        if name.hasPrefix("artboard.") { properties[key] = AutomationCommand.artboardSchema(key); continue }
        if name.hasPrefix("actions.batch") { properties[key] = AutomationCommand.batchSchema(key); continue }
        if PeopleAPI.commands.contains(name) {properties[key]=PeopleAPI.schema(key);continue}
        if ObjectFinderAPI.commands.contains(name) {properties[key]=ObjectFinderAPI.schema(key);continue}
        if CanvasEdgesAPI.commands.contains(name){properties[key]=CanvasEdgesAPI.schema(key);continue}
        if name == DocumentDuplicateAPI.name {properties[key]=DocumentDuplicateAPI.schema(key);continue}
        if name == FlattenImageAPI.name {properties[key]=BrushAPI.flag;continue}
        if BackgroundLayerAPI.commands.contains(name){properties[key]=BackgroundLayerAPI.schema(key);continue}
        if PixelPaintAPI.commands.contains(name){properties[key]=PixelPaintAPI.schema(key);continue}
        if name == LayerFilterAPI.command { properties[key] = LayerFilterAPI.schema(key); continue }
        if name == LayerStackOrderAPI.command { properties[key] = LayerStackOrderAPI.schema(key); continue }
        if LayerLinksAPI.commands.contains(name){properties[key]=LayerLinksAPI.schema(key);continue}
        if name == LayerCollectionTransformAPI.name{properties[key]=LayerCollectionTransformAPI.schema(key);continue}
        if name == ChannelTransformAPI.name{properties[key]=ChannelTransformAPI.schema(key);continue}
        if name == PixelMaskTransformAPI.name{properties[key]=PixelMaskTransformAPI.schema(key);continue}
        if name == SelectedPixelMoveAPI.name{properties[key]=SelectedPixelMoveAPI.schema(key);continue}
        if name == SelectedPixelTransformAPI.name{properties[key]=SelectedPixelTransformAPI.schema(key);continue}
        if name == "selection.transform"{properties[key]=SelectionTransformAPI.schema(key);continue}
        if SelectionModifyAPI.commands.contains(name){properties[key]=SelectionModifyAPI.schema(key);continue}
        if MagneticLassoAPI.commands.contains(name){properties[key]=MagneticLassoAPI.schema(key);continue}
        if name == "selection.colorRange"{properties[key]=ColorRangeAPI.schema(key);continue}
        if name == "selection.focus"{properties[key]=FocusAreaAPI.schema(key);continue}
        if SkyAPI.commands.contains(name) {properties[key]=SkyAPI.schema(key,command:name);continue}
        if SelectionToolAPI.commands.contains(name) {properties[key]=SelectionToolAPI.schema(key);continue}
        if name.hasPrefix("actions.") { properties[key] = AutomationCommand.actionSchema(key); continue }
        if name == "filter.vanishingPoint" {
          if key == "settings" { properties[key]=VanishingSettings.apiSchema;continue }
          if key == "operations" { properties[key]=VanishingSettings.operationSchema;continue }
          if key == "newLayer" { properties[key]=["type":"boolean","default":false];continue }
        }
        if name == "layer.warp",key == "settings" { properties[key] = WarpDefinition.apiSchema;continue }
        if name == "document.contactSheet",key == "settings" || key == "sources" { properties[key] = key == "settings" ? ContactSheetSettings.apiSchema:ContactSheetSettings.sourcesSchema;continue }
        if name == "document.imageStack",key == "settings" || key == "sources" { properties[key] = key == "settings" ? ImageStackSettings.apiSchema:PhotomergeSettings.sourcesSchema;continue }
        if name == SmartObjectLayerCompAPI.name { properties[key] = key == "compID" ? VariablesAPI.nullableUUID : VariablesAPI.uuid; continue }
        if name == "smartObject.stackMode",key == "mode" { properties[key] = ImageStackSettings.modeSchema;continue }
        if name == "raw.develop", key == "settings" { properties[key] = RawDevelopment.apiSchema; continue }
        if name == "document.hdrMerge",key == "settings" || key == "sources" {
          properties[key] = key == "settings" ? HDRMergeSettings.apiSchema:PhotomergeSettings.sourcesSchema;continue
        }
        if name == "document.photomerge",key == "settings" || key == "sources" {
          properties[key] = key == "settings" ? PhotomergeSettings.apiSchema:PhotomergeSettings.sourcesSchema;continue
        }
        if name == "photo.autoAlign" {
          properties[key] = key == "settings" ? PhotoAlignSettings.apiSchema : ["type":"array","minItems":2,"maxItems":PhotoAlign.maximumLayers,"uniqueItems":true,"items":["type":"string","format":"uuid"]]
          continue
        }
        if name == "photo.autoBlend" {
          properties[key] = key == "settings" ? PhotoBlendSettings.apiSchema : ["type":"array","minItems":2,"maxItems":PhotoBlend.maximumLayers,"uniqueItems":true,"items":["type":"string","format":"uuid"]]
          continue
        }
        if RegionRetouchAPI.commands.contains(name),let schema = RegionRetouchAPI.schema(key,command:name) { properties[key] = schema; continue }
        if ClipboardAPI.commands.contains(name) { properties[key] = ClipboardAPI.schema(key); continue }
        if SelectionGeometryAPI.commands.contains(name) { properties[key] = SelectionGeometryAPI.schema(key); continue }
        if GeometryAPI.commands.contains(name) { properties[key] = GeometryAPI.schema(key); continue }
        if name == "document.crop",let schema = CropRequest.apiSchema(key) { properties[key] = schema; continue }
        if name == "contentAware.scale",let schema = ContentAwareScaleRequest.apiSchema(key) { properties[key] = schema; continue }
        if name == "contentAware.fill" {
          if key == "settings" { properties[key] = ContentAwareSettings.apiSchema; continue }
          if key == "strokes" { properties[key] = ContentAwareSettings.strokeSchema; continue }
          if key == "output" { properties[key] = ["type":"string","enum":ContentAwareOutput.allCases.map(\.rawValue),"default":"new"]; continue }
          if key == "samplingChannelID" { properties[key] = ["type":"string","format":"uuid"]; continue }
        }
        if name == "channel.edit", let schema = ChannelAPI.parameterSchema(key) { properties[key] = schema; continue }
        if name == "channel.view" {properties[key] = ["overlay","visible"].contains(key) ? ["type":"boolean"]:key=="layerID" ? ["type":"string","format":"uuid"]:["type":"string","description":"RGB, quickMask, auxiliary UUID, layerMask or smartFilterMask"];continue}
        if name == "layer.transform", key != "layerID" {
          properties[key] = ["type": "number", "minimum": -1_000_000, "maximum": 1_000_000]
          continue
        }
        if name == "text.layout" {properties[key] = key=="settings" ? TextLayoutAPI.settings:key=="enabled" ? BrushAPI.flag:["type":"string","format":"uuid"];continue}
        switch key {
        case "settings": properties[key] = SelectionRefinement.apiSchema
        case "strokes": properties[key] = SelectionRefinement.strokeSchema
        case "output": properties[key] = ["type":"string","enum":SelectionRefinementOutput.allCases.map(\.rawValue),"default":"selection"]
        case "fromLayerMask": properties[key] = ["type":"boolean","default":false]
        case "adjustment": properties[key] = ["oneOf": [ClassicAdjustment.apiSchema, ColorLookupAdjustment.apiSchema, ModernAdjustment.apiSchema, SourceAdjustment.apiSchema] + (name == "adjustment.apply" ? [ClassicAdjustment.pixelInvertSchema] : [])]
        case "text": properties[key] = TextContent.apiTypeSchema
        case "stack": properties[key] = SmartFilterStack.apiSchema
        case "size": properties[key] = ["type": "number", "minimum": 0.5, "maximum": 2048]
        case "points": properties[key] = ["type": "array", "minItems": 1, "maxItems": 4096,
          "items": ["type": "object", "additionalProperties": false, "required": ["x", "y"], "properties": [
            "x": ["type": "number", "minimum": -1_000_000, "maximum": 1_000_000],
            "y": ["type": "number", "minimum": -1_000_000, "maximum": 1_000_000],
            "pressure": ["type": "number", "minimum": 0, "maximum": 1]]]]
        case "style": properties[key] = LayerStyle.apiSchema
        case "filter": properties[key] = RasterFilter.apiSchema
        case "options": properties[key] = DocumentEncodingOptions.schema
        case "operation":
          properties[key] = ["type": "string", "enum": ["down", "selected", "visible"]]
        case "mode": properties[key] = ["type": "string", "enum": ["replace", "add", "subtract", "intersect"]]
        case "layerIDs":
          properties[key] = [
            "type": "array", "minItems": ["layer.protection", "layer.style", "smartObject.convert"].contains(name) ? 1 : 0, "maxItems": LayerLimits.maximumLayers, "uniqueItems": true,
            "items": ["type": "string", "format": "uuid"],
          ]
        case "protection":
          properties[key] = ["type": "array", "minItems": 1, "maxItems": 6,
            "uniqueItems": true, "items": ["type": "string", "enum": AdobeLayerProtection.names]]
        case "layerID", "filterID", "operationID", "sourceDocumentID": properties[key] = ["type": "string", "format": "uuid"]
        case "sourceRevision": properties[key] = ["type": "string", "minLength": 1, "maxLength": 256]
        case "name": properties[key] = ["type": "string", "minLength": 1, "maxLength": 256]
        case "visible", "replace", "includeDescendants", "sampleAllLayers", "fit", "preserveSize", "allInstances": properties[key] = ["type": "boolean"]
        case "format":
          properties[key] = ["type": "string", "enum": DocumentIO.Format.allCases.map(\.rawValue)]
        case "channel":
          properties[key] = ["type": "string", "enum": RGBChannelPreview.allCases.map(\.title)]
        case "x", "y":
          properties[key] = [
            "type": "integer", "minimum": ["layer.move", "text.create"].contains(name) ? -1_000_000 : 0,
            "maximum": 1_000_000,
          ]
        case "width", "height":
          properties[key] = ["type": "integer", "minimum": 1, "maximum": 1_000_000]
        default: properties[key] = ["type": "number", "minimum": 0, "maximum": 1]
        }
      }
      return [
        "type": "object", "additionalProperties": false,
        "required": ["command", "revision", "parameters"],
        "properties": [
          "command": ["const": name], "revision": ["type": "string", "minLength": 1],
          "parameters": [
            "type": "object", "additionalProperties": false, "properties": properties,
            "required": parameters.keys.filter { !optionalParameters.contains($0) }.sorted(),
          ],
        ],
      ]
    }
  }
  static let definitions: [Definition] = LayerFilesAPI.definitions + ImageExportAPI.definitions + LayerCompsAPI.definitions + LinkedArtworkAPI.definitions + VariablesAPI.definitions + TimelineWorkspaceAPI.definitions + VideoRenderAPI.definitions + TimelineAudioAPI.definitions + [VideoKeyframeAPI.definition] + ImageSequenceAPI.definitions + VideoAPI.definitions + AnimationAPI.definitions + [
    .init(name:"image.applyImage",parameters:["source":"Source document/layer/channel","mask":"Optional independent mask source","target":"Optional destination, defaults to current editing target","blending":"Channel blend","opacity":"Percent0–100","scale":"Add/Subtract1–2","offset":"Add/Subtract−255–255","preserveTransparency":"Retain destination alpha"],description:"Blend a source into pixels or a channel through native Apply Image, with one Undo.",optionalParameters:["source","mask","target","blending","opacity","scale","offset","preserveTransparency"]),
    .init(name:"image.calculations",parameters:["source1":"Top source","source2":"Base source","mask":"Optional independent mask source","blending":"Channel blend","opacity":"Percent0–100","scale":"Add/Subtract1–2","offset":"Add/Subtract−255–255","result":"newChannel, selection or newDocument","name":"Optional result name"],description:"Combine two source channels into an alpha channel, selection or shared grayscale document.",optionalParameters:["source1","source2","mask","blending","opacity","scale","offset","result","name"]),
    .init(name:"render.flame",parameters:["settings":"Procedural settings","layerID":"Raster target or new-layer insertion parent","newLayer":"Render on a new raster layer","pathID":"Saved path for Flame"],description:"Render flame through the native raster engine in one undoable transaction.",optionalParameters:["settings","layerID","newLayer","pathID"]),
    .init(name:"render.tree",parameters:["settings":"Procedural settings","layerID":"Raster target or new-layer insertion parent","newLayer":"Render on a new raster layer"],description:"Render tree through the native raster engine in one undoable transaction.",optionalParameters:["settings","layerID","newLayer"]),
    .init(name:"render.pictureFrame",parameters:["settings":"Procedural settings","layerID":"Raster target or new-layer insertion parent","newLayer":"Render on a new raster layer"],description:"Render pictureFrame through the native raster engine in one undoable transaction.",optionalParameters:["settings","layerID","newLayer"]),
    .init(name: GradientFillAPI.command, parameters: ["layerID":"Existing Gradient Fill layer UUID", "fill":"Nonempty partial fill; omitted fields retain current values"], description: "Edit live Gradient Fill controls through the shared native transaction."),
    .init(name:"path.configure",parameters:["layerID":"Editable shape path target","tool":"Pen tool ID","tolerance":"Freeform/trace tolerance","combine":"Component operation","pathID":"Select saved path"],description:"Configure native Pen/Paths tools.",optionalParameters:["layerID","tool","tolerance","combine","pathID"]),
    .init(name:"path.draw",parameters:["points":"Document points","method":"freeform or curvature","closed":"Close contour","corners":"Curvature corner indices","tolerance":"Freeform fit tolerance","pathID":"Replace saved path","name":"Path name","workPath":"Work path flag"],description:"Fit Freeform or interpolate Curvature Pen geometry in one transaction.",optionalParameters:["method","closed","corners","tolerance","pathID","name","workPath"]),
    .init(name:"path.edit",parameters:["operation":"save, delete, selection or vectorMask","path":"Editable cubic geometry","pathID":"Saved path UUID","layerID":"Vector mask layer","name":"Path name","workPath":"Work path flag","selectionMode":"Selection combination","feather":"Selection feather","antiAlias":"Selection antialiasing"],description:"Edit retained paths or convert to selections/vector masks.",optionalParameters:["path","pathID","layerID","name","workPath","selectionMode","feather","antiAlias"]),
    .init(name:"path.trace",parameters:["tolerance":"Selection trace tolerance"],description:"Convert the current selection to an editable Work Path.",optionalParameters:["tolerance"]),
    .init(name:"path.paint",parameters:["pathID":"Saved path UUID","layerID":"Raster layer","brush":"Current brush overrides","stroke":"Stroke instead of foreground fill","simulatePressure":"Taper brush pressure"],description:"Fill or stroke a path using native raster painting with Undo.",optionalParameters:["pathID","layerID","brush","stroke","simulatePressure"]),
    .init(name:"shape.edit",parameters:["strokePreset":"Optional solid, dashed or dotted stroke preset","operation":"create, configure, append or path","path":"Document-space Bézier path","definition":"Live shape definition","component":"Parametric component to append","layerID":"Shape or raster target","name":"New shape/path name","mode":"shape, path or pixels","transform":"Logical origin transform"],description:"Create or edit live shapes, work paths or raster pixels in one native transaction.",optionalParameters:["strokePreset","definition","component","layerID","name","mode","transform","path"]),
    .init(name:"shape.configure",parameters:["strokePreset":"Optional solid, dashed or dotted stroke preset","definition":"Single primitive tool template","mode":"shape, path or pixels","combine":"null for new layer or path operation","presetID":"Custom shape preset"],description:"Configure native shape drawing tools without changing document history.",optionalParameters:["strokePreset","definition","mode","combine","presetID"]),
    .init(name:"shape.library",parameters:["operation":"list, define, import, export, rename or delete","name":"Preset name","presetID":"Shape preset UUID","data":"Base64 photatoshapes archive"],description:"Manage native custom shape presets. Define uses the selected path or shape layer.",optionalParameters:["name","presetID","data"]),
    .init(name: "frame.edit", parameters: ["operation":"Frame operation", "layerID":"Frame or shape/type UUID", "layerIDs":"Layers to frame", "name":"New frame name", "bounds":"Physical pixel bounds", "definition":"Frame shape and stroke", "transform":"Document-space affine delta", "contents":"Transform contents too", "fit":"fill, fit or original"], description: "Create, convert, configure, transform, fit or clear editable frames in one native transaction.", optionalParameters: ["layerID","layerIDs","name","bounds","definition","transform","contents","fit"]),
    .init(name: "frame.place", parameters: ["layerID":"Frame UUID", "sourceDocumentID":"Shared image source", "sourceRevision":"Expected source revision", "fit":"fill, fit or original"], description: "Replace frame contents with an embedded shared source snapshot and one Undo.", optionalParameters: ["fit"]),
    .init(name: "file.info", parameters: Dictionary(uniqueKeysWithValues: FileInformation.fields.map { ($0, "Optional descriptive metadata field") }), description: "Read or patch File Info using the native metadata/history engine.", optionalParameters: Set(FileInformation.fields)),
    .init(name:"guides.edit",parameters:["operation":"Guide operation","guides":"Document guide records","ids":"Selected guide UUIDs","layout":"Rows, columns, gutters and margins"],description:"Edit document guides in the shared native history transaction.",optionalParameters:["guides","ids","layout"]),
    .init(name:"guides.view",parameters:["visible":"Show canvas guides","locked":"Lock guide editing","snap":"Snap layers to guides","enabled":"Enable snapping"],description:"Configure the shared document guide view without modifying image pixels.",optionalParameters:["visible","locked","snap","enabled"]),
    .init(name: "artboard.edit", parameters: ["operation": "Artboard operation", "layerID": "Artboard/group UUID", "layerIDs": "Top-level children for creation", "name": "Artboard name", "bounds": "Logical document pixel rectangle", "background": "RGBA background", "guides": "Local guide offsets", "moveContents": "Move child contents"], description: "Create, convert, configure, duplicate or ungroup an artboard in one undoable transaction.", optionalParameters: ["layerID", "layerIDs", "name", "bounds", "background", "guides", "moveContents"]),
    .init(name: "artboard.export", parameters: ["layerIDs": "Artboards in output order", "format": "png, jpeg, tiff, photato or pdf"], description: "Download one artboard or a multipage PDF. Returns binary content; requires document transfers. Source document/history are preserved."),
    .init(name: "actions.batch", parameters: ["actionID": "Saved action UUID", "sources": "Shared ids and current revisions", "format": "Output format", "options": "Encoding options", "suffix": "Filename suffix", "stopOnError": "Stop on first failure", "clipboardPayloadBase64": "Optional initial clipboard for each source"], description: "Process independent source snapshots into numbered new files in the approved API save folder. Originals and existing outputs are preserved; per-file results and cancellation are observable.", optionalParameters: ["options", "suffix", "stopOnError", "clipboardPayloadBase64"]),
    .init(name: "actions.batch.cancel", parameters: ["operationID": "Current batch UUID"], description: "Cancel processing from a participating shared source; already published outputs remain."),
    .init(name:"selection.findPeople",parameters:["refresh":"Force local person inference","includeMasks":"Return raw UInt8 masks as base64","includeThumbnails":"Return bounded PNG person thumbnails","features":"Features for exported masks; defaults wholePerson"],description:"Detect individual people on device; return cache identity, IDs, bounds and optional masks/thumbnails without editing the document.",optionalParameters:["refresh","includeMasks","includeThumbnails","features"]),
    .init(name:"selection.hoverPerson",parameters:["cacheID":"Current person cache","instanceID":"Person to highlight; omit to clear","feature":"Feature to preview; defaults wholePerson"],description:"Preview an actual person or feature mask without modifying history.",optionalParameters:["instanceID","feature"]),
    .init(name:"selection.selectPeople",parameters:["cacheID":"Current person cache","instanceIDs":"One or more person IDs","features":"Feature union; defaults wholePerson","mode":"Selection combination mode","hardEdge":"Threshold soft coverage"],description:"Select whole people or available semantic features through native history and Actions.",optionalParameters:["mode","hardEdge","features"]),
    .init(name:"selection.findObjects",parameters:["refresh":"Force new local inference","includeMasks":"Return raw UInt8 masks as base64"],description:"Detect and cache separate objects in the active sampling source. Does not change document/history. Returns cacheID, object IDs/bounds and optional masks.",optionalParameters:["refresh","includeMasks"]),
    .init(name:"selection.hoverObject",parameters:["cacheID":"Current object cache UUID","instanceID":"Object to highlight; omit to clear"],description:"Set the same temporary object highlight used by canvas hover; no history or document edit.",optionalParameters:["instanceID"]),
    .init(name:"selection.selectFoundObject",parameters:["cacheID":"Current object cache UUID","instanceID":"Detected object ID","mode":"replace/add/subtract/intersect","hardEdge":"Binary selection edges"],description:"Select a cached object with native history/Actions; rejects stale caches.",optionalParameters:["mode","hardEdge"]),
    .init(name:"selection.configure",parameters:["objectFinderEnabled":"Enable native hover detection","hardEdge":"Binary object selection edges","finderOverlayColor":"RGBA object highlight","mode":"Selection mode","objectMode":"Rectangle, Lasso or Object Click","sampleAllLayers":"Sample composite","enhanceEdge":"Refine selection edges","overlayColor":"RGBA overlay color","brush":"Partial brush settings"],description:"Configure native selection tool settings without changing document pixels.",optionalParameters:["objectFinderEnabled","hardEdge","finderOverlayColor","mode","objectMode","sampleAllLayers","enhanceEdge","overlayColor","brush"]),
    .init(name:"selection.quick",parameters:["points":"Stroke samples","brush":"Partial brush settings","mode":"Selection combination mode","layerID":"Sampling layer UUID","sampleAllLayers":"Sample visible composite","enhanceEdge":"Refine edges"],description:"Grow an image-aware native selection from a stroke using graph cut, in one Undo.",optionalParameters:["brush","mode","layerID","sampleAllLayers","enhanceEdge"]),
    .init(name:"selection.object",parameters:["hardEdge":"Binary object edges","region":"One point, rectangle or polygon","mode":"Selection combination mode","layerID":"Sampling layer UUID","sampleAllLayers":"Sample visible composite","enhanceEdge":"Refine edges"],description:"Select an object with native region graph cut or on-device point instance detection.",optionalParameters:["hardEdge","mode","layerID","sampleAllLayers","enhanceEdge"]),
    .init(name:"selection.brush",parameters:["points":"Stroke samples","brush":"Partial brush settings","mode":"Selection combination mode"],description:"Paint soft selection coverage using the shared native brush and history.",optionalParameters:["brush","mode"]),
    .init(name:"adjustmentBrush.configure",parameters:["kind":"Default adjustment type","subtract":"Subtract coverage","newLayer":"Next stroke starts new adjustment","applyToObject":"Object click mode","overlay":"Show mask overlay","brush":"Partial brush settings"],description:"Configure native Adjustment Brush session state.",optionalParameters:["kind","subtract","newLayer","applyToObject","overlay","brush"]),
    .init(name:"adjustmentBrush.stroke",parameters:["points":"Brush samples","kind":"Adjustment type","settings":"Partial typed adjustment values","brush":"Partial brush settings","layerID":"Existing masked adjustment UUID","newLayer":"Create a new adjustment","newLayerID":"Optional new UUID","subtract":"Subtract from mask"],description:"Paint an editable local adjustment in one transaction.",optionalParameters:["kind","settings","brush","layerID","newLayer","newLayerID","subtract"]),
    .init(name:"adjustmentBrush.object",parameters:["x":"Document x","y":"Document y","kind":"Adjustment type","settings":"Partial typed adjustment values","brush":"Brush settings","layerID":"Existing masked adjustment UUID","newLayer":"Create a new adjustment","newLayerID":"Optional new UUID","subtract":"Subtract object coverage"],description:"Apply a local adjustment to the on-device foreground instance at a point.",optionalParameters:["kind","settings","brush","layerID","newLayer","newLayerID","subtract"]),
    .init(name:"adjustmentBrush.edit",parameters:["operation":"new, replace, invert or mask","layerID":"Masked adjustment UUID","kind":"Replacement type","settings":"Replacement settings","density":"Mask density0...1","feather":"Mask feather0...100"],description:"Start a new adjustment or replace/invert an existing local adjustment.",optionalParameters:["layerID","kind","settings","density","feather"]),
    .init(name:"paint.configure",parameters:["tool":"Painting tool","options":"Partial tool options"],description:"Configure painting tools without changing pixels."),
    .init(name:"paint.tool",parameters:["tool":"Painting tool","points":"Stroke samples or Magic Eraser click","brush":"Partial brush override","presetID":"Optional brush preset UUID","options":"Partial tool options","patternID":"Pattern resource ID","target":"pixels, layerMask, smartFilterMask, alpha or quickMask","layerID":"Layer UUID","channelID":"Alpha UUID"],description:"Paint using Pencil, Mixer Brush, Color Replacement, Pattern Stamp or color-aware erasers with shared native preview/history.",optionalParameters:["brush","presetID","options","patternID","target","layerID","channelID"]),
    .init(name:"paint.mixer",parameters:["operation":"load, clean or sample","color":"Loaded color","x":"Sample x","y":"Sample y","size":"Sample diameter","layerID":"Source layer UUID","allLayers":"Sample composite","solid":"Load solid color only"],description:"Manage persistent Mixer Brush paint; changes tool state without document history.",optionalParameters:["color","x","y","size","layerID","allLayers","solid"]),
    .init(name:"brush.configure",parameters:["brush":"Partial brush/tool settings"],description:"Patch the active brush settings and foreground/background color context without changing document pixels."),
    .init(name:"brush.presets",parameters:["operation":"Preset operation","presetID":"Preset UUID","name":"Preset name","group":"Group name","includeSize":"Capture diameter","includeToolSettings":"Capture tool options","includeColor":"Capture colors","index":"Destination index","data":"Base64 brush file","format":"photatobrushes or abr"],description:"Manage reusable native brush presets and supported ABR files.",optionalParameters:["presetID","name","group","includeSize","includeToolSettings","includeColor","index","data","format"]),
    .init(name:"paint.stroke",parameters:["points":"Tablet/time stroke samples","brush":"Partial override of current brush","presetID":"Optional preset","target":"pixels, layerMask, smartFilterMask, alpha or quickMask","layerID":"Layer UUID","channelID":"Alpha UUID"],description:"Apply one undoable native brush stroke with deterministic settings. A pixel target respects the selected RGB8/native components when present.",optionalParameters:["brush","presetID","target","layerID","channelID"]),
    .init(name: "actions.manage", parameters: ["operation": "Library/recorder operation including duplicate", "actionID": "Saved source action UUID", "stepID": "Step UUID", "name": "Action name; optional copy override", "set": "Action set; optional copy override", "enabled": "Enable step", "index": "Destination step index", "data": "Base64 version 1–\(ActionLibraryFile.maximumVersion) action library"], description: "List, record, stop, cancel, rename, duplicate, delete, import/export and edit native action steps. Duplicate copies one saved action with fresh action/step IDs and no document edit. Uses the shared local action library; no filesystem paths accepted.", optionalParameters: ["actionID", "stepID", "name", "set", "enabled", "index", "data"]),
    .init(name: "actions.play", parameters: ["actionID": "Saved action UUID", "clipboardPayloadBase64": "Optional initial native clipboard image", "sources": "Additional shared master-palette or retouch sources with revisions"], description: "Play a native action as one transaction. Uses a private clipboard; Copy/Cut output is returned after successful playback. Never accesses the Mac clipboard.", optionalParameters: ["clipboardPayloadBase64", "sources"]),
    .init(name:"document.photomerge.cancel",parameters:["operationID":"Current panorama operation UUID"],description:"Cancel an active panorama creation operation from a participating shared source."),
    .init(name:"document.photomerge",parameters:["sources":"Shared source document IDs and current revisions","settings":"Optional Photomerge settings","name":"Optional new document name"],description:"Create a new shared panorama from multiple shared photographs; preserve all source documents.",optionalParameters:["settings","name"]),
    .init(name:"document.imageProcessor",parameters:["sources":"Shared source UUIDs/revisions","settings":"Optional Image Processor settings"],description:"Export selected shared images to JPEG/PSD/TIFF folders in a ZIP through the native engine.",optionalParameters:["settings"]),
    .init(name:"document.imageProcessor.cancel",parameters:["operationID":"Current Image Processor UUID"],description:"Cancel Image Processor from a participating shared source."),
    .init(name:"document.cropStraighten",parameters:["layerID":"Optional source layer UUID","forceSingle":"Keep disconnected pieces together"],description:"Extract scanned photos into separate shared documents, preserving the source.",optionalParameters:["layerID","forceSingle"]),
    .init(name:"document.cropStraighten.detect",parameters:["layerID":"Optional source layer UUID","forceSingle":"Keep disconnected pieces together"],description:"Preview detected photo rectangles without creating documents.",optionalParameters:["layerID","forceSingle"]),
    .init(name:"document.cropStraighten.cancel",parameters:["operationID":"Current extraction UUID"],description:"Cancel detection or extraction from its shared source."),
    .init(name:"document.contactSheet",parameters:["sources":"Shared source UUIDs/current revisions","settings":"Optional page/layout/caption/profile settings","name":"Optional page name prefix"],description:"Create and share all Contact Sheet II pages atomically, preserving sources.",optionalParameters:["settings","name"]),
    .init(name:"document.contactSheet.cancel",parameters:["operationID":"Current contact-sheet operation UUID"],description:"Cancel an active Contact Sheet II operation from a participating source."),
    .init(name:"document.imageStack.cancel",parameters:["operationID":"Current stack creation UUID"],description:"Cancel stack creation from a participating shared source."),
    .init(name:"document.imageStack",parameters:["sources":"Shared source IDs/revisions","settings":"Optional alignment, Smart Object and statistical mode","name":"Optional name"],description:"Create a shared editable image stack from multiple shared documents.",optionalParameters:["settings","name"]),
    .init(name: SmartObjectLayerCompAPI.name, parameters: ["layerID": "Smart Object layer UUID", "compID": "Source Layer Comp UUID or null for Last Document State"], description: "Choose one placed source variation without changing source bytes, shared identity, transforms, masks or effects. One Undo transaction."),
    .init(name:"smartObject.stackMode",parameters:["layerID":"Smart Object UUID","mode":"Statistical mode or none"],description:"Change one Smart Object instance stack mode; retain its sources, filters and transforms."),
    .init(name:"document.hdrMerge.cancel",parameters:["operationID":"Current HDR image operation UUID"],description:"Cancel an active HDR image creation operation from a participating shared source."),
    .init(name:"document.hdrMerge",parameters:["sources":"Shared source document IDs and current revisions","settings":"Optional HDR merge settings","name":"Optional new document name"],description:"Create a new shared HDR image from multiple shared photographs; preserve all source documents.",optionalParameters:["settings","name"]),
    .init(name:"filter.vanishingPoint",parameters:["layerID":"Target raster layer UUID","settings":"Perspective plane definitions; omitted uses saved planes","operations":"Perspective paste/clone/brush operations","newLayer":"Apply pixels on a new layer"],description:"Define reusable perspective planes and apply perspective-aware edits in one native transaction.",optionalParameters:["settings","operations","newLayer"]),
    .init(name:"layer.warp",parameters:["layerID":"Pixel layer or Smart Object UUID","settings":"Warp preset or custom mesh"],description:"Warp a pixel layer or retain editable source-space Warp on a Smart Object, in one undoable transaction."),
    .init(name:"photo.autoAlign",parameters:["layerIDs":"Two to sixteen unique pixel-layer UUIDs","settings":"Optional projection, reference and focal length"],description:"Register overlapping layers by image content and warp their pixels and masks in one undoable transaction.",optionalParameters:["settings"]),
    .init(name:"photo.autoBlend",parameters:["layerIDs":"Two to sixteen unique pixel-layer UUIDs","settings":"Optional Auto-Blend settings"],description:"Blend aligned layers as a panorama or focus stack with editable masks, optional multiband result and transparent-area fill.",optionalParameters:["settings"]),
    .init(name:"retouch.stroke",parameters:["tool":"One of nine native retouch tools","points":"Document-space stroke samples","layerID":"Target layer UUID","target":"pixels or layerMask","brush":"Partial native retouch brush settings","mapping":"Clone/Healing source and optional anchor/transform","source":"Optional explicit shared source id/revision","sourceLayerID":"Source layer UUID","sampling":"Current Layer, Current & Below or All Layers","ignoreAdjustments":"Ignore adjustment layers when sampling","toning":"Dodge/Burn/Sponge settings","focus":"Blur/Sharpen/Smudge settings","foreground":"Smudge finger-paint colour","spotType":"Spot Healing algorithm"],description:"Apply one native retouch stroke, including semantic Actions and atomic history.",optionalParameters:["layerID","target","brush","mapping","source","sourceLayerID","sampling","ignoreAdjustments","toning","focus","foreground","spotType"]),
    .init(name:"retouch.patch",parameters:["layerID":"Raster layer UUID","dx":"Integer horizontal drag offset","dy":"Integer vertical drag offset","mode":"source or destination","type":"normal or contentAware","diffusion":"Normal blending 1–7","transparent":"Respect sampled transparency","structure":"Structure retention 1–7","color":"Color adaptation 0–10","sampleAllLayers":"Sample visible composite","seed":"Deterministic variation"],description:"Repair a selected area using a dragged source or destination through native Patch and history.",optionalParameters:["mode","type","diffusion","transparent","structure","color","sampleAllLayers","seed"]),
    .init(name:"retouch.move",parameters:["layerID":"Raster layer UUID","dx":"Horizontal center offset","dy":"Vertical center offset","mode":"move or extend","scaleX":"Horizontal percentage","scaleY":"Vertical percentage","angle":"Clockwise degrees","structure":"Structure retention 1–7","color":"Color adaptation 0–10","sampleAllLayers":"Sample visible composite","seed":"Deterministic fill variation"],description:"Move/extend selected pixels, adapt the destination and fill the original hole in Move mode.",optionalParameters:["mode","scaleX","scaleY","angle","structure","color","sampleAllLayers","seed"]),
    .init(name:"retouch.redEye",parameters:["layerID":"Raster layer UUID","x":"Search left","y":"Search top","width":"Search width","height":"Search height","pupilSize":"Pupil extent percentage","darken":"Correction darkness percentage"],description:"Correct red pupils within a bounded region while preserving neutral highlights and selection coverage.",optionalParameters:["pupilSize","darken"]),
    .init(name: "clipboard.copy", parameters: ["layerIDs": "Optional copied layer IDs", "merged": "Copy visible merged pixels"], description: "Return an explicit native clipboard payload without changing the system clipboard or history.", optionalParameters: ["layerIDs", "merged"]),
    .init(name: "clipboard.cut", parameters: ["layerIDs": "Optional cut layer IDs", "backgroundColor": "Opaque RGB fill for flat modes without transparency"], description: "Return native clipboard data and apply one undoable Cut. Never writes the system clipboard.", optionalParameters: ["layerIDs", "backgroundColor"]),
    .init(name: "clipboard.paste", parameters: ["payloadBase64": "Native clipboard bytes", "placement": "Paste placement", "center": "Optional document-pixel center", "colorDecision": "convertAppearance or preserveNumbers"], description: "Paste an explicit payload through the shared native mode/profile/history path.", optionalParameters: ["placement", "center", "colorDecision"]),
    .init(name:"document.trim",parameters:["basis":"transparent,topLeft,bottomRight", "top":"Trim top", "left":"Trim left", "bottom":"Trim bottom", "right":"Trim right"],description:"Trim document edges through shared native compositor/geometry and one Undo.",optionalParameters:["basis","top","left","bottom","right"]),
    .init(name:"document.revealAll",parameters:["backgroundColor":"Optional opaque Background extension RGB"],description:"Expand canvas to retained layer content without resampling the layer pixels.",optionalParameters:["backgroundColor"]),
    .init(name:"document.duplicate",parameters:["name":"Optional copy name", "merged":"Duplicate merged visible layers only"],description:"Create an independent new shared document; requires document transfers. Source history is unchanged.",optionalParameters:["name","merged"]),
    .init(name: "clipboard.newDocument", parameters: ["payloadBase64": "Native clipboard bytes", "name": "Optional new document name"], description: "Create a new shared document from a native clipboard payload; requires document transfers.", optionalParameters: ["name"]),
    .init(name: "document.resize", parameters: ["width": "Pixel width", "height": "Pixel height", "resolution": "Pixels per inch", "method": "Resampling method"], description: "Resize the document through native Image Size and history.", optionalParameters: ["resolution", "method"]),
    .init(name:"document.fitImage",parameters:["width":"Maximum pixel width", "height":"Maximum pixel height", "dontEnlarge":"Keep images already inside the bounds at their current size", "method":"Resampling method"],description:"Fit the whole document proportionally inside a reusable pixel bounding box, preserving PPI, through native history and Actions.",optionalParameters:["dontEnlarge","method"]),
    .init(name: "document.canvasSize", parameters: ["width": "Pixel width", "height": "Pixel height", "anchor": "Position of original canvas", "fill": "Optional RGBA extension color"], description: "Change canvas extent while retaining document mode and history.", optionalParameters: ["anchor", "fill"]),
    .init(name: "document.rotate", parameters: ["turn": "Quarter turn, half turn or canvas flip"], description: "Rotate or flip the entire canvas with one Undo."),
    .init(name: "document.resolution", parameters: ["resolution": "Pixels per inch"], description: "Change print resolution without resampling pixels."),
    .init(name:"document.crop",parameters:["x":"Crop document x","y":"Crop document y","width":"Output width","height":"Output height","angle":"Clockwise crop frame angle","deleteCroppedPixels":"Trim ordinary raster storage","fill":"transparent, background or contentAware","backgroundColor":"Three RGB values","seed":"Deterministic fill variation"],description:"Crop/expand/straighten the document and optionally fill exposed edges through the native preview/history pipeline.",optionalParameters:["angle","deleteCroppedPixels","fill","backgroundColor","seed"]),
    .init(name:"contentAware.scale",parameters:["layerID":"Ordinary raster layer UUID","width":"Output width in pixels","height":"Output height in pixels","x":"Output document x","y":"Output document y","amount":"Content-aware percentage","protectChannelID":"Saved alpha channel UUID","protectSkinTones":"Protect skin-tone regions"],description:"Scale the layer or selected pixels using native seam carving with preview-equivalent output and one undo transaction.",optionalParameters:["x","y","amount","protectChannelID","protectSkinTones"]),
    .init(name:"contentAware.fill",parameters:["layerID":"Raster layer UUID","settings":"Fill settings","output":"current, new or duplicate","strokes":"Sampling and selection edits","samplingChannelID":"Saved alpha sampling source"],description:"Fill the selected area through the native Content-Aware Fill engine, one prepared undo transaction.",optionalParameters:["settings","output","strokes","samplingChannelID"]),
    .init(name:"channel.edit",parameters:ChannelAPI.fields,description:"Manage alpha channels, save/load selections, edit Quick Mask, paint and filter through native history. Action-specific parameters are strict.",optionalParameters:Set(ChannelAPI.fields.keys).subtracting(["action"])),
    .init(name:"channel.view",parameters:["target":"RGB, quickMask, auxiliary UUID, layerMask or smartFilterMask","layerID":"Mask owner UUID; required only for layerMask/smartFilterMask","overlay":"View alpha/spot over image","visible":"Independent eye for RGB, Quick Mask, auxiliary UUID or active layerMask/smartFilterMask with layerID; retains editing target, pixels and history"],description:"Select the shared desktop channel/mask target and colour context; supplying visible changes only its image/auxiliary eye. Multiple saved masks can remain visible independently.",optionalParameters:["layerID","overlay","visible"]),
    .init(name:"layer.background",parameters:["layerID":"Layer UUID","operation":"toLayer or fromLayer","name":"Converted regular layer name","mode":"Converted regular blend mode","opacity":"Converted opacity0–1","color":"Layer color label","backgroundColor":"Opaque RGBA canvas/transparency fill"],description:"Convert explicit Background identity through the native engine and one Undo transaction.",optionalParameters:["name","mode","opacity","color","backgroundColor"]),
    .init(name:"pixels.clear",parameters:["layerID":"Raster layer UUID","backgroundColor":"Opaque RGBA fill for Background"],description:"Clear selected pixels; Background uses its background color and remains opaque.",optionalParameters:["backgroundColor"]),
    .init(name:"pixels.fill",parameters:["layerID":"Raster layer or mask owner UUID","mask":"Edit its pixel mask","target":"Auxiliary channel UUID or quickMask instead of layerID","color":"RGBA0–1 instead of patternID","patternID":"Saved document/native-library pattern ID instead of color","placement":"Optional native pattern scale/angle/phase override","opacity":"Paint opacity0–1","mode":"Paint blend mode","preserveTransparency":"Retain raster alpha"],description:"Fill current selection or canvas with color or a saved pattern using the shared native paint engine and one Undo.",optionalParameters:["layerID","mask","target","color","patternID","placement","opacity","mode","preserveTransparency"]),
    .init(name:"pixels.stroke",parameters:["layerID":"Raster layer or mask owner UUID","mask":"Edit its pixel mask","target":"Auxiliary channel UUID or quickMask instead of layerID","color":"RGBA0–1","opacity":"Paint opacity0–1","mode":"Paint blend mode","preserveTransparency":"Retain raster alpha","width":"Integer Stroke width1–250","location":"Inside, Center or Outside"],description:"Outline selection or raster transparency using the shared native Stroke engine and one Undo.",optionalParameters:["layerID","mask","target","opacity","mode","preserveTransparency","location"]),
    .init(name:"layer.links",parameters:["operation":"link, unlink, enable, disable, select","layerIDs":"Distinct layer/group UUIDs"],description:"Edit persistent relationships with one Undo, or select related layers without changing history."),
    .init(name:"layers.move",parameters:["layerIDs":"Whole layer/group UUIDs","dx":"Integer displacement x","dy":"Integer displacement y","copy":"Duplicate selected subtrees before moving"],description:"Translate whole selected and enabled linked subtrees once, retaining original samples and metadata with one Undo.",optionalParameters:["copy"]),
    .init(name:"layers.transform",parameters:["layerIDs":"Whole layer/group UUIDs","matrix":"Nine row-major affine/projective document-coordinate coefficients","interpolation":"Nearest Neighbor/Bilinear/Bicubic"],description:"Transform editable selected layer subtrees once around shared geometry with one Undo.",optionalParameters:["interpolation"]),
    .init(name:"channel.transform",parameters:["target":"Current alpha/spot UUID or quickMask","matrix":"Nine row-major document-coordinate coefficients","interpolation":"Nearest Neighbor/Bilinear/Bicubic","backgroundValue":"Editing gray for exterior and cut holes,0to1","copy":"Duplicate over unchanged source"],description:"Transform whole or selected auxiliary-channel coverage, preserving other planes, channel identity and one Undo.",optionalParameters:["interpolation","backgroundValue","copy"]),
    .init(name:"mask.transform",parameters:["layerID":"Selected unlinked pixel-mask layer UUID","matrix":"Nine row-major document-coordinate coefficients","interpolation":"Nearest Neighbor/Bilinear/Bicubic"],description:"Transform one whole unlinked pixel mask while preserving layer content and mask properties.",optionalParameters:["interpolation"]),
    .init(name:"pixels.move",parameters:["layerID":"Editable RGB raster/Background UUID","dx":"Document pixel displacement x","dy":"Document pixel displacement y","copy":"Copy selected pixels","constrain":"Round direction to45degrees","backgroundColor":"Opaque RGBA Background fill"],description:"Move/copy selected pixels through the shared native preview/history engine and one Move Undo.",optionalParameters:["copy","constrain","backgroundColor"]),
    .init(name:"pixels.transform",parameters:["layerID":"RGB raster or Background layer UUID","matrix":"Document-space homogeneous3x3 matrix","interpolation":"Nearest Neighbor, Bilinear or Bicubic","backgroundColor":"Optional opaque RGBA fill for Background holes","copy":"Copy selected content over its unchanged source"],description:"Transform selected pixels and selection through the native engine; ordinary off-canvas storage is retained and Background stays opaque/full-canvas.",optionalParameters:["interpolation","backgroundColor","copy"]),
    .init(name:"selection.transform",parameters:["matrix":"Document-space homogeneous3×3 matrix","interpolation":"Nearest Neighbor, Bilinear or Bicubic"],description:"Transform selection coverage without changing image pixels, using native tiled resampling/history/Actions.",optionalParameters:["interpolation"]),
    .init(name:"selection.modify",parameters:["operation":"border, smooth, expand or contract","amount":"Pixel amount","atCanvasBounds":"Apply against zero coverage beyond canvas"],description:"Refine document selection through native tiled coverage and one named history transaction.",optionalParameters:["atCanvasBounds"]),
    .init(name:"selection.reselect",parameters:[:],description:"Restore the most recently deselected selection in this document through native history."),
    .init(name:"selection.magnetic.configure",parameters:["settings":"Partial Magnetic Lasso controls"],description:"Configure native Magnetic Lasso tool options without changing document/history."),
    .init(name:"selection.magneticLasso",parameters:["settings":"Optional Magnetic Lasso controls","events":"Ordered pointer/fastening/freehand/straight/removal/width events","mode":"Selection combination","straightClose":"Close with a straight segment"],description:"Trace image edges through the native Magnetic Lasso engine, preserving one Undo and explicit coverage Actions.",optionalParameters:["settings","mode","straightClose"]),
    .init(name:"selection.colorRange",parameters:["settings":"Partial native Color Range settings","presetBase64":"Version1 Photato preset JSON"],description:"Select sampled colors, hue presets or tonal ranges from the visible composite, constrained by an existing selection, with one native Undo. Settings and presetBase64 are mutually exclusive.",optionalParameters:["settings","presetBase64"]),
    .init(name:"selection.focus",parameters:["layerID":"Ordinary raster layer UUID","settings":"Focus range/noise/Auto/soft-edge controls","output":"Selection, mask, layer or document output","strokes":"Add/Subtract correction brushes","sampleAllLayers":"Sample composite colors"],description:"Select in-focus image areas through native analysis and shared history/output paths. New-document output requires transfers and returns201.",optionalParameters:["settings","output","strokes","sampleAllLayers"]),
    .init(name:"selection.refine",parameters:["layerID":"Ordinary raster layer UUID","settings":"Refinement settings","output":"Output mode","strokes":"Brush/lasso edits","fromLayerMask":"Use existing layer mask","sampleAllLayers":"Sample composite colors"],description:"Select and Mask through the shared native matting engine. New-document outputs return201 and require document transfers.",optionalParameters:["settings","output","strokes","fromLayerMask","sampleAllLayers"]),
    .init(name: "adjustment.create", parameters: ["adjustment": "Classic, Color Lookup or modern adjustment", "name": "Optional layer name"], description: "Create an editable adjustment layer with selection-derived mask and Undo.", optionalParameters: ["name"]),
    .init(name: "adjustment.set", parameters: ["layerID": "Adjustment layer UUID", "adjustment": "Complete settings of the existing kind"], description: "Replace editable adjustment settings, retaining masks and layer properties."),
    .init(name: "document.convertDuotone", parameters: ["settings": "Named inks, curves and preview overprints", "mergeVisible": "Consent to flatten the visible stack"], description: "Convert Grayscale8 to Duotone, or edit existing ink options with one Undo.", optionalParameters: ["settings", "mergeVisible"]),
    .init(name: "document.convertMultichannel", parameters: ["mergeVisible": "Consent to flatten the visible stack", "plateIDs": "Optional identities for resulting channels"], description: "Convert component8/16 or Duotone to independent ink plates with one Undo.", optionalParameters: ["mergeVisible", "plateIDs"]),
    .init(name: "print.configure", parameters: ["settings": "Print output settings"], description: "Configure physical page layout and print color without changing document history."),
    .init(name: "print.settings.read", parameters: [:], description: "Read committed print settings and last job state."),
    .init(name: "print.present", parameters: [:], description: "Open native print controls; requires Allow printing."),
    .init(name: "print.submit", parameters: [:], description: "Prepare and submit a native printer job using committed settings; requires Allow printing."),
    .init(name: "print.cancel", parameters: ["operationID": "Owned print operation UUID"], description: "Cancel this API session's print preparation before submission."),
    .init(name: "proof.configure", parameters: ["settings": "Proof display settings"], description: "Configure proof colors and gamut warnings without modifying document pixels or history."),
    .init(name: "proof.settings.read", parameters: [:], description: "Read committed proof settings, including a custom ICC profile."),
    .init(name: "ink.settings.read", parameters: [:], description: "Read retained ink settings and plate metadata without a history change."),
    .init(name: "ink.channel.read", parameters: ["target": "Ink channel", "offset": "First sample", "count": "Sample count up to4096"], description: "Read raw gray/density without modifying history.", optionalParameters: ["offset", "count"]),
    .init(name: "ink.channel.write", parameters: ["target": "Ink channel", "offset": "First sample", "values": "Raw gray/density in0...1"], description: "Write numeric ink samples with one Undo.", optionalParameters: ["offset"]),
    .init(name: "ink.channel.edit", parameters: ["targets": "Ink channels", "action": "fill,stroke,invert,filter,selection", "value": "Gray value", "opacity": "Opacity", "brush": "Brush settings", "points": "Stroke samples", "filter": "Native filter", "mode": "Selection combination", "invert": "Invert loaded selection"], description: "Selection-aware ink editing or channel-to-selection loading.", optionalParameters: ["value", "opacity", "brush", "points", "filter", "mode", "invert"]),
    .init(name: "ink.channel.manage", parameters: ["action": "create,delete,duplicate,move,options", "plateID": "Existing plate UUID", "newID": "Created plate UUID", "name": "Plate name", "color": "Preview ink color", "solidity": "Preview solidity", "density": "Initial raw density", "index": "Destination index"], description: "Manage independent Multichannel plates with native history.", optionalParameters: ["plateID", "newID", "name", "color", "solidity", "density", "index"]),
    .init(name: "ink.channel.select", parameters: ["targets": "Ink channel targets; empty selects all"], description: "Change desktop editing targets without changing pixels."),
    .init(name: "ink.channel.visibility", parameters: ["targets": "Nonempty visible ink channels"], description: "Change ink channel preview without changing pixels."),
    .init(name: "document.convertIndexed", parameters: ["settings": "Indexed Color options", "mergeVisible": "Explicitly flatten the stack", "sources": "Additional shared master palette sources with revisions", "previousPalette": "Explicit palette for Previous"], description: "Convert RGB/Grayscale8 to actual indexed storage with one Undo.", optionalParameters: ["settings", "mergeVisible", "sources", "previousPalette"]),
    .init(name: "document.convertBitmap", parameters: ["settings": "Bitmap options", "mergeVisible": "Explicitly flatten the stack"], description: "Convert Grayscale8 to packed one-bit storage with one Undo.", optionalParameters: ["settings", "mergeVisible"]),
    .init(name: "indexed.colorTable.read", parameters: [:], description: "Read palette, transparency and ACT bytes without modifying history."),
    .init(name: "indexed.colorTable.write", parameters: ["colors": "RGB entries", "actBase64": "ACT file bytes", "transparentIndex": "Transparent index, or -1 for none"], description: "Replace the color table while preserving every pixel index.", optionalParameters: ["colors", "actBase64", "transparentIndex"]),
    .init(name: "indexed.indices.read", parameters: ["offset": "Row-major pixel offset", "count": "Up to 4096 indices"], description: "Read actual pixel indices.", optionalParameters: ["offset", "count"]),
    .init(name: "indexed.indices.write", parameters: ["offset": "Row-major pixel offset", "values": "Palette entry indices"], description: "Write actual pixel indices with one Undo; ignores selection.", optionalParameters: ["offset"]),
    .init(name: "document.assignProfile", parameters: ["profileBase64": "Matching ICC profile", "removeProfile": "Remove ICC tagging and use platform working interpretation"], description: "Assign profile without changing numerical samples; undoable.", optionalParameters: ["profileBase64", "removeProfile"]),
    .init(name: "document.convertProfile", parameters: ["profileBase64": "Destination ICC profile", "intent": "Rendering intent", "blackPointCompensation": "Use black point compensation", "mergeVisible": "Flatten image before conversion"], description: "Convert document colors through Apple ColorSync; undoable.", optionalParameters: ["intent", "blackPointCompensation", "mergeVisible"]),
    .init(name: "document.profile.read", parameters: [:], description: "Read effective ICC data and tagging state."),
    .init(name: "document.convertMode", parameters: ["mode": "Color mode", "depth": "8, 16 or 32", "profileBase64": "Optional destination ICC profile", "intent": "Color conversion intent", "mergeVisible": "Replace visible stack with its composite", "clipHDR": "Allow HDR clipping on precision reduction"], description: "Convert native document components with shared preview/history semantics.", optionalParameters: ["profileBase64", "intent", "mergeVisible", "clipHDR"]),
    .init(name: "mode.channel.read", parameters: ["layerID": "Raster layer UUID", "component": "Color component index", "offset": "First layer-local sample", "count": "Number of samples, up to 4096"], description: "Read numerical native component samples without changing history.", optionalParameters: ["offset", "count"]),
    .init(name: "mode.channel.write", parameters: ["layerID": "Unlocked raster layer UUID", "component": "Color component index", "offset": "First layer-local sample", "values": "Component samples"], description: "Replace a bounded range of one color plane; preserves other planes and alpha with one Undo.", optionalParameters: ["offset"]),
    .init(name: "mode.channel.select", parameters: ["components": "Editing component indices; empty means composite; ordinary RGB8 all three also means composite"], description: "Select ordinary RGB8 or retained color components in the desktop Channels panel without pixel/history changes."),
    .init(name: "mode.channel.visibility", parameters: ["components": "Visible component indices"], description: "Set independent color component visibility without changing stored pixels."),
    .init(name: "mode.channel.edit", parameters: ["layerID": "Raster layer UUID", "components": "Component indices", "action": "fill, stroke, invert or filter", "value": "Gray fill value", "opacity": "Fill opacity", "brush": "Brush settings", "points": "Document-coordinate stroke samples", "filter": "Native raster filter"], description: "Edit retained components with selection, alpha preservation and one Undo.", optionalParameters: ["value", "opacity", "brush", "points", "filter"]),
    .init(name:"tone.apply",parameters:["kind":"Adjustment kind","settings":"Tone/color settings","layerID":"Pixel layer UUID"],description:"Apply native tone/color adjustment with shared preview and Undo semantics.",optionalParameters:["settings","layerID"]),
    .init(name:"tone.statistics",parameters:["layerID":"Source layer UUID; omit for merged","useSelection":"Calculate from selection"],description:"Read portable Match Color Lab statistics from this shared document.",optionalParameters:["layerID","useSelection"]),
    .init(name: "adjustment.apply", parameters: ["layerID": "Pixel layer UUID", "adjustment": "Classic, Color Lookup or modern adjustment"], description: "Apply to selected pixels with shared native Undo; composite RGB target only."),
    .init(name:"font.inspect",parameters:["font":"Installed PostScript font name","start":"First glyph ID","count":"Glyph page size"],description:"Inspect installed OpenType features, variable axes and glyphs.",optionalParameters:["start","count"]),
    .init(name:"text.find",parameters:["find":"Literal text","layerID":"Single layer UUID; omitted searches all eligible type layers","caseSensitive":"Exact case","wholeWord":"Unicode whole word","start":"UTF-16 start in explicit layer","offset":"Match page offset","limit":"Match page size"],description:"Find text in visible editable type layers without changing document/history.",optionalParameters:["layerID","caseSensitive","wholeWord","start","offset","limit"]),
    .init(name:"text.replace",parameters:["find":"Literal text","replacement":"New text; empty deletes matches","layerID":"Single layer UUID; omitted searches all eligible type layers","caseSensitive":"Exact case","wholeWord":"Unicode whole word","start":"UTF-16 start in explicit layer","replaceAll":"All matches or only the next match"],description:"Replace type text with formatting, native shaping, one Undo and semantic Actions.",optionalParameters:["layerID","caseSensitive","wholeWord","start","replaceAll"]),
    .init(name:"text.layout",parameters:["layerID":"Type layer UUID","settings":"Editable layout settings","enabled":"False removes layout","pathID":"Saved document path"],description:"Apply editable path, warp or Dynamic Text layout with Undo.",optionalParameters:["settings","enabled","pathID"]),
    .init(name:"text.glyph",parameters:["layerID":"Type layer UUID","font":"Installed font","glyphID":"Glyph table ID","location":"UTF-16 insertion offset","length":"UTF-16 replacement length"],description:"Insert a retained glyph in editable type, with Undo.",optionalParameters:["location","length"]),
    .init(name: "text.create", parameters: ["text": "Native type description", "x": "Pixel x", "y": "Pixel y", "name": "Layer name"], description: "Create editable point or paragraph text with native shaping and Undo.", optionalParameters: ["name"]),
    .init(name: "text.set", parameters: ["layerID": "Type layer UUID", "text": "Complete native type description"], description: "Replace editable text and formatting, retaining the layer transform, effects and masks."),
    .init(name: "layer.transform", parameters: ["layerID": "layer UUID", "a": "affine coefficient", "b": "affine coefficient", "c": "affine coefficient", "d": "affine coefficient", "tx": "translation in pixels", "ty": "translation in pixels"], description: "Apply an affine delta through native Free Transform. Smart Objects, video and layers with geometry keyframes retain source pixels; other raster layers resample with bicubic interpolation."),
    .init(name: "smartObject.convert", parameters: ["layerIDs": "one to 8,000 unique UUIDs"], description: "Convert selected layers into one embedded editable Smart Object."),
    .init(name: "smartObject.place", parameters: ["sourceDocumentID": "shared source UUID", "sourceRevision": "current source revision", "fit": "boolean, default true", "transform":"Optional document-coordinate matrix after centering/fit"], description: "Place an editable snapshot of a shared source document with optional initial transform in one Undo.", optionalParameters: ["fit","transform"]),
    .init(name: "smartObject.replace", parameters: ["layerID": "Smart Object UUID", "sourceDocumentID": "shared source UUID", "sourceRevision": "current source revision", "preserveSize": "boolean, default true", "allInstances": "boolean, default true"], description: "Replace embedded content from a shared document. Original transforms and masks are retained.", optionalParameters: ["preserveSize", "allInstances"]),
    .init(name: "smartObject.copy", parameters: ["layerID": "Smart Object UUID"], description: "New Smart Object via Copy, with independent source content."),
    .init(name: "smartObject.resetTransform", parameters: ["layerID": "Smart Object UUID"], description: "Restore source dimensions and rotation, retaining the integer layer origin."),
    .init(name: "layer.rasterize", parameters: ["layerID": "editable layer UUID"], description: "Rasterize an editable layer including Smart Objects. Source contents are discarded in the new state, recoverable with Undo."),
    .init(name:"selection.sky",parameters:["layerID":"Optional current source layer UUID","sampleAllLayers":"Sample visible composite, default true","settings":"Sky threshold/softness","mode":"replace, add, subtract or intersect"],description:"Select the sky through native classical segmentation; no-sky errors preserve the current selection.",optionalParameters:["layerID","sampleAllLayers","settings","mode"]),
    .init(name:"sky.replace",parameters:["skyID":"Imported sky library UUID","sourceLayerID":"Existing raster source layer UUID instead of skyID","settings":"Replacement placement/blending/output settings","strokes":"Manual sky mask refinement strokes","useSelection":"Use current selection instead of sky detection"],description:"Replace the sky with editable native layers or a duplicate merged layer in one Undo transaction.",optionalParameters:["skyID","sourceLayerID","settings","strokes","useSelection"]),
    .init(name:"sky.library",parameters:["operation":"list, import, rename, delete or export","skyID":"Sky library UUID","name":"Sky name","data":"Base64 image for import"],description:"Manage the optional persistent sky image library without editing document pixels.",optionalParameters:["skyID","name","data"]),
    .init(name: "selection.subject", parameters: ["layerID": "pixel layer UUID", "sampleAllLayers": "boolean, default false", "mode": "replace (default), add, subtract or intersect"], description: "Find foreground subjects with Apple Vision on-device. Commits one undoable selection. May fail if the system model is unavailable or no subject is found.", optionalParameters: ["sampleAllLayers", "mode"]),
    .init(name: MaskManagementAPI.command, parameters: ["layerID": "Mask owner UUID", "target": "layerMask, vectorMask or smartFilterMask; default layerMask", "operation": "apply or delete"], description: "Apply a supported pixel mask or delete a selected mask while retaining its layer, using native prepared history.", optionalParameters: ["target"]),
    .init(name: "layer.maskAllObjects", parameters: ["layerID": "Raster layer UUID"], description: "Create a separate editable masked group per detected object using the native local Vision model. Preserves the source and selection; returns createdGroupIDs in stacking order."),
    .init(name: "layer.removeBackground", parameters: ["layerID": "unlocked pixel layer UUID without an existing mask", "sampleAllLayers": "boolean, default false"], description: "Create an editable foreground layer mask using the same native on-device detector as Select Subject. Keeps original pixels and the selection.", optionalParameters: ["sampleAllLayers"]),
    .init(name: "layer.style", parameters: ["layerIDs": "one to8,000 unique UUIDs", "style": "LayerStyle object or null to clear", "globalLight":"Optional document shared light"], description: "Replace editable effects and optionally shared light atomically. Read layer state to copy styles.", optionalParameters:["globalLight"]),
    .init(name:"layer.style.patch",parameters:["layerIDs":"One to8,000 unique UUIDs","patch":"Partial root style object","effectIndex":"Existing zero-based effect index","effect":"Partial effect object","globalLight":"Optional document shared light"],description:"Patch independent layer styles without resubmitting retained descriptors. Optional effectIndex/effect edits one existing effect; arrays explicitly replace.",optionalParameters:["patch","effectIndex","effect","globalLight"]),
    .init(name:"document.globalLight",parameters:["angle":"Shared light angle","altitude":"Shared light altitude"],description:"Set document-wide effects light through native history."),
    .init(name: "smartFilter.set", parameters: ["layerID": "uuid", "stack": "Editable filter stack or null"], description: "Edit, reorder, enable or clear Smart Filters and their mask settings."),
    .init(name: "smartFilter.maskStroke", parameters: ["layerID": "uuid", "points": "Document-coordinate stroke", "size": "Brush diameter", "hardness": "0...1", "opacity": "0...1", "value": "Grayscale value"], description: "Paint the shared Smart Filter mask using the native brush and Undo."),
    .init(name: "smartFilter.maskFill", parameters: ["layerID": "uuid", "value": "Grayscale value"], description: "Fill the Smart Filter mask respecting selection coverage."),
    .init(name:"raw.inspect",parameters:["layerID":"RAW Smart Object UUID"],description:"Read sensor/decoder capabilities and retained settings without mutation."),
    .init(name:"raw.develop",parameters:["layerID":"RAW Smart Object UUID","settings":"Partial RAW settings object","allInstances":"Optional boolean, default true"],description:"Redevelop original sensor bytes with shared native history.",optionalParameters:["allInstances"]),
    .init(name: "liquify.faces", parameters: ["layerID": "Raster or Smart Object UUID", "filterID": "Optional existing filter UUID; detect on its input"], description: "Read on-device face geometry for Liquify. Returns revision,width,height,faces; no document mutation or history.", optionalParameters: ["filterID"]),
    .init(name: FilterRecallAPI.name, parameters: [:], description: "Repeat captured last-filter settings on the current native target in one Undo transaction; discover filterRecall state."),
    .init(name: "filter.apply", parameters: ["layerID": "uuid", "filter": "filter object: kind plus optional kind-specific parameters"],
      description: "Apply a native raster filter with selection, alpha protection and shared Undo. Requires RGB layer targeting. Discover parameters and limits in filters."),
    .init(name: "layer.protection", parameters: ["layerIDs": "one to8,000 unique layer UUIDs",
      "protection": "none or all alone; or transparency, composite, position, artboard_autonest",
      "includeDescendants": "optional boolean, default false"],
      description: "Replace selected layer protection in one native undo transaction. Groups also enforce inherited protection; includeDescendants additionally replaces each descendant’s stored flags.",
      optionalParameters: ["includeDescendants"]),
    .init(
      name: "layer.flatten", parameters:["discardHiddenLayers":"Explicitly discard hidden layers; default false"], description:"Flatten through the full native document compositor into Background, with one Undo. Retains document channels, paths, guides and profiles.", optionalParameters:["discardHiddenLayers"]),
    .init(
      name: "layer.merge",
      parameters: [
        "operation": "down, selected or visible",
        "layerIDs": "unique UUID array; one for down, two or more or one group for selected, empty for visible",
      ],
      description:
        "Merge supported static RGB layers through the shared native compositor, including groups, complete clipping bases, type, shapes, masks, transforms, effects and resolved Smart artwork. One Undo; preserves untouched layers and document state. Visible clips to canvas; selected/down retain supported off-canvas geometry. Numerical/temporal and unresolved hierarchy cases reject explicitly; renderer resource budgets apply."
    ),
    .init(name: EmptyLayerDeletionAPI.name, parameters: [:],
      description: "Delete supported empty raster layers and plain groups through the native transaction. Retains nonempty, locked and extended editable content, one editable layer and surviving selection. No-op adds no Undo. Discover limitations in emptyLayerDeletion."),
    .init(
      name: "document.save", parameters: ["options": "optional format-specific encoding options"],
      description:
        "Save the shared document to its associated file through the native save path. Requires separate local-saving permission; no path is accepted.",
      optionalParameters: ["options"]
    ),
    .init(
      name: "document.saveAs",
      parameters: [
        "name": "filename, no path components", "format": "photato, psd, png, jpeg or tiff",
        "replace": "boolean",
        "options": "optional format-specific encoding options",
      ],
      description:
        "Save to a filename inside the native-approved Save As folder, adopting that file association. Requires separate local-saving permission and a selected folder.",
      optionalParameters: ["options"]
    ),
    .init(
      name: "document.revert", parameters: [:],
      description:
        "Reload this shared document's associated file as one undoable edit. Requires native document-transfer enablement; no file path is accepted. A successful Revert clears the modified flag."
    ),
    .init(
      name: "channel.target", parameters: ["channel": "RGB, Red, Green or Blue"],
      description:
        "Select the native editing target and its preview. Component editing requires RGB8. Target selection does not change document history."
    ),
    .init(
      name: "channel.fill", parameters: ["value": "number, 0–1", "opacity": "number, 0–1"],
      description:
        "Normal neutral Fill of the selected RGB8 components on the active pixel layer. Preserves other components and alpha, respects selection and shares desktop undo."
    ),
    .init(
      name: "view.channelPreview", parameters: ["channel": "RGB, Red, Green or Blue"],
      description:
        "Choose a channel preview. This changes view state, not the channel editing target or document history."
    ),
    .init(
      name: "view.channelVisibility",
      parameters: ["channel": "RGB, Red, Green or Blue", "visible": "boolean"],
      description:
        "Show or hide color components without changing the preview selection. Hiding the last visible component is a no-op. Mask views must be exited first."
    ),
    .init(
      name: "layer.rename", parameters: ["layerID": "uuid", "name": "string, 1–256 characters"],
      description: "Rename one layer."),
    .init(
      name: "layer.opacity", parameters: ["layerID": "uuid", "opacity": "number, 0–1"],
      description: "Set one layer's opacity using the same command as the Layers numeric field and pop-up slider. The desktop slider previews without changing history; acceptance commits one edit, Escape cancels, and API mutations return busy while the slider is open."),
    .init(
      name: "layer.visibility", parameters: ["layerID": "uuid", "visible": "boolean"],
      description: "Set one layer's visibility."),
    .init(name: LayerFilterAPI.command, parameters: ["operation": "configure, enable, disable, find, isolate, selectAll or reset", "filter": "Partial document-local panel filter settings"], description: "Filter Layers panel rows without altering visibility, pixels or edit history. Shared native Find/Isolate and state.", optionalParameters: ["filter"]),
    .init(name: LayerStackOrderAPI.command, parameters: ["layerIDs": "Distinct layer UUIDs", "operation": "bringToFront, bringForward, sendBackward, sendToBack or reverse"], description: "Arrange complete layer/group subtrees within each parent as one Undo transaction. Background stays at the bottom; Reverse exchanges selected slots. Portable Actions48."),
    .init(
      name: "layer.move",
      parameters: ["layerID": "uuid", "x": "integer, ±1000000", "y": "integer, ±1000000"],
      description: "Set absolute layer position in document pixels."),
    .init(
      name: "layer.new", parameters: ["name": "string, 1–256 characters"],
      description: "Create a transparent pixel layer above the active layer."),
    .init(
      name: "layer.fill",
      parameters: [
        "layerID": "uuid", "r": "number, 0–1", "g": "number, 0–1", "b": "number, 0–1",
        "a": "number, 0–1",
      ],
      description:
        "Fill a pixel layer with native RGBA values, respecting the document selection. Does not target a mask."
    ),
    .init(
      name: "selection.rectangle",
      parameters: [
        "x": "integer, >=0", "y": "integer, >=0", "width": "integer, >=1", "height": "integer, >=1",
      ], description: "Replace selection with a rectangle contained in the canvas."),
    .init(name: "selection.clear", parameters: [:], description: "Deselect."),
    .init(name:"selection.shape",parameters:["shape":"One rectangle, ellipse, polygon, row index or column index","mode":"replace/add/subtract/intersect","antiAlias":"Subpixel coverage","feather":"Native feather radius0–100"],description:"Create or combine canvas-space coverage through native prepared selection history.",optionalParameters:["mode","antiAlias","feather"]),
    .init(name:"selection.inverse",parameters:[:],description:"Invert the current selection through native history."),
    .init(name:"selection.feather",parameters:["radius":"Native feather radius0–100"],description:"Feather current coverage through native prepared history."),
    .init(
      name: "history.undo", parameters: [:],
      description: "Undo the latest shared desktop/API document edit."),
    .init(
      name: "history.redo", parameters: [:], description: "Redo the latest undone document edit."),
    .init(
      name: "history.cancel", parameters: ["operationID": "UUID of the active history operation"],
      description: "Request cancellation of one active desktop/API Undo or Redo. No document edit."),
    .init(
      name: "document.autosave", parameters: [:],
      description:
        "Write committed content to AppKit-managed crash recovery storage. Keeps explicit Save and dirty/history state unchanged."
    ),
  ]
  let name: String
  let revision: String
  let parameters: [String: AutomationValue]
  init(data: Data) throws {
    let object: [String: AutomationValue]
    do { object = try JSONDecoder().decode([String: AutomationValue].self, from: data) } catch {
      throw AutomationFailure(status: 400, message: "Expected a JSON command object.")
    }
    guard Set(object.keys) == ["command", "revision", "parameters"],
      case .string(let name) = object["command"], case .string(let revision) = object["revision"],
      case .object(let parameters) = object["parameters"]
    else {
      throw AutomationFailure(
        status: 400, message: "Required fields: command, revision, parameters.")
    }
    guard let definition = Self.definitions.first(where: { $0.name == name }) else {
      throw AutomationFailure(
        status: 422, message: "Command is not implemented by this API version.")
    }
    guard Set(parameters.keys).isSubset(of: Set(definition.parameters.keys)),
      Set(definition.parameters.keys).subtracting(definition.optionalParameters).isSubset(of: Set(parameters.keys)) else {
      throw AutomationFailure(status: 400, message: "Missing or unknown command parameters.")
    }
    if BackgroundLayerAPI.commands.contains(name) {for (key,value) in parameters {_ = try BrushAPI.merge(value,schema:BackgroundLayerAPI.schema(key),path:key)}}
    if PixelPaintAPI.commands.contains(name){for(key,value) in parameters{_ = try BrushAPI.merge(value,schema:PixelPaintAPI.schema(key),path:key)}}
    if name == LayerFilterAPI.command { for (key,value) in parameters { _ = try BrushAPI.merge(value,schema:LayerFilterAPI.schema(key),path:key) } }
    if name == LayerStackOrderAPI.command { for(key,value) in parameters { _ = try BrushAPI.merge(value,schema:LayerStackOrderAPI.schema(key),path:key) } }
    if LayerLinksAPI.commands.contains(name){for(key,value) in parameters{_ = try BrushAPI.merge(value,schema:LayerLinksAPI.schema(key),path:key)}}
    if name == LayerCollectionTransformAPI.name {for(key,value) in parameters{_ = try BrushAPI.merge(value,schema:LayerCollectionTransformAPI.schema(key),path:key)}}
    if name == ChannelTransformAPI.name {for(key,value) in parameters{_ = try BrushAPI.merge(value,schema:ChannelTransformAPI.schema(key),path:key)}}
    if name == PixelMaskTransformAPI.name {for(key,value) in parameters{_ = try BrushAPI.merge(value,schema:PixelMaskTransformAPI.schema(key),path:key)}}
    if name == SelectedPixelMoveAPI.name {for (key,value) in parameters {_ = try BrushAPI.merge(value,schema:SelectedPixelMoveAPI.schema(key),path:key)}}
    if name == SelectedPixelTransformAPI.name {
      for (key,value) in parameters {_ = try BrushAPI.merge(value,schema:SelectedPixelTransformAPI.schema(key),path:key)}
    }
    if name == "selection.transform" {
      for (key,value) in parameters {_ = try BrushAPI.merge(value,schema:SelectionTransformAPI.schema(key),path:key)}
    }
    if SelectionModifyAPI.commands.contains(name) {
      for (key,value) in parameters {_ = try BrushAPI.merge(value,schema:SelectionModifyAPI.schema(key),path:key)}
    }
    if MagneticLassoAPI.commands.contains(name) {
      for (key,value) in parameters {_ = try BrushAPI.merge(value,schema:MagneticLassoAPI.schema(key),path:key)}
    }
    if name == "selection.colorRange" {
      for (key,value) in parameters {_ = try BrushAPI.merge(value,schema:ColorRangeAPI.schema(key),path:key)}
    }
    if LayerFilesAPI.commands.contains(name) {
      for (key, value) in parameters { _ = try BrushAPI.merge(value, schema: LayerFilesAPI.schema(key), path: key) }
    }
    if ImageExportAPI.commands.contains(name) {
      for (key, value) in parameters { _ = try BrushAPI.merge(value, schema: ImageExportAPI.schema(key, preferences: name == "export.preferences"), path: key) }
    }
    if LayerCompsAPI.commands.contains(name) {
      for (key, value) in parameters { _ = try BrushAPI.merge(value, schema: LayerCompsAPI.schema(key), path: key) }
    }
    if VariablesAPI.commands.contains(name) {
      for (key, value) in parameters { _ = try BrushAPI.merge(value, schema: VariablesAPI.schema(key), path: key) }
    }
    self.name = name
    self.revision = revision
    self.parameters = parameters
  }
  func string(_ key: String) throws -> String {
    guard case .string(let value) = parameters[key],
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      value.count <= 256,
      !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { throw AutomationFailure(status: 400, message: "Invalid \(key).") }
    return value
  }
  func number(_ key: String, range: ClosedRange<Double>) throws -> Double {
    guard case .number(let value) = parameters[key], value.isFinite, range.contains(value) else {
      throw AutomationFailure(status: 400, message: "Invalid \(key).")
    }
    return value
  }
  func integer(_ key: String, range: ClosedRange<Double>) throws -> Int {
    let value = try number(key, range: range)
    guard value.rounded() == value else {
      throw AutomationFailure(status: 400, message: "\(key) must be an integer.")
    }
    return Int(value)
  }
  func nativeCommand(document: CraftDocument, lookup: ColorLookupAdjustment? = nil, colorSettings: ColorSettings? = nil) throws -> Command? {
    func id() throws -> UUID {
      guard let id = UUID(uuidString: try string("layerID")),
        document.layers.contains(where: { $0.id == id })
      else {
        throw AutomationFailure(status: 404, message: "Layer not found.")
      }
      return id
    }
    if name == "video.edit" { return try videoCommand() }
    if name == "layerComps.edit" { return try layerCompCommand(in: document) }
    if VariablesAPI.commands.contains(name), !name.hasPrefix("variables.export") { return try variableCommand(in: document) }
    if name == "animation.edit" { return try animationCommand() }
    if name == "channel.edit" { return try channelEdit(document:document) }
    switch name {
    case "layer.flatten": return nil
    case "layer.merge":
      let operation: LayerMergeOperation
      switch try string("operation") {
      case "down": operation = .down
      case "selected": operation = .selected
      case "visible": operation = .visible
      default: throw AutomationFailure(status: 400, message: "Invalid merge operation.")
      }
      guard case .array(let values) = parameters["layerIDs"], values.count <= LayerLimits.maximumLayers else {
        throw AutomationFailure(
          status: 400, message: "layerIDs must be an array of at most 8,000 UUIDs.")
      }
      let ids = try values.map { value -> UUID in
        guard case .string(let text) = value, let id = UUID(uuidString: text) else {
          throw AutomationFailure(status: 400, message: "Invalid layer UUID.")
        }
        return id
      }
      guard Set(ids).count == ids.count,
        operation == .visible ? ids.isEmpty : operation == .down ? ids.count == 1 : (ids.count >= 2 || (ids.count == 1 && document.layers.first(where:{$0.id==ids[0]})?.isGroup == true))
      else {
        throw AutomationFailure(
          status: 400, message: "Invalid layer selection for merge operation.")
      }
      guard Set(ids).isSubset(of: Set(document.layers.map(\.id))) else {
        throw AutomationFailure(status: 404, message: "Layer not found.")
      }
      _ = try LayerMergePlan(operation,layerIDs:Set(ids),in:document)
      return .mergeLayers(Set(ids), operation)
    case MaskManagementAPI.command: return try maskManagementRequest(in: document).command(in: document)
    case "layer.style": return try layerStyleCommand(document: document)
    case "layer.style.patch", "document.globalLight": return try advancedStyleCommand(document:document)
    case "adjustment.create", "adjustment.set", "adjustment.apply": return try classicAdjustmentCommand(document: document, lookup: lookup)
    case "ink.channel.write", "ink.channel.edit", "ink.channel.manage": return try inkChannelCommand(in: document)
    case "mode.channel.edit": return try modeComponentEdit(in: document)
    case "document.resize", "document.fitImage", "document.canvasSize", "document.rotate", "document.resolution", "selection.shape", "selection.inverse", "selection.feather": return try geometryCommand(in: document)
    case "document.convertDuotone", "document.convertMultichannel": return try inkModeRequest(in: document).command(in: document)
    case "document.convertIndexed", "document.convertBitmap", "indexed.colorTable.write": return try restrictedModeRequest(in: document).command(in: document)
    case "indexed.indices.write": return try indexedWrite(in: document)
    case "document.assignProfile", "document.convertProfile": return try ColorProfileInput.command(colorProfileRequest(in: document, settings: colorSettings ?? .init()), in: document)
    case "document.convertMode": return try DocumentModeInput.command(documentModeRequest(settings: colorSettings, document: document), in: document)
    case "mode.channel.write": return try modeChannelWrite(in: document)
    case "tone.apply":return .toneAdjustment(try classicToneRequest(document))
    case "render.flame","render.tree","render.pictureFrame":return .proceduralRender(try proceduralRequest(document))
    case "filter.apply": return try filterCommand(document: document)
    case GradientFillAPI.command: return try gradientFillCommand(document)
    case "text.layout":return try textLayoutCommand(document)
    case "text.glyph":return try insertTypeGlyph(document)
    case "text.create", "text.set": return try textCommand(document: document)
    case "smartFilter.set", "smartFilter.maskStroke", "smartFilter.maskFill": return try smartFilterCommand(document: document)
    case "pixels.fill","pixels.stroke":return .pixelPaint(try pixelPaintRequest(patterns:document.patterns ?? []))
    case "layer.links":return .layerLinks(try layerLinkCommand())
    case LayerStackOrderAPI.command: return .stackLayers(try layerStackOrderOptions())
    case "layers.move":return .moveLayers(try wholeLayerMoveOptions())
    case "layer.protection": return try protectionCommand(document: document)
    case "layer.rename": return .renameLayer(try id(), try string("name"))
    case "layer.opacity": return .opacity(try id(), Float(try number("opacity", range: 0...1)))
    case "layer.visibility":
      guard case .bool(let value) = parameters["visible"] else {
        throw AutomationFailure(status: 400, message: "visible must be boolean.")
      }
      return .visibility(try id(), value)
    case "layer.move":
      return .move(
        try id(), try integer("x", range: -1_000_000...1_000_000),
        try integer("y", range: -1_000_000...1_000_000))
    case "layer.new": return .newPixelLayer(NewPixelLayerOptions(name: try string("name")))
    case "layer.fill":
      let target = try id()
      guard case .raster = document.layers.first(where: { $0.id == target })?.content else {
        throw AutomationFailure(status: 422, message: "Fill requires a pixel layer.")
      }
      return .fill(
        target,
        Pixel(
          Float(try number("r", range: 0...1)), Float(try number("g", range: 0...1)),
          Float(try number("b", range: 0...1)), Float(try number("a", range: 0...1))))
    case "selection.rectangle":
      let x = try integer("x", range: 0...Double(document.width - 1))
      let y = try integer("y", range: 0...Double(document.height - 1))
      let width = try integer("width", range: 1...Double(document.width - x))
      let height = try integer("height", range: 1...Double(document.height - y))
      return .selection(IntRect(x: x, y: y, width: width, height: height))
    case "selection.clear": return .selection(nil)
    case "history.undo", "history.redo": return nil
    default: throw AutomationFailure(status: 422, message: "Unsupported command.")
    }
  }

  @MainActor func applyViewCommand(to store: EditorStore) throws -> Bool {
    if name == "ink.channel.select" { try store.selectInkChannels(Set(inkTargets(in: store.document, allowEmpty: true))); return true }
    if name == "ink.channel.visibility" { try store.setInkVisibility(Set(inkTargets(in: store.document,allowEmpty:store.hasAuxiliaryChannelRows))); return true }
    if name == "mode.channel.select" { try store.selectModeComponents(modeComponents(in: store.document, allowEmpty: true)); return true }
    if name == "mode.channel.visibility" { try store.setModeComponentVisibility(modeComponents(in: store.document,allowEmpty:store.hasAuxiliaryChannelRows)); return true }
    if name == "channel.view" {
      let target = try string("target")
      if target=="layerMask" || target=="smartFilterMask" {
        guard parameters["overlay"]==nil else{throw AutomationFailure(status:400,message:"Mask targets do not accept overlay; use visible for their independent eye.")}
        if let raw=parameters["visible"],case .bool=raw {}else if parameters["visible"] != nil {throw AutomationFailure(status:400,message:"visible must be boolean.")}
        let id=try actionUUID("layerID")
        guard store.canSelectComponentTarget,store.canBeginLayerCreation else{throw AutomationFailure(status:409,message:"Finish the current interaction before selecting a mask.")}
        guard let layer=store.document.layers.first(where:{$0.id==id}) else{throw AutomationFailure(status:404,message:"Mask owner not found.")}
        guard target=="layerMask" ? layer.mask != nil:layer.smartFilters?.mask != nil else{throw AutomationFailure(status:422,message:"The requested mask is unavailable.")}
        if case .bool(let visible)=parameters["visible"] {try store.setChannelEye(.mask(.init(layerID:id,smartFilter:target=="smartFilterMask")),visible:visible)}
        else {try store.selectTemporaryMaskChannel(.init(layerID:id,smartFilter:target=="smartFilterMask"))}
        return true
      }
      guard parameters["layerID"]==nil else{throw AutomationFailure(status:400,message:"layerID applies only to a layerMask or smartFilterMask target.")}
      var overlay = false
      if let raw = parameters["overlay"] { guard case .bool(let v) = raw else { throw AutomationFailure(status:400,message:"overlay must be boolean.") }; overlay = v }
      if let raw = parameters["visible"] {
        guard case .bool(let visible)=raw else{throw AutomationFailure(status:400,message:"visible must be boolean.")}
        if target=="quickMask" {try store.setQuickMaskVisibility(visible)}
        else if target=="RGB" {try store.setColorChannelsVisibility(visible)}
        else {guard let id=UUID(uuidString:target) else{throw AutomationFailure(status:400,message:"Expected RGB, quickMask or an auxiliary channel UUID.")};try store.setAlphaVisibility(id,visible)}
        return true
      }
      if target == "RGB" { try store.selectEditingChannel(.composite) }
      else { let t = try channelTarget(); _ = try store.document.channel(t); if case .alpha(let id) = t { try store.selectAlphaChannel(id,overlay:overlay) } else { try store.selectQuickMaskChannel() } }
      return true
    }
    if name == "channel.fill" {
      let command = try store.componentFillCommand(
        value: Float(number("value", range: 0...1)),
        opacity: Float(number("opacity", range: 0...1)))
      try store.executeEditorCommand(command)
      return true
    }
    guard ["channel.target", "view.channelPreview", "view.channelVisibility"].contains(name) else {
      return false
    }
    guard store.document.colorMode == .rgb else { throw AutomationFailure(status: 422, message: "Use mode.channel.select or mode.channel.visibility for this color mode.") }
    let title = try string("channel")
    guard let channel = RGBChannelPreview.allCases.first(where: { $0.title == title }) else {
      throw AutomationFailure(status: 400, message: "channel must be RGB, Red, Green or Blue.")
    }
    if name == "channel.target" {
      try store.selectEditingChannel(channel)
    } else if name == "view.channelPreview" {
      store.previewChannel(channel)
    } else {
      guard case .bool(let visible) = parameters["visible"] else {
        throw AutomationFailure(status: 400, message: "visible must be boolean.")
      }
      guard store.setChannelVisibility(channel, visible: visible) else {
        throw AutomationFailure(
          status: 422, message: "Finish the current interaction before changing channel visibility.")
      }
    }
    return true
  }
}
