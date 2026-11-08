import Foundation

/// A native interpreter for supported Photoshop actionJSON descriptors. It does
/// not evaluate JavaScript, run plug-ins, or silently skip unsupported actions.
/// The HTTP job/resource adapters decide which documents this may access.
public struct PhotoshopActionProgram: Sendable {
  public enum Step: Equatable, Sendable {
    case selectLayer(String)
    case selectAllLayers
    case imageStack(ImageStackMode)
    case photoAlign(PhotoAlignSettings)
    case photoBlend(PhotoBlendSettings)
    case flattenImage
    case mergeSelected
    case mergeVisible
    case selectComponents(RGBComponents?)
    case selectModeComponent(DocumentColorMode, Int?)
    case convertMode(DocumentColorMode?, PixelDepth?, Bool)
    case fill(value: Float, opacity: Float)
    case filter(RasterFilter)
    case invertComponents
    case colorLookup(ColorLookupAdjustment)
    case adjustment(ClassicAdjustment)
  }

  public struct Result: Sendable {
    public var session: EditorSession
    public let components: RGBComponents?
    public let selectedLayerIDs: Set<UUID>
    public let modeComponents: ModeComponentTarget?
    public init(session: EditorSession, components: RGBComponents?, selectedLayerIDs: Set<UUID>,
      modeComponents: ModeComponentTarget? = nil) {
      self.session = session
      self.components = components
      self.selectedLayerIDs = selectedLayerIDs
      self.modeComponents = modeComponents
    }
  }

  public struct ModeComponentTarget: Equatable, Sendable {
    public let mode: DocumentColorMode
    public let components: Set<Int>
    public init(mode: DocumentColorMode, components: Set<Int>) { self.mode = mode; self.components = components }
  }

  public typealias MergeRenderer = @Sendable (CraftDocument,Set<UUID>,LayerMergeOperation) throws -> Command
  public typealias FlattenRenderer = @Sendable (CraftDocument) throws -> Command
  public typealias StackRenderer = @Sendable (CraftDocument, UUID, ImageStackMode) throws -> Command
  public typealias ModeConverter = @Sendable (CraftDocument, DocumentModeConversion, Bool) throws -> Command
  public let steps: [Step]
  public static let maximumCharacters = 51_200
  public static let maximumSteps = 1_024
  public static var modeCapabilities: [String: Any] { [
    "conversionParametersSchema": modeConversionParameterSchema,
    "channelNameSchema": ["type": "string", "enum": ["RGB", "red", "green", "blue", "gray", "CMYK", "cyan", "magenta", "yellow", "black", "lab", "lightness", "a", "b"]],
    "channels": ["rgb": ["RGB", "red", "green", "blue"], "grayscale": ["gray"],
      "cmyk": ["CMYK", "cyan", "magenta", "yellow", "black"], "lab": ["lab", "lightness", "a", "b"]],
    "componentOperations": ["select", "fill (neutral Normal)", "invert", "supported raster filters"],
    "componentFilterKinds": ModeComponentEdit.filters.map(\.rawValue).sorted(),
    "depths": ["rgb": [8, 16, 32], "grayscale": [8, 16, 32], "cmyk": [8, 16], "lab": [8, 16]],
    "conversion": ["event": "convertMode", "modeEnumeration": "colorSpaceMode",
      "modes": DocumentColorMode.componentModes.map(\.rawValue), "depths": [8, 16, 32],
      "merge": "Optional boolean; false retains supported layers, true converts the visible composite and discards hidden layers."],
    "behavior": "Targets persist between action resources, clear when selecting a layer or converting mode, and must match the current color mode. Fill/invert/filter preserve alpha and untargeted planes and respect selection. CMYK zero view-gray means full ink. RGB8 neutral Fill retains its qualified path. Depth-only conversion retains working-profile primaries, linearizing for32-bit storage.",
    "limitations": "No alpha/spot targets, multi-channel selection modifiers, arbitrary component colors/blends or other component tools. HDR depth reduction requires prior toning. Mode-specific enum references are based on public plugin-author observations; current Photoshop2026 descriptor/pixel/default equivalence and full service conformance remain unqualified.",
  ] }
  public static var modeConversionParameterSchema: [String: Any] { [
    "type": "object", "additionalProperties": false,
    "anyOf": [["required": ["to"]], ["required": ["depth"]]],
    "properties": [
      "to": ["oneOf": [
        ["type": "object", "required": ["_enum", "_value"], "additionalProperties": false,
          "properties": ["_enum": ["const": "colorSpaceMode"], "_value": ["enum": DocumentColorMode.componentModes.map(\.rawValue)]]],
        ["type": "object", "required": ["_class"], "additionalProperties": false,
          "properties": ["_class": ["enum": ["$RGBM", "$Grys", "$CMYM", "$LbCM"]]]],
      ]], "depth": ["type": "integer", "enum": [8, 16, 32]],
      "merge": ["type": "boolean", "default": false],
    ],
    "description": "Canonical parameters for _obj convertMode, excluding shared action metadata. Legacy aliases: $CnvM, $T followed by three spaces, $Dpth, $Mrge. Duplicate canonical/legacy parameters reject. Runtime checks enforce mode/depth/profile/HDR constraints.",
  ] }

  public init(actionJSON: String) throws {
    guard actionJSON.unicodeScalars.count <= Self.maximumCharacters else {
      throw CraftError.invalid("Inline actionJSON exceeds 51,200 characters.")
    }
    let data = Data(actionJSON.utf8)
    try Self.checkNesting(data)
    let values: [ActionValue]
    do { values = try JSONDecoder().decode([ActionValue].self, from: data) } catch {
      throw CraftError.invalid("ActionJSON must be a JSON array of action descriptors.")
    }
    guard !values.isEmpty, values.count <= Self.maximumSteps else {
      throw CraftError.invalid("An action program must contain 1–1,024 steps.")
    }
    steps = try values.enumerated().map { index, value in
      do { return try Self.parse(value) } catch let error as CraftError {
        let message = "Action \(index + 1): \(error.localizedDescription)"
        if case .unsupported = error { throw CraftError.unsupported(message) }
        throw CraftError.invalid(message)
      }
    }
  }

  /// Work on an isolated session. Validation, unsupported contexts, cancellation
  /// and later-step errors never partially replace the caller's document.
  public func applying(to document: CraftDocument, components initial: RGBComponents? = nil,
    modeComponents: ModeComponentTarget? = nil, stackRenderer: StackRenderer? = nil, modeConverter: ModeConverter? = nil, flattenRenderer: FlattenRenderer? = nil, mergeRenderer: MergeRenderer? = nil)
    throws -> Result
  {
    try applying(to: EditorSession(document: document), components: initial,
      modeComponents: modeComponents, stackRenderer: stackRenderer, modeConverter: modeConverter, flattenRenderer: flattenRenderer, mergeRenderer: mergeRenderer)
  }

  /// Continue another action resource without losing its history or target.
  public func applying(
    to original: EditorSession, components initial: RGBComponents? = nil,
    selectedLayerIDs initialLayers: Set<UUID>? = nil, modeComponents initialMode: ModeComponentTarget? = nil,
    stackRenderer: StackRenderer? = nil, modeConverter: ModeConverter? = nil, flattenRenderer: FlattenRenderer? = nil, mergeRenderer: MergeRenderer? = nil
  )
    throws -> Result
  {
    try Task.checkCancellation()
    try original.document.validate()
    if let initial, initial.isEmpty || !initial.isSubset(of: .all) {
      throw CraftError.invalid("Invalid initial component target.")
    }
    if initial != nil && original.document.colorMode != .rgb {
      throw CraftError.unsupported("RGB component targets require an RGB document.")
    }
    if let initialMode {
      guard initial == nil, initialMode.mode != .rgb, initialMode.mode == original.document.colorMode,
        !initialMode.components.isEmpty, initialMode.components.allSatisfy({ (0..<initialMode.mode.componentCount).contains($0) }) else {
        throw CraftError.invalid("Invalid initial mode component target.")
      }
    }
    var session = original
    var components = initial
    var modeComponents = initialMode
    var selectedLayers = initialLayers ?? Set(original.document.activeLayerID.map { [$0] } ?? [])
    guard selectedLayers.isSubset(of: Set(original.document.layers.map(\.id))) else {
      throw CraftError.invalid("Unknown initial layer selection.")
    }
    for step in steps {
      try Task.checkCancellation()
      let hasComponentTarget = components != nil || modeComponents != nil
      switch step {
      case .selectLayer(let name):
        let matches = session.document.layers.filter { $0.name == name }
        guard matches.count == 1 else { throw CraftError.invalid("Layer name must identify exactly one layer.") }
        session.selectLayer(matches[0].id); selectedLayers = [matches[0].id]; components = nil; modeComponents = nil
      case .colorLookup(let value):
        guard !hasComponentTarget, let id = session.document.activeLayerID, selectedLayers == [id], session.document.layers.first(where: { $0.id == id })?.smartObject == nil else { throw CraftError.unsupported("Color Lookup requires a single ordinary RGB pixel layer.") }
        try session.execute(.applyAdjustment(id,.colorLookup(value)))
      case .adjustment(let value):
        guard !hasComponentTarget, let id = session.document.activeLayerID, selectedLayers == [id],
          session.document.layers.first(where: { $0.id == id })?.smartObject == nil else {
          throw CraftError.unsupported("Adjustments require a single ordinary RGB pixel layer.")
        }
        try session.execute(.applyAdjustment(id, .classic(value)))
      case .filter(let filter):
        guard let id = session.document.activeLayerID,
          selectedLayers == [id] else {
          throw CraftError.unsupported("Filters require a single active RGB pixel layer.")
        }
        if hasComponentTarget {
          try session.execute(.modeComponents(.init(layerID: id,
            components: modeComponents?.components ?? Self.indices(components!), operation: .filter(filter))))
        } else { try session.execute(.applyFilter(id, filter)) }
      case .invertComponents:
        guard hasComponentTarget, let id = session.document.activeLayerID, selectedLayers == [id] else {
          throw CraftError.unsupported("This Invert action requires one pixel layer and a color-component target.")
        }
        try session.execute(.modeComponents(.init(layerID: id,
          components: modeComponents?.components ?? Self.indices(components!), operation: .invert)))
      case .imageStack(let mode):
        guard !hasComponentTarget, let id = session.document.activeLayerID, selectedLayers == [id], let stackRenderer else { throw CraftError.unsupported("Stack rendering requires one RGB Smart Object and a native imaging renderer.") }
        try session.execute(stackRenderer(session.document,id,mode))
      case .photoAlign(let settings):
        guard !hasComponentTarget else { throw CraftError.unsupported("Auto-Align requires RGB layers.") }
        let edit = try PhotoAlign.prepare(session.document,layerIDs:selectedLayers,settings:settings)
        try session.execute(.photoAlign(edit));selectedLayers = edit.selectedLayerIDs
      case .photoBlend(let settings):
        guard !hasComponentTarget else { throw CraftError.unsupported("Auto-Blend requires the RGB target.") }
        let edit = try PhotoBlend.prepare(session.document,layerIDs:selectedLayers,settings:settings)
        try session.execute(.photoBlend(edit))
        selectedLayers = edit.selectedLayerIDs
      case .selectAllLayers:
        guard !hasComponentTarget,
          !session.document.layers.contains(where: { $0.isGroup || $0.locked || $0.parentID != nil }
          )
        else {
          throw CraftError.unsupported(
            "Select All Layers currently requires unlocked root layers and the RGB target.")
        }
        selectedLayers = Set(session.document.layers.map(\.id))
      case .flattenImage:
        guard !hasComponentTarget, let flattenRenderer else {throw CraftError.unsupported("Flatten Image requires the composite target and native compositor.")}
        try session.execute(flattenRenderer(session.document))
        selectedLayers = Set(session.document.activeLayerID.map{[$0]} ?? [])
      case .mergeSelected, .mergeVisible:
        guard !hasComponentTarget else {
          throw CraftError.unsupported("Merge requires the RGB target.")
        }
        let operation: LayerMergeOperation =
          step == .mergeVisible ? .visible : selectedLayers.count == 1 ? .down : .selected
        if let mergeRenderer {try session.execute(mergeRenderer(session.document,selectedLayers,operation))}
        else {try session.execute(.mergeLayers(selectedLayers,operation))}
        selectedLayers = Set(session.document.activeLayerID.map { [$0] } ?? [])
      case .selectComponents(let selected):
        guard session.document.colorMode == .rgb else {
          throw CraftError.unsupported("RGB channel descriptors require an RGB document.")
        }
        components = selected
        modeComponents = nil
      case .selectModeComponent(let mode, let component):
        guard mode == session.document.colorMode else {
          throw CraftError.unsupported("The requested channel is absent from this document color mode.")
        }
        components = nil
        modeComponents = component.map { .init(mode: mode, components: [$0]) }
      case .convertMode(let mode, let depth, let merge):
        let before = session.document, targetMode = mode ?? before.colorMode, targetDepth = depth ?? before.depth
        guard targetMode.depths.contains(targetDepth), before.depth != .f32 || targetDepth == .f32 else {
          throw CraftError.unsupported("This conversion requires a supported depth; tone HDR before reducing 32-bit precision.")
        }
        let profile: Data?
        if targetMode == before.colorMode, let retained = before.modeDescriptor?.profile ?? before.workingICC {
          profile = try NativeModeProfile.atDepth(retained, mode: targetMode, depth: targetDepth)
        } else { profile = nil }
        let conversion = DocumentModeConversion(mode: targetMode, depth: targetDepth, profile: profile)
        if let modeConverter { try session.execute(modeConverter(before, conversion, merge)) }
        else {
          guard !merge else { throw CraftError.unsupported("Merge before conversion requires the native compositor.") }
          try session.execute(.documentMode(conversion))
        }
        components = nil; modeComponents = nil
        if merge { selectedLayers = Set(session.document.activeLayerID.map { [$0] } ?? []) }
        else { selectedLayers.formIntersection(Set(session.document.layers.map(\.id))) }
      case .fill(let value, let opacity):
        guard hasComponentTarget else {
          throw CraftError.unsupported(
            "This action adapter requires a color-component target for Fill. Composite RGB Fill is not implemented here yet."
          )
        }
        guard let id = session.document.activeLayerID, selectedLayers == [id] else {
          throw CraftError.invalid("Fill requires an active pixel layer.")
        }
        if let modeComponents {
          try session.execute(.modeComponents(.init(layerID: id, components: modeComponents.components,
            operation: .fill(value, opacity))))
        } else if session.document.depth != .u8 || session.document.hasNativeModeStorage {
          try session.execute(.modeComponents(.init(layerID: id, components: Self.indices(components!),
            operation: .fill(value, opacity))))
        } else { try session.execute(
          .fillComponents(
            id,
            .init(
              components: components!, value: value, opacity: opacity))) }
      }
    }
    try Task.checkCancellation()
    return Result(session: session, components: components, selectedLayerIDs: selectedLayers,
      modeComponents: modeComponents)
  }

  private static func indices(_ channels: RGBComponents) -> Set<Int> {
    Set([RGBComponents.red, .green, .blue].enumerated().compactMap { channels.contains($0.element) ? $0.offset : nil })
  }

  private static func classicAdjustment(_ event: String, fields: [String: ActionValue], metadata: Set<String>) throws -> ClassicAdjustment? {
    let kinds: [String: ClassicAdjustment.Kind] = ["vibrance": .vibrance, "blackAndWhite": .blackWhite, "photoFilter": .photoFilter, "channelMixer": .channelMixer, "selectiveColor": .selectiveColor]
    guard let kind = kinds[event] else { return nil }
    var value = ClassicAdjustment(kind)
    func number(_ object: [String: ActionValue], _ key: String, _ fallback: Int) throws -> Int {
      guard let field = object[key] else { return fallback }
      guard let n = field.number, n.isFinite, n.rounded() == n, abs(n) <= 100_000 else { throw CraftError.invalid("Invalid adjustment percentage: \(key).") }; return Int(n)
    }
    func flag(_ key: String, _ fallback: Bool) throws -> Bool {
      guard let field = fields[key] else { return fallback }
      guard let result = field.boolean else { throw CraftError.invalid("Invalid adjustment flag.") }; return result
    }
    func color(_ raw: ActionValue?) throws -> Pixel {
      guard case .object(let c) = raw, c["_obj"]?.string == "RGBColor" else { throw CraftError.unsupported("Adjustment colors must be RGBColor.") }
      try known(c, keys: ["_obj", "red", "grain", "blue"])
      let values = try ["red", "grain", "blue"].map { k -> Float in
        guard let n = c[k]?.number, n.isFinite, (0...255).contains(n) else { throw CraftError.invalid("Invalid RGB color.") }; return Float(n/255)
      }
      return Pixel(values[0],values[1],values[2])
    }
    switch kind {
    case .exposure: throw CraftError.unsupported("Exposure actionJSON descriptors are not yet qualified; use create-composite Exposure adjustments.")
    case .vibrance:
      try known(fields,keys:metadata.union(["vibrance","saturation"]))
      value.vibrance = try number(fields,"vibrance",0); value.saturation = try number(fields,"saturation",0)
    case .blackWhite:
      let keys = ["red","yellow","grain","cyan","blue","magenta"]
      try known(fields,keys:metadata.union(keys).union(["useTint","tintColor"]))
      for (i,k) in keys.enumerated() { value.weights[i] = try number(fields,k,value.weights[i]) }
      if try flag("useTint",false) { value.tint = try fields["tintColor"] == nil ? ClassicAdjustment.defaultTint : color(fields["tintColor"]) }
      else if fields["tintColor"] != nil { _ = try color(fields["tintColor"]) }
    case .photoFilter:
      try known(fields,keys:metadata.union(["color","density","preserveLuminosity"]))
      value.color = try color(fields["color"]); value.density = try number(fields,"density",25); value.preserveLuminosity = try flag("preserveLuminosity",true)
    case .channelMixer:
      try known(fields,keys:metadata.union(["monochromatic","red","grain","blue","gray"]))
      value.monochrome = try flag("monochromatic",false)
      let keys = value.monochrome ? ["gray"] : ["red","grain","blue"]
      guard !(value.monochrome ? ["red","grain","blue"] : ["gray"]).contains(where: { fields[$0] != nil }) else { throw CraftError.unsupported("Channel Mixer output channels do not match its mode.") }
      for (i,k) in keys.enumerated() {
        guard case .object(let row) = fields[k], row["_obj"]?.string == "channelMatrix" else { throw CraftError.invalid("Missing Channel Mixer output row.") }
        try known(row,keys:["_obj","red","grain","blue","constant"])
        value.matrix[i] = try ["red","grain","blue","constant"].map { try number(row,$0,0) }
      }
    case .selectiveColor:
      try known(fields,keys:metadata.union(["method","colorCorrection"]))
      let method = try enumerated(fields["method"],types:["correctionMethod"])
      guard ["relative","absolute"].contains(method) else { throw CraftError.invalid("Invalid selective color method.") }; value.relative = method == "relative"
      guard case .array(let rows) = fields["colorCorrection"], rows.count <= 9 else { throw CraftError.invalid("Invalid color correction list.") }
      var seen = Set<Int>()
      for raw in rows {
        guard case .object(let row) = raw, row["_obj"]?.string == "colorCorrection" else { throw CraftError.invalid("Invalid color correction.") }
        try known(row,keys:["_obj","colors","cyan","magenta","yellow","black"])
        let name = try enumerated(row["colors"],types:["colors"])
        guard let index = ClassicAdjustment.rangeNames.map({ $0.lowercased() }).firstIndex(of:name), seen.insert(index).inserted else { throw CraftError.invalid("Duplicate or unknown selective range.") }
        value.adjustments[index] = try ["cyan","magenta","yellow","black"].map { try number(row,$0,0) }
      }
    }
    try value.validate(); return value
  }

  private static func parse(_ value: ActionValue) throws -> Step {
    guard case .object(let fields) = value, let event = fields["_obj"]?.string else {
      throw CraftError.invalid("Each descriptor requires an _obj command name.")
    }
    if let options = fields["_options"] {
      guard case .object(let options) = options,
        Set(options.keys).isSubset(of: ["dialogOptions", "suppressProgressBar"]),
        options["dialogOptions"] == nil || options["dialogOptions"]?.string == "silent"
          || options["dialogOptions"]?.string == "dontDisplay",
        options["suppressProgressBar"] == nil || options["suppressProgressBar"]?.boolean != nil
      else {
        throw CraftError.unsupported("Interactive or unknown execution options are unsupported.")
      }
    }
    if let command = fields["_isCommand"], command.boolean == nil {
      throw CraftError.invalid("_isCommand must be boolean.")
    }
    let metadata: Set<String> = ["_obj", "_options", "_isCommand"]
    if event == "colorLookup" {
      try known(fields,keys:metadata.union(["lookupType","LUTFormat","dataOrder","tableOrder","LUT3DFileName","LUT3DFileData","dither"]))
      guard try enumerated(fields["lookupType"],types:["colorLookupType"]) == "3DLUT",
        try enumerated(fields["dataOrder"],types:["colorLookupOrder"]) == "rgbOrder",
        try enumerated(fields["tableOrder"],types:["colorLookupOrder"]) == "bgrOrder",
        let filename = fields["LUT3DFileName"]?.string,
        case .object(let raw) = fields["LUT3DFileData"], Set(raw.keys) == ["_rawData","_data"],
        raw["_rawData"]?.string == "base64", let encoded = raw["_data"]?.string,
        let bytes = Data(base64Encoded:encoded),
        fields["dither"] == nil || fields["dither"]?.boolean != nil else { throw CraftError.unsupported("Color Lookup requires inline base64 LUT data, RGB data order and BGR table order.") }
      let format = ["cube":"LUTFormatCUBE","3dl":"LUTFormat3DL","look":"LUTFormatLOOK"][URL(fileURLWithPath:filename).pathExtension.lowercased()]
      guard let format, try enumerated(fields["LUTFormat"],types:["LUTFormatType"]) == format else { throw CraftError.unsupported("Unsupported LUT format.") }
      return .colorLookup(.init(lut:try ColorLUTFile.read(bytes,name:filename),interpolation:.tetrahedral,dither:fields["dither"]?.boolean ?? true))
    }
    if let adjustment = try classicAdjustment(event, fields: fields, metadata: metadata) { return .adjustment(adjustment) }
    let filterAliases: [String: RasterFilter.Kind] = ["$Avrg": .average, "boxblur": .boxBlur]
    if let kind = filterAliases[event] ?? RasterFilter.Kind(rawValue: event) {
      guard kind != .perspectiveWarp else { throw CraftError.unsupported("Adobe Perspective Warp action descriptors are not implemented. Use Photato filter.apply with plane settings.") }
      guard kind != .puppetWarp else { throw CraftError.unsupported("Adobe Puppet Warp action descriptors are not implemented. Use Photato filter.apply with a pin program.") }
      guard kind != .cameraRaw else { throw CraftError.unsupported("Adobe Camera Raw action descriptors are not supported. Use the published /v2/edit subset or Photato filter.apply.") }
      guard kind != .liquify else { throw CraftError.unsupported("Adobe Liquify mesh descriptors are not supported. Use Photato filter.apply with a Liquify program.") }
      var filter = RasterFilter(kind)
      let parameters = kind.parameters.subtracting(["seed"])
      try known(fields, keys: metadata.union(parameters))
      func number(_ name: String, unit: String? = nil) throws -> Double {
        if let unit {
          guard case .object(let value) = fields[name], Set(value.keys) == ["_unit", "_value"],
            value["_unit"]?.string == unit, let number = value["_value"]?.number else {
            throw CraftError.invalid("\(name) requires \(unit).")
          }
          return number
        }
        guard let number = fields[name]?.number else { throw CraftError.invalid("Missing \(name).") }
        return number
      }
      switch kind {
      case .gaussianBlur, .boxBlur, .highPass: filter.radius = try number("radius", unit: "pixelsUnit")
      case .unsharpMask:
        filter.radius = try number("radius", unit: "pixelsUnit")
        filter.amount = try number("amount", unit: "percentUnit")
        filter.threshold = try number("threshold")
      case .motionBlur:
        filter.angle = try number("angle", unit: "angleUnit")
        filter.distance = try number("distance", unit: "pixelsUnit")
      case .mosaic: filter.cellSize = try number("cellSize", unit: "pixelsUnit")
      case .addNoise:
        filter.amount = try number("amount", unit: "percentUnit")
        guard let monochromatic = fields["monochromatic"]?.boolean else {
          throw CraftError.invalid("Noise requires monochromatic boolean.")
        }
        filter.monochromatic = monochromatic
        switch try enumerated(fields["distribution"], types: ["distribution"]) {
        case "uniformDistribution": filter.distribution = .uniform
        case "gaussianDistribution": filter.distribution = .gaussian
        default: throw CraftError.unsupported("Unknown noise distribution.")
        }
      case .shadowsHighlights:throw CraftError.unsupported("Shadows/Highlights ActionJSON descriptors remain unqualified; use the Photato API.")
      case .blur, .blurMore, .radialBlur, .shapeBlur, .smartBlur, .surfaceBlur, .despeckle, .dustAndScratches, .median, .sharpen, .sharpenEdges, .sharpenMore: throw CraftError.unsupported("These Blur/Noise/Sharpen ActionJSON descriptors are not qualified; use the Photato API.")
      case .customFilter, .hsbHsl, .maximum, .minimum, .offset, .deInterlace, .ntscColors: throw CraftError.unsupported("Other/Video ActionJSON descriptors are not qualified; use the Photato API.")
      case .clouds, .differenceClouds, .fibers, .lensFlare: throw CraftError.unsupported("Render actionJSON descriptors are not qualified; use the Photato API.")
      case .diffuse, .emboss, .extrude, .findEdges, .oilPaint, .solarize, .tiles, .traceContour, .wind: throw CraftError.unsupported("Stylize actionJSON descriptors are not qualified; use the Photato API.")
      case .colorHalftone, .crystallize, .facet, .fragment, .mezzotint, .pointillize: throw CraftError.unsupported("Pixelate actionJSON descriptors are not qualified; use the Photato API.")
      case .displace, .shear, .wave, .pinch, .spherize, .twirl, .ripple, .polarCoordinates, .zigzag: throw CraftError.unsupported("Distortion Photoshop descriptors are not qualified; use the Photato API.")
      case .lightingEffects: throw CraftError.unsupported("Lighting Effects Adobe actionJSON descriptors are not qualified.")
      case .relight: throw CraftError.unsupported("Photato Relight has no published Adobe actionJSON descriptor.")
      case .lensBlur: throw CraftError.unsupported("Lens Blur Photoshop descriptors are not qualified; retain editable settings in Photato format.")
      case .smartSharpen, .reduceNoise: throw CraftError.unsupported("Smart Sharpen / Reduce Noise Photoshop descriptors are not qualified; retain editable settings in Photato format.")
      case .filterGallery: throw CraftError.unsupported("Filter Gallery actionJSON descriptors are not qualified.")
      case .adaptiveWideAngle: throw CraftError.unsupported("Adaptive Wide Angle actionJSON descriptors are not qualified.")
      case .lensCorrection: throw CraftError.unsupported("Lens Correction actionJSON descriptors are not qualified.")
      case .blurGallery: throw CraftError.unsupported("Blur Gallery actionJSON descriptors are not qualified.")
      case .average, .liquify, .cameraRaw, .puppetWarp, .perspectiveWarp: break
      }
      try filter.validate()
      return .filter(filter)
    }
    switch event {
    case "convertMode", "$CnvM":
      try known(fields, keys: metadata.union(["to", "$T   ", "depth", "$Dpth", "merge", "$Mrge"]))
      func field(_ key: String, _ legacy: String) throws -> ActionValue? {
        guard fields[key] == nil || fields[legacy] == nil else { throw CraftError.invalid("Duplicate conversion parameter.") }
        return fields[key] ?? fields[legacy]
      }
      var mode: DocumentColorMode?
      if let raw = try field("to", "$T   ") {
        guard case .object(let target) = raw else { throw CraftError.invalid("Conversion requires a color-mode descriptor.") }
        if Set(target.keys) == ["_class"] {
          let classes: [String: DocumentColorMode] = ["$RGBM": .rgb, "$Grys": .grayscale, "$CMYM": .cmyk, "$LbCM": .lab]
          mode = classes[target["_class"]?.string ?? ""]
        } else if Set(target.keys) == ["_enum", "_value"], target["_enum"]?.string == "colorSpaceMode" {
          mode = DocumentColorMode(rawValue: target["_value"]?.string ?? "")
        }
        guard let mode, DocumentColorMode.componentModes.contains(mode) else { throw CraftError.unsupported("This mode-conversion descriptor is not implemented.") }
      }
      var depth: PixelDepth?
      if let raw = try field("depth", "$Dpth") {
        guard let number = raw.number, [8.0, 16.0, 32.0].contains(number) else {
          throw CraftError.invalid("Conversion depth must be 8, 16 or 32.")
        }
        depth = number == 8 ? .u8 : number == 16 ? .u16 : .f32
      }
      guard mode != nil || depth != nil else { throw CraftError.invalid("Specify a conversion mode or depth.") }
      var merge = false
      if let raw = try field("merge", "$Mrge") {
        guard let value = raw.boolean else { throw CraftError.invalid("Conversion merge must be boolean.") }
        merge = value
      }
      return .convertMode(mode, depth, merge)
    case "invert":
      try known(fields, keys: metadata)
      return .invertComponents
    case "flattenImage", "$FltI":
      try known(fields, keys: metadata)
      return .flattenImage
    case "mergeLayersNew", "$Mrg2":
      try known(fields, keys: metadata)
      return .mergeSelected
    case "mergeVisible", "$MrgV":
      try known(fields, keys: metadata)
      return .mergeVisible
    case "selectAllLayers":
      try known(fields, keys: metadata.union(["_target", "null"]))
      guard (fields["_target"] == nil) != (fields["null"] == nil),
        case .array(let targets) = fields["_target"] ?? fields["null"], targets.count == 1,
        case .object(let target) = targets[0], Set(target.keys) == ["_ref", "_enum", "_value"],
        ["layer", "$Lyr "].contains(target["_ref"]?.string ?? ""),
        ["ordinal", "$Ordn"].contains(target["_enum"]?.string ?? ""),
        ["targetEnum", "$Trgt"].contains(target["_value"]?.string ?? "")
      else { throw CraftError.unsupported("Select All Layers requires the current layer target.") }
      return .selectAllLayers
    case "select", "$slct":
      try known(fields, keys: metadata.union(["_target", "null"]))
      if case .array(let targets) = fields["_target"], targets.count == 1,
        case .object(let target) = targets[0], target["_ref"]?.string == "layer" {
        guard fields["null"] == nil, Set(target.keys) == ["_ref", "_name"],
          let name = target["_name"]?.string, !name.isEmpty, name.utf8.count <= 1024 else {
          throw CraftError.unsupported("Layer selection requires an exact name reference.")
        }
        return .selectLayer(name)
      }
      guard (fields["_target"] == nil) != (fields["null"] == nil),
        case .array(let targets) = fields["_target"] ?? fields["null"],
        (1...2).contains(targets.count), case .object(let target) = targets[0],
        Set(target.keys) == ["_ref", "_enum", "_value"],
        ["channel", "$Chnl"].contains(target["_ref"]?.string ?? ""),
        ["channel", "$Chnl"].contains(target["_enum"]?.string ?? "")
      else {
        throw CraftError.unsupported("Select requires an enumerated color-channel reference.")
      }
      if targets.count == 2 {
        guard case .object(let parent) = targets[1],
          Set(parent.keys) == ["_ref", "_enum", "_value"],
          ["document", "$Dcmn"].contains(parent["_ref"]?.string ?? ""),
          ["ordinal", "$Ordn"].contains(parent["_enum"]?.string ?? ""),
          ["targetEnum", "$Trgt"].contains(parent["_value"]?.string ?? "")
        else { throw CraftError.unsupported("Only the current input document can be selected.") }
      }
      switch target["_value"]?.string {
      case "RGB", "$RGB ": return .selectComponents(nil)
      case "red", "$Rd  ": return .selectComponents(.red)
      case "green", "$Grn ": return .selectComponents(.green)
      case "blue", "$Bl  ": return .selectComponents(.blue)
      case "gray", "$Gry ": return .selectModeComponent(.grayscale, 0)
      case "CMYK": return .selectModeComponent(.cmyk, nil)
      case "cyan": return .selectModeComponent(.cmyk, 0)
      case "magenta": return .selectModeComponent(.cmyk, 1)
      case "yellow": return .selectModeComponent(.cmyk, 2)
      case "black": return .selectModeComponent(.cmyk, 3)
      case "lab": return .selectModeComponent(.lab, nil)
      case "lightness": return .selectModeComponent(.lab, 0)
      case "a": return .selectModeComponent(.lab, 1)
      case "b": return .selectModeComponent(.lab, 2)
      default: throw CraftError.unsupported("This channel reference is not implemented.")
      }
    case "applyImageStackPluginRenderer":
      try known(fields,keys:metadata.union(["imageStackPlugin","name","$Nm  "]))
      guard case .object(let plugin) = fields["imageStackPlugin"],Set(plugin.keys) == ["_class"],let code = plugin["_class"]?.string else { throw CraftError.invalid("Image stack renderer requires a plugin class descriptor.") }
      let modes: [String:ImageStackMode] = ["$avrg":.mean,"$summ":.summation,"$minn":.minimum,"$maxx":.maximum,"$medn":.median,"$vari":.variance,"$stdv":.standardDeviation,"$skew":.skewness,"$kurt":.kurtosis,"$rang":.range,"$entr":.entropy]
      guard let mode = modes[code] else { throw CraftError.unsupported("Unknown image statistics plugin class.") }
      for key in ["name","$Nm  "] where fields[key] != nil { guard fields[key]?.string != nil else { throw CraftError.invalid("Image statistics name must be text.") } }
      return .imageStack(mode)
    case "$Algn":
      try known(fields,keys:metadata.union(["_target","null","$Usng","$Aply"]))
      guard (fields["_target"] == nil) != (fields["null"] == nil),
        case .array(let targets) = fields["_target"] ?? fields["null"],targets.count == 1,
        case .object(let target) = targets[0],Set(target.keys) == ["_ref","_enum","_value"],
        ["layer","$Lyr "].contains(target["_ref"]?.string ?? ""),
        ["ordinal","$Ordn"].contains(target["_enum"]?.string ?? ""),
        ["targetEnum","$Trgt"].contains(target["_value"]?.string ?? ""),
        try enumerated(fields["$Usng"],types:["$ADSt"]) == "ADSContent"
      else { throw CraftError.unsupported("Auto-Align requires the current layers and content alignment.") }
      let value = try enumerated(fields["$Aply"],types:["projection"])
      let projections: [String:PhotoAlignSettings.Projection] = ["$Auto":.auto,"$Prsp":.perspective,"cylindrical":.cylindrical,"spherical":.spherical,"sceneCollage":.collage,"translation":.reposition]
      guard let value,let projection = projections[value] else { throw CraftError.unsupported("Unsupported Auto-Align projection descriptor.") }
      var settings = PhotoAlignSettings();settings.projection = projection;return .photoAlign(settings)
    case "mergeAlignedLayers":
      try known(fields,keys:metadata.union(["$Aply","$ClrC","autoTransparencyFill"]))
      guard try enumerated(fields["$Aply"],types:["autoBlendType"]) == "panorama" else {
        throw CraftError.unsupported("Only the installed panorama Auto-Blend action descriptor is qualified.")
      }
      guard let seamless = fields["$ClrC"]?.boolean,let fill = fields["autoTransparencyFill"]?.boolean else {
        throw CraftError.invalid("Auto-Blend requires explicit color-correction and transparency-fill booleans.")
      }
      var settings = PhotoBlendSettings();settings.seamlessTones = seamless;settings.fillTransparentAreas = fill
      return .photoBlend(settings)
    case "fill", "$Fl  ":
      try known(
        fields,
        keys: metadata.union([
          "using", "$Usng", "opacity", "$Opct", "mode", "$Md  ",
          "preserveTransparency", "$PrsT",
        ]))
      let contents = try alias(fields, "using", "$Usng")
      let mode = try alias(fields, "mode", "$Md  ")
      let opacity = try alias(fields, "opacity", "$Opct")
      let preserve = try alias(fields, "preserveTransparency", "$PrsT")
      guard case .object(let opacity) = opacity,
        Set(opacity.keys) == ["_unit", "_value"],
        ["percentUnit", "$#Prc"].contains(opacity["_unit"]?.string ?? ""),
        let amount = opacity["_value"]?.number, amount.isFinite, (0...100).contains(amount)
      else { throw CraftError.invalid("Fill requires an opacity in percent from 0 through 100.") }
      guard
        try enumerated(mode, types: ["blendMode", "$BlnM"]).map({
          ["normal", "$Nrml"].contains($0)
        }) == true
      else { throw CraftError.unsupported("Only Normal component Fill is implemented.") }
      if let preserve {
        guard preserve.boolean != nil else {
          throw CraftError.invalid("preserveTransparency must be boolean.")
        }
        // Component Fill always preserves alpha, but this option has not been
        // independently qualified when explicitly requested in actionJSON.
        guard preserve.boolean == false else {
          throw CraftError.unsupported(
            "Explicit Preserve Transparency actions are not qualified yet.")
        }
      }
      let value: Float
      switch try enumerated(contents, types: ["fillContents", "$FlCn"]) {
      case "white", "$Wht ": value = 1
      case "black", "$Blck": value = 0
      case "gray50", "$Gry ": value = 0.5
      default:
        throw CraftError.unsupported(
          "Only White, Black and 50% Gray component Fill are implemented.")
      }
      return .fill(value: value, opacity: Float(amount / 100))
    default: throw CraftError.unsupported("The \(event) action is not implemented.")
    }
  }

  private static func known(_ object: [String: ActionValue], keys: Set<String>) throws {
    guard Set(object.keys).isSubset(of: keys) else {
      throw CraftError.unsupported("Unknown action parameters cannot be ignored.")
    }
  }

  private static func alias(_ object: [String: ActionValue], _ name: String, _ code: String)
    throws -> ActionValue?
  {
    guard object[name] == nil || object[code] == nil else {
      throw CraftError.invalid("Duplicate parameter aliases for \(name).")
    }
    return object[name] ?? object[code]
  }

  private static func enumerated(_ value: ActionValue?, types: Set<String>) throws -> String? {
    guard case .object(let object) = value, Set(object.keys) == ["_enum", "_value"],
      let type = object["_enum"]?.string, types.contains(type),
      let value = object["_value"]?.string
    else { throw CraftError.invalid("Invalid action enumeration.") }
    return value
  }

  private static func checkNesting(_ data: Data) throws {
    var depth = 0
    var quoted = false
    var escaped = false
    for byte in data {
      if quoted {
        if escaped {
          escaped = false
        } else if byte == 92 {
          escaped = true
        } else if byte == 34 {
          quoted = false
        }
      } else if byte == 34 {
        quoted = true
      } else if byte == 123 || byte == 91 {
        depth += 1
        guard depth <= 64 else { throw CraftError.invalid("ActionJSON nesting exceeds 64 levels.") }
      } else if byte == 125 || byte == 93 {
        depth -= 1
      }
    }
  }
}

private indirect enum ActionValue: Decodable, Sendable {
  case object([String: Self])
  case array([Self])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() {
      self = .null
    } else if let b = try? value.decode(Bool.self) {
      self = .bool(b)
    } else if let n = try? value.decode(Double.self) {
      self = .number(n)
    } else if let s = try? value.decode(String.self) {
      self = .string(s)
    } else if let a = try? value.decode([Self].self) {
      self = .array(a)
    } else {
      self = .object(try value.decode([String: Self].self))
    }
  }
  var string: String? { if case .string(let value) = self { value } else { nil } }
  var number: Double? { if case .number(let value) = self { value } else { nil } }
  var boolean: Bool? { if case .bool(let value) = self { value } else { nil } }
}
