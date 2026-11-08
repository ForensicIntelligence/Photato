import Foundation
import PhotoCraftCore

extension AutomationValue {
  var jsonValue: Any {
    switch self {
    case .string(let value): value
    case .number(let value): value
    case .bool(let value): value
    case .array(let value): value.map(\.jsonValue)
    case .object(let value): value.mapValues(\.jsonValue)
    case .null: NSNull()
    }
  }
}

extension RasterFilter {
  var apiState:[String:Any] {
    let all=(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(self))) as? [String:Any] ?? [:]
    var value=all.filter{kind.parameters.contains($0.key) || $0.key == "kind"}
    if let tone {value["tone"]=tone.apiParameters}
    if let classicDetail {value["classicDetail"]=classicDetail.apiParameters(kind:kind)}
    if let otherVideo {value["otherVideo"]=otherVideo.apiParameters(kind:kind)}
    if let renderSettings {value["render"]=renderSettings.apiParameters(kind:kind)}
    if let stylize,kind.parameters.contains("stylize") {value["stylize"]=stylize.apiParameters(kind:kind)}
    if let pixelate,kind.parameters.contains("pixelate") {value["pixelate"]=pixelate.apiParameters(kind:kind)}
    if let distortion {value["distortion"]=distortion.apiParameters(kind:kind)}
    return value
  }

  static var apiSchema: [String: Any] {
    let numbers: [String: [String: Any]] = [
      "radius": ["type": "number", "minimum": 0.1, "maximum": 1000],
      "amount": ["type": "number", "minimum": 0.1, "maximum": 500],
      "threshold": ["type": "integer", "minimum": 0, "maximum": 255],
      "angle": ["type": "number", "minimum": -360, "maximum": 360],
      "distance": ["type": "integer", "minimum": 1, "maximum": 2000],
      "cellSize": ["type": "integer", "minimum": 2, "maximum": 200],
      "seed": ["type": "integer", "minimum": 0, "maximum": UInt32.max],
      "monochromatic": ["type": "boolean"],
      "distribution": ["type": "string", "enum": ["uniform", "gaussian"]],
    ]
    return ["oneOf": Kind.allCases.map { kind -> [String: Any] in
      var properties: [String: Any] = ["kind": ["const": kind.rawValue]]
      for key in kind.parameters { properties[key] = key == "tone" ? ClassicToneAPI.settings(.shadowsHighlights) : key == "classicDetail" ? ClassicDetailSettings.apiSchema(kind:kind) : key == "otherVideo" ? OtherVideoSettings.apiSchema(kind:kind) : key == "render" ? RenderSettings.apiSchema(kind:kind) : key == "stylize" ? StylizeSettings.apiSchema(kind:kind) : key == "pixelate" ? PixelateSettings.apiSchema(kind:kind) : key == "distortion" ? DistortionSettings.apiSchema(kind:kind) : key == "lighting" ? LightingSettings.apiSchema : key == "relight" ? RelightSettings.apiSchema : key == "lensBlur" ? LensBlurSettings.apiSchema : key == "sharpen" ? SmartSharpenSettings.apiSchema : key == "denoise" ? ReduceNoiseSettings.apiSchema : key == "artistic" ? ArtisticGallerySettings.apiSchema : key == "wideAngle" ? WideAngleSettings.apiSchema : key == "lens" ? LensCorrectionSettings.apiSchema : key == "gallery" ? BlurGallerySettings.apiSchema : key == "perspective" ? PerspectiveSettings.apiSchema : key == "puppet" ? PuppetSettings.apiSchema : key == "cameraRaw" ? CameraRawSettings.apiSchema : key == "liquify" ? LiquifySettings.apiSchema : numbers[key] }
      if kind == .boxBlur { properties["radius"] = ["type": "integer", "minimum": 1, "maximum": 1000] }
      if kind == .addNoise { properties["amount"] = ["type": "number", "minimum": 0.1, "maximum": 400] }
      if kind == .unsharpMask { properties["amount"] = ["type": "number", "minimum": 1, "maximum": 500] }
      return ["type": "object", "additionalProperties": false, "required": kind == .displace ? ["kind","distortion"]:["kind"], "properties": properties]
    }]
  }
  static var apiCapabilities: [String: Any] {
    ["kinds": Kind.allCases.map(\.rawValue), "schema": apiSchema,
     "maskTargets":MaskFilterAPI.capabilities,
     "classicTone":ClassicToneAPI.capabilities,
     "classicDetail": ClassicDetailSettings.apiCapabilities,
     "otherVideo": OtherVideoSettings.apiCapabilities,
     "render": RenderSettings.apiCapabilities,
     "stylize": StylizeSettings.apiCapabilities,
     "pixelate": PixelateSettings.apiCapabilities,
     "distortion": DistortionSettings.apiCapabilities,
     "lightingEffects":LightingSettings.apiCapabilities,
     "relight":RelightSettings.apiCapabilities,
     "lensBlur": LensBlurSettings.apiCapabilities,
     "smartSharpen": SmartSharpenSettings.apiCapabilities,
     "reduceNoise": ReduceNoiseSettings.apiCapabilities,
     "filterGallery": ArtisticGallerySettings.apiCapabilities.merging(["effectReordering":GalleryEffectTransfer.apiCapabilities]) { _,value in value },
     "adaptiveWideAngle": WideAngleSettings.apiCapabilities,
     "lensCorrection": LensCorrectionSettings.apiCapabilities,
     "blurGallery": BlurGallerySettings.apiCapabilities,
     "puppetWarp": PuppetSettings.apiCapabilities,
     "perspectiveWarp": PerspectiveSettings.apiCapabilities,
     "liquify": LiquifySettings.apiCapabilities,
     "cameraRaw": CameraRawSettings.apiCapabilities,
     "maximumLayerPixels": RasterFilterEngine.maximumPixels,
     "largeBasicRasterFilters":["kinds":RasterFilterEngine.pagedFilterKinds.map(\.rawValue),
       "maximumDimension":Surface.maxDimension,"logicalMaximumPixels":Surface.maxPixels,
       "maximumScratchPlaneBytes":RasterFilterEngine.maximumPagedScratchPlaneBytes,
       "scratchSampleBytes":32,"maximumTransferBytes":65_536,"maximumOutputPatchPixels":131_072,
       "behavior":"Direct RGB raster filtering uses checked unlinked readonly Float64 premultiplied planes, full-line legacy reduction order and bounded output patches. Selection, transparency locks, global Noise sequence, history and native/API output are shared. Exact integer constant proofs preserve sparse cases.",
       "limits":"The generic maximumLayerPixels value remains the common preparation limit for other filter families; auxiliary channels expose filtering under channels. smartFilters.largeRGBStacks describes editable large stacks. Per-plane4TiB is file admission, separate from simultaneous planes, final raster scratch, physical disk/RSS and mapped residency. Full dense90GP/performance/Photoshop kernels/platform qualification remain open."],
     "targets": "Image pixels by default or explicit target=pixels; explicit layerMask/smartFilterMask use maskTargets. Single unlocked raster layer or Smart Object, RGB composite; RGB8/16 encoded samples, RGB32 linear samples except Lens Blur (RGB8/16 only). Selection coverage and transparency locks are respected.",
     "history": "One cancellable prepared native edit. Preview never edits the document; Cancel discards it.",
     "persistence": "Raster layers bake pixels; Smart Objects append editable filters in native15 archives (native19 for Liquify, native21 for Camera Raw, native25 for Puppet Warp, native26 for Perspective Warp, native29 for Blur Gallery, native30 for Lens Correction, native31 for Adaptive Wide Angle, native36 for Filter Gallery, native37 for photo detail, native38 for Lens Blur, native39 for distortions, native40 for Pixelate, native41 for Stylize, native42 for Render, native43 for Other/Video, native44 for Blur/Noise/Sharpen, native45 for Shadows/Highlights) and supported PSD/PSB descriptors. Liquify, Camera Raw, Puppet Warp, Perspective Warp Blur Gallery Lens Correction Adaptive Wide Angle Filter Gallery Smart Sharpen Reduce Noise Lens Blur distortion Pixelate Stylize (except Emboss) Render, Other/Video, Blur/Noise/Sharpen and Shadows/Highlights editable interchange with PSD/PSB is unsupported.",
     "limitations": "Photoshop pixel equality unqualified. Gaussian uses three running-box passes; Motion Blur uses at most257 samples. Mask targets are limited to the eight kinds in maskTargets; other target/mode limits remain. Noise seed is a Photato parameter; Adobe actionJSON uses a fixed local seed."]
  }
}

extension AutomationCommand {
  func filterCommand(document: CraftDocument) throws -> Command {
    let text = try string("layerID")
    guard let id = UUID(uuidString: text) else { throw AutomationFailure(status: 400, message: "Invalid layerID.") }
    guard let layer = document.layers.first(where: { $0.id == id }) else {
      throw AutomationFailure(status: 404, message: "Layer not found.")
    }
    let target=parameters["target"] == nil ? "pixels":try string("target")
    guard target=="pixels" || MaskFilterTarget(rawValue:target) != nil else {throw AutomationFailure(status:400,message:"Unknown filter target.")}
    if target=="pixels" {guard case .raster = layer.content else {throw AutomationFailure(status:422,message:"Filter requires a pixel layer.")}}
    guard let value = parameters["filter"] else { throw AutomationFailure(status: 400, message: "Missing filter.") }
    do {
      let filter=try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject:value.jsonValue,options:.fragmentsAllowed))
      if let mask=MaskFilterTarget(rawValue:target) {return .maskFilter(.init(layerID:id,target:mask,filter:filter))}
      return .applyFilter(id,filter)
    } catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
  }
}
