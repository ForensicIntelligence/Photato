import Foundation

/// Native raster filters. Numerical Photoshop matching is a separate qualification;
/// Gaussian uses three running-box passes and Motion Blur uses bounded line sampling.
public struct RasterFilter: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case shadowsHighlights, blur, blurMore, radialBlur, shapeBlur, smartBlur, surfaceBlur, despeckle, dustAndScratches, median, sharpen, sharpenEdges, sharpenMore, customFilter, hsbHsl, maximum, minimum, offset, deInterlace, ntscColors, clouds, differenceClouds, fibers, lensFlare, diffuse, emboss, extrude, findEdges, oilPaint, solarize, tiles, traceContour, wind, colorHalftone, crystallize, facet, fragment, mezzotint, pointillize, displace, shear, wave, pinch, spherize, twirl, ripple, polarCoordinates, zigzag, gaussianBlur, boxBlur, motionBlur, unsharpMask, highPass, addNoise, mosaic, average, liquify, cameraRaw, puppetWarp, perspectiveWarp, blurGallery, lensCorrection, adaptiveWideAngle, filterGallery, smartSharpen, reduceNoise, lensBlur
    public var title: String {
      switch self {
      case .shadowsHighlights:"Shadows/Highlights"
      case .blur: "Blur"
      case .blurMore: "Blur More"
      case .radialBlur: "Radial Blur"
      case .shapeBlur: "Shape Blur"
      case .smartBlur: "Smart Blur"
      case .surfaceBlur: "Surface Blur"
      case .despeckle: "Despeckle"
      case .dustAndScratches: "Dust & Scratches"
      case .median: "Median"
      case .sharpen: "Sharpen"
      case .sharpenEdges: "Sharpen Edges"
      case .sharpenMore: "Sharpen More"

      case .customFilter: "Custom"
      case .hsbHsl: "HSB/HSL"
      case .maximum: "Maximum"
      case .minimum: "Minimum"
      case .offset: "Offset"
      case .deInterlace: "De-Interlace"
      case .ntscColors: "NTSC Colors"

            case .clouds: "Clouds"
      case .differenceClouds: "Difference Clouds"
      case .fibers: "Fibers"
      case .lensFlare: "Lens Flare"
      case .diffuse: "Diffuse"
case .emboss: "Emboss"
case .extrude: "Extrude"
case .findEdges: "Find Edges"
case .oilPaint: "Oil Paint"
case .solarize: "Solarize"
case .tiles: "Tiles"
case .traceContour: "Trace Contour"
case .wind: "Wind"
      case .colorHalftone: "Color Halftone"
case .crystallize: "Crystallize"
case .facet: "Facet"
case .fragment: "Fragment"
case .mezzotint: "Mezzotint"
case .pointillize: "Pointillize"
      case .displace: "Displace"
      case .shear: "Shear"
      case .wave: "Wave"
      case .pinch: "Pinch"
      case .spherize: "Spherize"
      case .twirl: "Twirl"
      case .ripple: "Ripple"
      case .polarCoordinates: "Polar Coordinates"
      case .zigzag: "ZigZag"

      case .gaussianBlur: "Gaussian Blur"
      case .boxBlur: "Box Blur"
      case .motionBlur: "Motion Blur"
      case .unsharpMask: "Unsharp Mask"
      case .highPass: "High Pass"
      case .addNoise: "Add Noise"
      case .mosaic: "Mosaic"
      case .average: "Average"
      case .cameraRaw: "Camera Raw Filter"
      case .puppetWarp: "Puppet Warp"
      case .lensBlur: "Lens Blur"
      case .smartSharpen: "Smart Sharpen"
      case .reduceNoise: "Reduce Noise"
      case .filterGallery: "Filter Gallery"
      case .adaptiveWideAngle: "Adaptive Wide Angle"
      case .lensCorrection: "Lens Correction"
      case .blurGallery: "Blur Gallery"
      case .perspectiveWarp: "Perspective Warp"
      case .liquify: "Liquify"
      }
    }
    public var parameters: Set<String> {
      switch self {
      case .shadowsHighlights:["tone"]
      case .blur, .blurMore, .radialBlur, .shapeBlur, .smartBlur, .surfaceBlur, .despeckle, .dustAndScratches, .median, .sharpen, .sharpenEdges, .sharpenMore: ["classicDetail"]
      case .customFilter, .hsbHsl, .maximum, .minimum, .offset, .deInterlace, .ntscColors: ["otherVideo"]
      case .clouds, .differenceClouds, .fibers, .lensFlare: ["render"]
      case .diffuse, .emboss, .extrude, .oilPaint, .tiles, .traceContour, .wind: ["stylize"]
      case .findEdges, .solarize: []
      case .colorHalftone, .crystallize, .mezzotint, .pointillize: ["pixelate"]
      case .facet, .fragment: []
      case .displace, .shear, .wave, .pinch, .spherize, .twirl, .ripple, .polarCoordinates, .zigzag: ["distortion"]
      case .gaussianBlur, .boxBlur, .highPass: ["radius"]
      case .motionBlur: ["angle", "distance"]
      case .unsharpMask: ["radius", "amount", "threshold"]
      case .addNoise: ["amount", "distribution", "monochromatic", "seed"]
      case .mosaic: ["cellSize"]
      case .average: []
      case .cameraRaw: ["cameraRaw"]
      case .puppetWarp: ["puppet"]
      case .lensBlur: ["lensBlur"]
      case .smartSharpen: ["sharpen"]
      case .reduceNoise: ["denoise"]
      case .filterGallery: ["artistic"]
      case .adaptiveWideAngle: ["wideAngle"]
      case .lensCorrection: ["lens"]
      case .blurGallery: ["gallery"]
      case .perspectiveWarp: ["perspective"]
      case .liquify: ["liquify"]
      }
    }
  }
  public enum Distribution: String, Codable, CaseIterable, Sendable { case uniform, gaussian }
  public var tone:ClassicToneSettings?
  public var classicDetail: ClassicDetailSettings?
  public var otherVideo: OtherVideoSettings?
  public var renderSettings: RenderSettings?
  public var stylize: StylizeSettings?
  public var pixelate: PixelateSettings?
  public var distortion: DistortionSettings?
  public var lensBlur: LensBlurSettings?
  public var sharpen: SmartSharpenSettings?
  public var denoise: ReduceNoiseSettings?
  public var artistic: ArtisticGallerySettings?
  public var wideAngle: WideAngleSettings?
  public var lens: LensCorrectionSettings?
  public var gallery: BlurGallerySettings?
  public var puppet: PuppetSettings?
  public var perspective: PerspectiveSettings?
  public var liquify: LiquifySettings?
  public var cameraRaw: CameraRawSettings?
  public var kind: Kind
  public var radius: Double = 5
  public var amount: Double = 50
  public var threshold: Double = 0
  public var angle: Double = 0
  public var distance: Double = 10
  public var cellSize: Double = 10
  public var monochromatic = true
  public var distribution: Distribution = .uniform
  public var seed: UInt32 = 1
  public init(_ kind: Kind) {
    self.kind = kind
    if kind == .shadowsHighlights {tone=ClassicToneSettings(.shadowsHighlights)}
    if kind.isClassicDetail {classicDetail=ClassicDetailSettings(kind:kind)}
    if kind.isOtherVideo {otherVideo=OtherVideoSettings()}
    if kind.isRender {renderSettings=RenderSettings(kind:kind)}
    if kind.isStylize {stylize=StylizeSettings(kind:kind)}
    if kind.isPixelate { pixelate = PixelateSettings(kind:kind) }
    if kind.isDistortion { distortion = DistortionSettings(kind:kind) }
    if kind == .lensBlur { lensBlur = LensBlurSettings() }
    if kind == .smartSharpen { sharpen = SmartSharpenSettings() }
    if kind == .reduceNoise { denoise = ReduceNoiseSettings() }
    if kind == .filterGallery { artistic = ArtisticGallerySettings() }
    if kind == .adaptiveWideAngle { wideAngle = WideAngleSettings() }
    if kind == .lensCorrection { lens = LensCorrectionSettings() }
    if kind == .blurGallery { gallery = BlurGallerySettings() }
    if kind == .cameraRaw { cameraRaw = CameraRawSettings() }
    if kind == .puppetWarp { puppet = PuppetSettings() }
    if kind == .perspectiveWarp { perspective = PerspectiveSettings() }
    if kind == .liquify { liquify = LiquifySettings() }
    if kind == .addNoise { amount = 10 }
    if kind == .unsharpMask { radius = 1 }
  }
  public func validate() throws {
    func range(_ value: Double, _ bounds: ClosedRange<Double>, _ name: String, integer: Bool = false) throws {
      guard value.isFinite, bounds.contains(value), !integer || value.rounded() == value else {
        throw CraftError.invalid("Invalid \(name) for \(kind.title).")
      }
    }
    guard kind == .shadowsHighlights || tone==nil else{throw CraftError.invalid("Tone settings require Shadows/Highlights.")}
    guard kind.isClassicDetail || classicDetail == nil else {throw CraftError.invalid("Blur/Noise/Sharpen settings require a matching filter.")}
    guard kind.isOtherVideo || otherVideo == nil else {throw CraftError.invalid("Other/Video settings require a matching filter.")}
    guard kind.isRender || renderSettings == nil else {throw CraftError.invalid("Render settings require a Render filter.")}
    guard kind.isStylize || stylize == nil else {throw CraftError.invalid("Stylize settings require a Stylize filter.")}
    guard kind.isPixelate || pixelate == nil else { throw CraftError.invalid("Pixelate settings require a Pixelate filter.") }
    guard kind.isDistortion || distortion == nil else { throw CraftError.invalid("Distortion settings require a distortion filter.") }
    guard kind == .lensBlur || lensBlur == nil else { throw CraftError.invalid("Lens Blur settings require Lens Blur.") }
    guard kind == .smartSharpen || sharpen == nil else { throw CraftError.invalid("Sharpen settings require Smart Sharpen.") }
    guard kind == .reduceNoise || denoise == nil else { throw CraftError.invalid("Denoise settings require Reduce Noise.") }
    guard kind == .filterGallery || artistic == nil else { throw CraftError.invalid("Artistic settings require Filter Gallery.") }
    guard kind == .adaptiveWideAngle || wideAngle == nil else { throw CraftError.invalid("Wide Angle settings require Adaptive Wide Angle.") }
    guard kind == .lensCorrection || lens == nil else { throw CraftError.invalid("Lens settings require Lens Correction.") }
    guard kind == .blurGallery || gallery == nil else { throw CraftError.invalid("Gallery settings require Blur Gallery.") }
    guard kind == .perspectiveWarp || perspective == nil else { throw CraftError.invalid("Perspective settings require Perspective Warp.") }
    guard kind == .puppetWarp || puppet == nil else { throw CraftError.invalid("Puppet settings require Puppet Warp.") }
    guard kind == .cameraRaw || cameraRaw == nil else { throw CraftError.invalid("Camera Raw settings require a Camera Raw filter.") }
    guard kind == .liquify || liquify == nil else { throw CraftError.invalid("Liquify settings require a Liquify filter.") }
    switch kind {
    case .shadowsHighlights:guard let tone,tone.kind == .shadowsHighlights else{throw CraftError.invalid("Missing Shadows/Highlights settings.")};try tone.validate()
    case .blur, .blurMore, .radialBlur, .shapeBlur, .smartBlur, .surfaceBlur, .despeckle, .dustAndScratches, .median, .sharpen, .sharpenEdges, .sharpenMore:
      guard let classicDetail else {throw CraftError.invalid("Missing Blur/Noise/Sharpen settings.")};try classicDetail.validate(kind:kind)
    case .customFilter, .hsbHsl, .maximum, .minimum, .offset, .deInterlace, .ntscColors:
      guard let otherVideo else {throw CraftError.invalid("Missing Other/Video settings.")};try otherVideo.validate(kind:kind)
    case .clouds, .differenceClouds, .fibers, .lensFlare:
      guard let renderSettings else {throw CraftError.invalid("Missing Render settings.")};try renderSettings.validate(kind:kind)
    case .diffuse, .emboss, .extrude, .findEdges, .oilPaint, .solarize, .tiles, .traceContour, .wind:
      guard let stylize else {throw CraftError.invalid("Missing Stylize settings.")};try stylize.validate(kind:kind)
    case .colorHalftone, .crystallize, .facet, .fragment, .mezzotint, .pointillize:
      guard let pixelate else {throw CraftError.invalid("Missing Pixelate settings.")};try pixelate.validate(kind:kind)
    case .displace, .shear, .wave, .pinch, .spherize, .twirl, .ripple, .polarCoordinates, .zigzag:
      guard let distortion else { throw CraftError.invalid("Missing distortion settings.") };try distortion.validate(kind:kind)
    case .lensBlur:
      guard let lensBlur else { throw CraftError.invalid("Missing Lens Blur settings.") };try lensBlur.validate()
    case .smartSharpen:
      guard let sharpen else { throw CraftError.invalid("Missing Smart Sharpen settings.") };try sharpen.validate()
    case .reduceNoise:
      guard let denoise else { throw CraftError.invalid("Missing Reduce Noise settings.") };try denoise.validate()
    case .filterGallery:
      guard let artistic else { throw CraftError.invalid("Missing Filter Gallery settings.") };try artistic.validate()
    case .adaptiveWideAngle:
      guard let wideAngle else { throw CraftError.invalid("Missing Wide Angle settings.") };try wideAngle.validate()
    case .lensCorrection:
      guard let lens else { throw CraftError.invalid("Missing Lens Correction settings.") };try lens.validate()
    case .blurGallery:
      guard let gallery else { throw CraftError.invalid("Missing Blur Gallery settings.") };try gallery.validate()
    case .perspectiveWarp:
      guard let perspective else { throw CraftError.invalid("Missing Perspective Warp settings.") };try perspective.validate()
    case .puppetWarp:
      guard let puppet else { throw CraftError.invalid("Missing Puppet Warp settings.") }; try puppet.validate()
    case .cameraRaw:
      guard let cameraRaw else { throw CraftError.invalid("Missing Camera Raw settings.") }; try cameraRaw.validate()
    case .liquify:
      guard let liquify else { throw CraftError.invalid("Missing Liquify settings.") }; try liquify.validate()
    case .boxBlur: try range(radius, 1...1000, "radius", integer: true)
    case .gaussianBlur, .highPass: try range(radius, 0.1...1000, "radius")
    case .unsharpMask:
      try range(radius, 0.1...1000, "radius")
      try range(amount, 1...500, "amount")
      try range(threshold, 0...255, "threshold", integer: true)
    case .motionBlur:
      try range(angle, -360...360, "angle")
      try range(distance, 1...2000, "distance", integer: true)
    case .mosaic: try range(cellSize, 2...200, "cell size", integer: true)
    case .addNoise: try range(amount, 0.1...400, "amount")
    case .average: break
    }
  }
  /// Strict public API decoding with optional parameters defaulting as in the UI.
  public static func decodeJSON(_ data: Data) throws -> Self {
    guard let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let text = fields["kind"] as? String, let kind = Kind(rawValue: text),
      Set(fields.keys).isSubset(of: kind.parameters.union(["kind"]))
    else { throw CraftError.invalid("Unknown filter kind or parameter.") }
    var result = Self(kind)
    for (name, value) in fields where name != "kind" {
      if name == "tone" {result.tone=try ClassicToneSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed),kind:.shadowsHighlights)} else if name == "classicDetail" {result.classicDetail=try ClassicDetailSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed),kind:kind)} else if name == "otherVideo" {result.otherVideo=try OtherVideoSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed),kind:kind)} else if name == "render" {result.renderSettings=try RenderSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed),kind:kind)} else if name == "stylize" {result.stylize=try StylizeSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed),kind:kind)} else if name == "pixelate" {
        result.pixelate = try PixelateSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed),kind:kind)
      } else if name == "distortion" {
        result.distortion = try DistortionSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed),kind:kind)
      } else if name == "lensBlur" {
        result.lensBlur = try LensBlurSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed))
      } else if name == "sharpen" {
        result.sharpen = try SmartSharpenSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed))
      } else if name == "denoise" {
        result.denoise = try ReduceNoiseSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed))
      } else if name == "artistic" {
        result.artistic = try ArtisticGallerySettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed))
      } else if name == "wideAngle" {
        result.wideAngle = try WideAngleSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed))
      } else if name == "lens" {
        result.lens = try LensCorrectionSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed))
      } else if name == "gallery" {
        result.gallery = try BlurGallerySettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed))
      } else if name == "perspective" {
        result.perspective = try PerspectiveSettings.decodeJSON(JSONSerialization.data(withJSONObject:value,options:.fragmentsAllowed))
      } else if name == "puppet" {
        result.puppet = try PuppetSettings.decodeJSON(JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed))
      } else if name == "cameraRaw" {
        result.cameraRaw = try CameraRawSettings.decodeJSON(JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed))
      } else if name == "liquify" {
        result.liquify = try LiquifySettings.decodeJSON(JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed))
      } else if name == "distribution" {
        guard let text = value as? String, let distribution = Distribution(rawValue: text) else {
          throw CraftError.invalid("Invalid noise distribution.")
        }
        result.distribution = distribution
      } else if name == "monochromatic" {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
          throw CraftError.invalid("monochromatic must be boolean.")
        }
        result.monochromatic = number.boolValue
      } else {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
          throw CraftError.invalid("\(name) must be numeric.")
        }
        let v = number.doubleValue
        switch name {
        case "radius": result.radius = v
        case "amount": result.amount = v
        case "threshold": result.threshold = v
        case "angle": result.angle = v
        case "distance": result.distance = v
        case "cellSize": result.cellSize = v
        case "seed":
          guard v.isFinite, (0...Double(UInt32.max)).contains(v), v.rounded() == v else {
            throw CraftError.invalid("Invalid noise seed.")
          }
          result.seed = UInt32(v)
        default: throw CraftError.invalid("Unknown filter parameter.")
        }
      }
    }
    try result.validate()
    return result
  }
}
