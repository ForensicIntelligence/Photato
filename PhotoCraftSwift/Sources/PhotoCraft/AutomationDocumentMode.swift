import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum DocumentModeAPI {
  static let commands = ["document.convertMode", "mode.channel.read", "mode.channel.write", "mode.channel.select", "mode.channel.visibility", "mode.channel.edit"]
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "components": ["type": "array", "maxItems": 4, "uniqueItems": true, "items": ["type": "integer", "minimum": 0, "maximum": 3]]
    case "action": BrushAPI.enumeration(["fill", "stroke", "invert", "filter"])
    case "value", "opacity": BrushAPI.number()
    case "brush": BrushAPI.brush
    case "points": BrushAPI.schema("points")
    case "filter": RasterFilter.apiSchema
    case "mode": BrushAPI.enumeration(DocumentColorMode.componentModes.map(\.rawValue))
    case "depth": ["type": "integer", "enum": [8, 16, 32]]
    case "intent": BrushAPI.enumeration(ModeRenderingIntent.allCases.map(\.rawValue))
    case "mergeVisible", "clipHDR": BrushAPI.flag
    case "profileBase64": ["type": "string", "contentEncoding": "base64", "maxLength": 5_592_408]
    case "component": ["type": "integer", "minimum": 0, "maximum": 3]
    case "offset": ["type": "integer", "minimum": 0, "maximum": NativeModeRaster.maximumDocumentPixels - 1]
    case "count": ["type": "integer", "minimum": 1, "maximum": 4096]
    case "values": ["type": "array", "minItems": 1, "maxItems": 4096,
      "items": ["type": "number", "minimum": -Double(Float.greatestFiniteMagnitude), "maximum": Double(Float.greatestFiniteMagnitude)]]
    default: ["type": "string", "format": "uuid"]
    }
  }
  static var stateSchema: [String: Any] {
    BrushAPI.object(["mode": BrushAPI.enumeration(DocumentColorMode.allCases.map(\.rawValue)), "depth": ["type": "integer", "enum": [1, 8, 16, 32]], "nativeComponents": BrushAPI.flag,
      "components": ["type": "array", "items": ["type": "string"]],
      "editingComponents": schema("components"), "visibleComponents": schema("components"), "componentEditingAvailable": BrushAPI.flag,
      "conversionAvailable": BrushAPI.flag, "requiresMerge": BrushAPI.flag,
      "previousPaletteAvailable": BrushAPI.flag, "indexedConversionAvailable": BrushAPI.flag, "bitmapConversionAvailable": BrushAPI.flag, "colorTableAvailable": BrushAPI.flag, "paletteCount": ["type": "integer", "minimum": 0, "maximum": 256], "restrictedWorkspace": BrushAPI.enumeration(["none", "indexed", "bitmap", "colorTable"]),
      "workspaceOpen": BrushAPI.flag, "previewBusy": BrushAPI.flag, "committing": BrushAPI.flag],
      required: ["mode", "depth", "nativeComponents", "components", "editingComponents", "visibleComponents", "componentEditingAvailable", "conversionAvailable", "requiresMerge", "workspaceOpen", "previewBusy", "committing", "indexedConversionAvailable", "bitmapConversionAvailable", "colorTableAvailable", "paletteCount", "restrictedWorkspace", "previousPaletteAvailable"])
  }
  static var capabilities: [String: Any] {
    ["commands": commands, "modes": Dictionary(uniqueKeysWithValues: DocumentColorMode.componentModes.map {
      ($0.rawValue, ["components": $0.componentNames, "depths": $0.depths.map(bits)] as [String: Any])
    }), "nativeArchive": 46, "maximumPixels": NativeModeRaster.maximumDocumentPixels, "maximumChannelSamples": 4096,
      "storage": ["sampleBlockSize": ComponentPlane.blockSamples, "copyOnWriteLevels": 4, "implicitUniformFill": true, "rawSampleBits": true, "denseOperationMaximumPixels": NativeModeRaster.maximumPixels, "largeNativeArchiveVersion":86, "maximumPixels": NativeModeRaster.maximumDocumentPixels, "limits": "Native logical components admit300,000pixels per dimension with resident/mapped accounting and native86 pages. Sparse creation/conversion/channel visibility/local reconciliation share raw blocks. Native resampling, trim and expanded reframe use bounded raw output and derived projections; Component Fill/Invert/Brush/Eraser and the eight listed filters use bounded projections/output; dense jobs retain physical storage/time limits. Legacy dense exports, channel blending and PSD/PSB/TIFF/profile/printing retain separate limits. Full dense capacity and Photoshop/platform/performance qualification remain open."],
      "componentFilters": ModeComponentEdit.filters.map(\.rawValue).sorted(),
      "legacyRGB8Tools": ["targetCommand":"channel.target","targetStatePreserved":true,"previewAndVisibilityIndependent":true,"numericalTargetState":"documentMode.editingComponents","commands":["channel.fill","mode.channel.edit","paint.stroke"],"operations":["fill","stroke","erase","invert","filter"],"neutralFillOpacity":"Generic neutral RGBA Fill and desktop Fill multiply color alpha by explicit opacity; channel.fill retains its existing value/opacity primitive. Nonneutral/profile conversion remains unavailable.","filterKinds":ModeComponentEdit.filters.map(\.rawValue).sorted(),"maximumPixels":Surface.maxPixels,"behavior":"Ordinary RGB8 Red/Green/Blue targets share the native component engine while retaining existing target and view state. Pixel paint.stroke respects the captured selected components; explicit mode.channel.edit must match a selected target. Desktop gestures, prepared previews/commit and API use the same component command, preserving other channels and alpha.","limits":"Other component tools, multi-target/visibility/clipboard/Actions/profile/default/Photoshop/live/platform/performance qualification remain open. No new Adobe route or descriptor."],
      "largeComponentTools": ["maximumDimension":Surface.maxDimension,"maximumPixels":Surface.maxPixels,"actions":["fill","stroke","invert","filter"],"maximumPatchPixels":RasterGeometry.maximumPatchPixels,"maximumSparseSelectionSupportTiles":RasterGeometry.sparseGridSourceTileLimit,"nativeArchiveVersion":86,"behavior":"Same selected-target validation, scalar arithmetic, brush and eight basic filter engines as the desktop. Raw native untargeted components and alpha are retained. Uniform/eligible sparse operations keep implicit fills; other jobs use checked paged output and remain cancellable. Failures discard the prepared candidate.","limits":"Large dense filters/coverage/painting may require substantial disk and time; this is not a physical maximum-capacity or60fps claim. Brush coverage, filter scratch and other shared admission remain authoritative. Exact Photoshop/cross-architecture kernels/defaults and current live/platform validation remain open. No new Adobe route or descriptor."],
      "componentEditing": "mode.channel.select selects UI editing components (empty means composite). Visibility is independent; an empty visibility set hides image components while retaining the edit target and saved masks. mode.channel.edit supports selection-aware fill, stroke/erase, invert and listed filters with one Undo. Editing values are view-gray: zero is black/full CMYK ink; numerical read/write still exposes raw stored ink. Other planes and alpha are unchanged. Explicit edit targets must match any selected UI component target. The channel-preview.png endpoint matches the mode view.",
      "channelResultSchema": BrushAPI.object(["layerID": schema("layerID"), "component": schema("component"),
        "offset": schema("offset"), "values": schema("values"), "width": ["type": "integer"],
        "height": ["type": "integer"], "revision": ["type": "string"]],
        required: ["layerID", "component", "offset", "values", "width", "height", "revision"]),
      "behavior": "Color components use normalized numerical values; alpha is preserved and is not addressed by these operations. Float color samples may exceed 0...1. Reads/writes are bounded row-major pages in layer-local coordinates. Writes preserve every other plane, bypass selection and form one Undo transaction. Conversion keeps layers unless mergeVisible explicitly replaces them with their visible composite; hidden layers are discarded only in that mode. clipHDR is required to reduce 32-bit precision. Omit profileBase64 to use the captured destination working space; precision-only changes retain the current document profile. Explicit profiles override defaults.",
      "limits": "Native components are authoritative; ordinary composite blend/filter algorithms use derived RGB. Raster/group/mask PSD/PSB/TIFF interchange and both job interfaces support documented mode creation/conversion/component action subsets; see actionJobs.colorModeActions. Full component tools, semantic Actions, restricted modes and complete Adobe compatibility remain pending. Editable non-RGB rich PSD content remains unsupported. No Photoshop colorimetric equivalence is claimed."]
  }
  static func bits(_ depth: PixelDepth) -> Int { depth == .u8 ? 8 : depth == .u16 ? 16 : 32 }
}

extension AutomationCommand {
  func documentModeRequest(settings: ColorSettings? = nil, document: CraftDocument? = nil) throws -> DocumentModeRequest {
    guard let mode = DocumentColorMode(rawValue: try string("mode")) else {
      throw AutomationFailure(status: 400, message: "Unknown color mode.")
    }
    guard DocumentColorMode.componentModes.contains(mode) else { throw AutomationFailure(status: 422, message: "Use the mode-specific convertIndexed, convertBitmap, convertDuotone or convertMultichannel operation.") }
    let bits = try integer("depth", range: 8...32)
    guard [8, 16, 32].contains(bits) else { throw AutomationFailure(status: 400, message: "Choose depth 8, 16 or 32.") }
    let depth: PixelDepth = bits == 8 ? .u8 : bits == 16 ? .u16 : .f32
    guard mode.depths.contains(depth) else { throw AutomationFailure(status: 400, message: "The color mode does not support this precision.") }
    let intent: ModeRenderingIntent
    if parameters["intent"] != nil {
      guard let value = ModeRenderingIntent(rawValue: try string("intent")) else { throw AutomationFailure(status: 400, message: "Unknown rendering intent.") }
      intent = value
    } else { intent = settings?.intent ?? .relativeColorimetric }
    var profile: Data?
    if parameters["profileBase64"] != nil {
      guard case .string(let encoded) = parameters["profileBase64"] else { throw AutomationFailure(status: 400, message: "Invalid ICC profile encoding.") }
      guard encoded.count <= 5_592_408, let data = Data(base64Encoded: encoded) else { throw AutomationFailure(status: 400, message: "Invalid ICC profile encoding.") }
      do { try NativeModeProfile.validate(data, mode: mode, depth: depth) }
      catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
      profile = data
    }
    if profile == nil, let settings {
      profile = try document.map { try settings.conversionProfile(from: $0, to: mode, depth: depth) }
        ?? settings.profile(mode, depth: depth)
    }
    return .init(.init(mode: mode, depth: depth, profile: profile, intent: intent),
      mergeVisible: try pathFlag("mergeVisible", false), clipHDR: try pathFlag("clipHDR", false))
  }
  func modeChannelPage(in document: CraftDocument) throws -> (UUID, NativeModeRaster, Int, Int) {
    let id = try actionUUID("layerID")
    guard let layer = document.layers.first(where: { $0.id == id }) else { throw AutomationFailure(status: 404, message: "Layer not found.") }
    guard let native = layer.nativeMode else { throw AutomationFailure(status: 422, message: "Convert to a native document mode before accessing components.") }
    let component = try integer("component", range: 0...Double(native.mode.componentCount - 1))
    let offset = try parameters["offset"].map { _ in try integer("offset", range: 0...Double(native.width * native.height - 1)) } ?? 0
    return (id, native, component, offset)
  }
  func modeChannelWrite(in document: CraftDocument) throws -> Command {
    let (id, native, component, offset) = try modeChannelPage(in: document)
    guard case .array(let values) = parameters["values"], !values.isEmpty, values.count <= 4096,
      values.count <= native.width * native.height - offset else { throw AutomationFailure(status: 400, message: "Channel write exceeds the sample range.") }
    var plane = try native.channel(component)
    for (i, item) in values.enumerated() {
      guard case .number(let number) = item, number.isFinite, Float(number).isFinite,
        (native.depth == .f32 && component < native.mode.componentCount) || (0...1).contains(number) else {
        throw AutomationFailure(status: 400, message: "Invalid component sample; integer color and alpha must be in 0...1.")
      }
      let index = offset + i, value = Float(number)
      plane.setPixel(x: index % native.width, y: index / native.width, Pixel(value, value, value))
    }
    return .modeChannel(.init(layerID: id, component: component, pixels: plane))
  }
}

extension EditorStore {
  var documentModeState: [String: Any] {
    ["mode": document.colorMode.rawValue, "depth": document.bitsPerChannel,
      "nativeComponents": document.hasNativeModeStorage, "components": document.colorChannelNames,
      "editingComponents": effectiveComponentTargets.sorted(), "visibleComponents": modeVisibleComponents.sorted(), "componentEditingAvailable": canEditModeComponents,
      "previousPaletteAvailable": previousIndexedPalette != nil, "indexedConversionAvailable": canBeginRestrictedMode(.indexed), "bitmapConversionAvailable": canBeginRestrictedMode(.bitmap), "colorTableAvailable": canBeginRestrictedMode(.colorTable),
      "paletteCount": { if case .indexed(let r) = document.restrictedMode { return r.palette.count }; return 0 }(),
      "restrictedWorkspace": restrictedModeWorkspace?.request.kind.rawValue ?? "none",
      "conversionAvailable": canBeginDocumentMode, "requiresMerge": DocumentModeInput.needsMerge(document),
      "workspaceOpen": documentModeWorkspace != nil || restrictedModeWorkspace != nil || inkModeWorkspace != nil, "previewBusy": (documentModeWorkspace?.rendering ?? false) || (restrictedModeWorkspace?.rendering ?? false) || (inkModeWorkspace?.rendering ?? false),
      "committing": (documentModeWorkspace?.committing ?? false) || (restrictedModeWorkspace?.committing ?? false) || (inkModeWorkspace?.committing ?? false)]
  }
}
