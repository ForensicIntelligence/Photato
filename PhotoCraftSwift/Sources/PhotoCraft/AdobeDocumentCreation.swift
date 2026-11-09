import CoreGraphics
import Foundation
import PhotoCraftCore

/// The pinned Photoshop v2 ImageParameters subset. Not an execute-actions extension
/// on the Adobe route; Photato's separately versioned action jobs also accept it.
struct AdobeDocumentCreation: Sendable {
  enum Profile: Sendable { case standard(String), custom(URL) }
  let width: Int
  let height: Int
  let depth: PixelDepth
  let mode: DocumentColorMode
  let name: String
  let resolution: Double
  let background: Pixel
  let profile: Profile?
  var resource: URL? { if case .custom(let url) = profile { url } else { nil } }

  init(_ raw: Any) throws {
    typealias Object = AdobeActionsRequest.Object
    let image = try Object(raw, at: "image", allowed: [
      "width", "height", "depth", "mode", "name", "resolution", "fill", "iccProfile", "unit", "pixelScaleFactor",
    ])
    width = try image.integer("width", range: 1...32_000)
    height = try image.integer("height", range: 1...32_000)
    try AdobeActionAssets.checkDimensions(width: width, height: height)
    let modeName = try image.fields["mode"] == nil ? "rgb" : image.string("mode")
    guard let colorMode = DocumentColorMode(rawValue: modeName) else {
      guard ["bitmap", "indexed", "hsb", "duotone", "multichannel"].contains(modeName) else {
        throw AdobeAPIError.invalid("Unknown image.mode.")
      }
      throw AdobeAPIError.unsupported("This document color mode is not implemented.")
    }
    guard DocumentColorMode.componentModes.contains(colorMode) else { throw AdobeAPIError.unsupported("Restricted-mode document creation is still being implemented.") }
    mode = colorMode
    let bits = try image.fields["depth"] == nil ? 8 : image.integer("depth", range: 1...32)
    guard [1, 8, 16, 32].contains(bits) else { throw AdobeAPIError.invalid("image.depth must be 1, 8, 16 or 32.") }
    guard bits != 1 else { throw AdobeAPIError.unsupported("Bitmap creation is not implemented.") }
    depth = bits == 8 ? .u8 : bits == 16 ? .u16 : .f32
    guard mode.depths.contains(depth) else { throw AdobeAPIError.unsupported("CMYK and Lab require 8 or 16 bits.") }
    if image.fields["unit"] != nil {
      let unit = try image.string("unit")
      guard ["pixels_unit", "points_unit", "percent_unit", "distance_unit"].contains(unit) else {
        throw AdobeAPIError.invalid("Unknown image.unit.")
      }
      guard unit == "pixels_unit" else { throw AdobeAPIError.unsupported("Blank document dimensions currently require pixels_unit.") }
    }
    if let raw = image.fields["pixelScaleFactor"] {
      guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
        value.doubleValue.isFinite, value.doubleValue >= 0.1 else {
        throw AdobeAPIError.invalid("image.pixelScaleFactor must be at least 0.1.")
      }
      guard value.doubleValue == 1 else { throw AdobeAPIError.unsupported("Only square-pixel document creation is implemented.") }
    }
    name = try image.fields["name"] == nil ? "Untitled-1" : image.string("name")
    guard name.unicodeScalars.count <= 255 else { throw AdobeAPIError.invalid("image.name exceeds 255 characters.") }
    if image.fields["resolution"] != nil {
      let value = try image.object("resolution", allowed: ["unit", "value"])
      guard try value.string("unit") == "density_unit" else { throw AdobeAPIError.invalid("Resolution requires density_unit.") }
      resolution = Double(try value.fields["value"] == nil ? 72 : value.integer("value", range: 1...100_000))
    } else { resolution = 72 }
    let fill = try image.fields["fill"] == nil ? "white" : image.string("fill")
    guard ["white", "transparent", "background_color"].contains(fill) else { throw AdobeAPIError.invalid("Unknown image.fill.") }
    // Isolated jobs have no mutable desktop foreground/background preference.
    background = fill == "transparent" ? .clear : .white
    if image.fields["iccProfile"] != nil {
      let value = try image.object("iccProfile", allowed: ["type", "name", "source", "imageMode"])
      let type = try value.string("type")
      let title = try value.string("name")
      guard title.unicodeScalars.count <= 255 else { throw AdobeAPIError.invalid("Profile name exceeds 255 characters.") }
      if value.fields["imageMode"] != nil {
        let profileMode = try value.string("imageMode")
        let allowed = type == "custom" ? ["rgb", "grayscale", "cmyk"] : ["rgb", "grayscale"]
        guard allowed.contains(profileMode), profileMode == mode.rawValue else {
          throw AdobeAPIError.invalid("iccProfile.imageMode must match image.mode and its profile variant.")
        }
      }
      switch type {
      case "custom":
        let source = try value.object("source", allowed: ["url"])
        profile = .custom(try AdobeActionsRequest.url(source.string("url"), path: "image.iccProfile.source.url", httpsOnly: false))
      case "standard":
        guard value.fields["source"] == nil else { throw AdobeAPIError.invalid("A standard profile cannot have a source.") }
        let names = ["Adobe RGB (1998)", "Apple RGB", "ColorMatch RGB", "sRGB IEC61966-2.1",
          "Dot Gain 10%", "Dot Gain 15%", "Dot Gain 20%", "Dot Gain 25%", "Dot Gain 30%", "Gray Gamma 1.8", "Gray Gamma 2.2"]
        guard names.contains(title) else { throw AdobeAPIError.invalid("Unknown standard ICC profile.") }
        guard ["Adobe RGB (1998)", "Apple RGB", "sRGB IEC61966-2.1", "Gray Gamma 2.2"].contains(title) else {
          throw AdobeAPIError.unsupported("This named standard ICC profile is not implemented.")
        }
        guard mode == (title == "Gray Gamma 2.2" ? .grayscale : .rgb) else {
          throw AdobeAPIError.invalid("The standard ICC profile does not match image.mode.")
        }
        profile = .standard(title)
      default: throw AdobeAPIError.invalid("iccProfile.type must be standard or custom.")
      }
    } else { profile = nil }
  }

  func document(resources: [URL: Data] = [:]) throws -> CraftDocument {
    try Task.checkCancellation()
    let bytes: Data?
    switch profile {
    case nil: bytes = nil
    case .custom(let url):
      guard let supplied = resources[url], supplied.count <= ICCProfile.maximumBytes else {
        throw AdobeAPIError.invalid("The custom ICC resource is missing or exceeds 4 MiB.")
      }
      // Explicit custom profiles retain their bytes. Nonlinear 32-bit profiles fail
      // rather than being silently changed; named standard profiles are linearized.
      try NativeModeProfile.validate(supplied, mode: mode, depth: depth)
      bytes = supplied
    case .standard(let name):
      if name == "Apple RGB" { bytes = try NativeModeProfile.appleRGB(depth: depth); break }
      let colorName = name == "Adobe RGB (1998)" ? CGColorSpace.adobeRGB1998
        : name == "Gray Gamma 2.2" ? CGColorSpace.genericGrayGamma2_2 : CGColorSpace.sRGB
      guard let standard = CGColorSpace(name: colorName),
        let space = depth == .f32 ? CGColorSpaceCreateLinearized(standard) : standard,
        let data = space.copyICCData() as Data? else {
        throw AdobeAPIError.unsupported("The system ICC profile is unavailable.")
      }
      bytes = data
    }
    let result = try DocumentCreation.blank(width: width, height: height, depth: depth,
      background: background, name: name, mode: mode, profile: bytes, resolution: resolution)
    try AdobeActionAssets.check(result)
    return result
  }

  static var capabilities: [String: Any] { [
    "imageParametersSchema": parameterSchema,
    "adobeRoute": "/v2/create-composite", "photatoRoute": "/v1/action-jobs",
    "image": "ImageParameters replaces image.source; Photato jobs still require options.actions.",
    "modes": ["rgb": [8, 16, 32], "grayscale": [8, 16, 32], "cmyk": [8, 16], "lab": [8, 16]],
    "units": ["pixels_unit"], "pixelScaleFactor": 1, "maximumCanvasPixels": AdobeActionAssets.maximumCanvasPixels,
    "resolution": "density_unit, integer 1–100000, default 72 pixels/inch",
    "fills": ["white", "transparent", "background_color"], "backgroundColor": "White in isolated jobs",
    "standardProfiles": ["sRGB IEC61966-2.1", "Adobe RGB (1998)", "Apple RGB", "Gray Gamma 2.2"],
    "customProfile": "URL source, at most 4 MiB, matching mode; 32-bit profiles must be linear",
    "defaults": "RGB8, white, 72 pixels/inch, Untitled-1; platform default profiles for omitted ICC",
    "limitations": "Restricted modes, other units/scales/named profiles, guide-only solidColor fill, exact Photoshop defaults and pixel/color equivalence remain unsupported or unqualified.",
  ] }

  static var parameterSchema: [String: Any] {
    let url: [String: Any] = ["type": "object", "required": ["url"], "additionalProperties": false,
      "properties": ["url": ["type": "string", "format": "uri", "pattern": "^https?://"]]]
    let profiles: [String: Any] = ["oneOf": [
      ["type": "object", "required": ["type", "name"], "additionalProperties": false, "properties": [
        "type": ["const": "standard"], "name": ["enum": ["sRGB IEC61966-2.1", "Adobe RGB (1998)", "Apple RGB", "Gray Gamma 2.2"]],
        "imageMode": ["enum": ["rgb", "grayscale"]],
      ]],
      ["type": "object", "required": ["type", "name", "source"], "additionalProperties": false, "properties": [
        "type": ["const": "custom"], "name": ["type": "string", "maxLength": 255], "source": url,
        "imageMode": ["enum": ["rgb", "grayscale", "cmyk"]],
      ]],
    ]]
    return ["type": "object", "required": ["width", "height"], "additionalProperties": false,
      "properties": [
        "width": ["type": "integer", "minimum": 1, "maximum": 32_000],
        "height": ["type": "integer", "minimum": 1, "maximum": 32_000],
        "depth": ["type": "integer", "enum": [8, 16, 32], "default": 8],
        "mode": ["enum": DocumentColorMode.componentModes.map(\.rawValue), "default": "rgb"],
        "name": ["type": "string", "maxLength": 255, "default": "Untitled-1"],
        "fill": ["enum": ["white", "transparent", "background_color"], "default": "white"],
        "unit": ["const": "pixels_unit"], "pixelScaleFactor": ["const": 1],
        "resolution": ["type": "object", "required": ["unit"], "additionalProperties": false, "properties": [
          "unit": ["const": "density_unit"], "value": ["type": "integer", "minimum": 1, "maximum": 100_000, "default": 72],
        ]], "iccProfile": profiles,
      ],
      "allOf": [["if": ["required": ["mode"], "properties": ["mode": ["enum": ["cmyk", "lab"]]]],
        "then": ["properties": ["depth": ["enum": [8, 16]]]]]],
      "description": "Runtime constraints: at most 8,000 layers and 128 MiB resident document data; native mode, codec, source and output budgets apply independently. RGB blank canvases retain implicit samples. ICC mode/name/bytes must agree. Named profiles are linearized at 32 bits; custom 32-bit ICC must already be linear.",
    ]
  }
}
