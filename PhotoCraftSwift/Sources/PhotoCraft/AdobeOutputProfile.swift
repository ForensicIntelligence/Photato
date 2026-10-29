import CoreGraphics
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Published PhotoshopOutput.iccProfile; uses the same conversion as the native dialog.
struct AdobeOutputProfile: Hashable, Sendable {
  let name: String
  let resource: URL?
  let imageMode: DocumentColorMode?
  init(_ raw: Any) throws {
    let value = try AdobeActionsRequest.Object(raw, at: "outputs.iccProfile", allowed: ["type", "name", "source", "imageMode"])
    let type = try value.fields["type"] == nil ? "standard" : value.string("type")
    guard ["standard", "custom"].contains(type) else { throw AdobeAPIError.invalid("iccProfile.type must be standard or custom.") }
    name = try value.fields["name"] == nil && type == "standard" ? "sRGB IEC61966-2.1" : value.string("name")
    guard name.unicodeScalars.count <= 255 else { throw AdobeAPIError.invalid("Profile name exceeds 255 characters.") }
    if value.fields["imageMode"] != nil {
      guard let mode = DocumentColorMode(rawValue: try value.string("imageMode")),
        (type == "custom" ? [.rgb, .grayscale, .cmyk] : [.rgb, .grayscale]).contains(mode) else { throw AdobeAPIError.invalid("Invalid output ICC imageMode.") }
      imageMode = mode
    } else { imageMode = nil }
    if type == "custom" {
      let source = try value.object("source", allowed: ["url"])
      resource = try AdobeActionsRequest.url(source.string("url"), path: "outputs.iccProfile.source.url", httpsOnly: false)
    } else {
      guard value.fields["source"] == nil else { throw AdobeAPIError.invalid("A standard profile cannot have a source.") }
      let names = ["Adobe RGB (1998)", "Apple RGB", "ColorMatch RGB", "sRGB IEC61966-2.1", "Dot Gain 10%", "Dot Gain 15%", "Dot Gain 20%", "Dot Gain 25%", "Dot Gain 30%", "Gray Gamma 1.8", "Gray Gamma 2.2"]
      guard names.contains(name) else { throw AdobeAPIError.invalid("Unknown standard ICC profile.") }
      guard ["Adobe RGB (1998)", "sRGB IEC61966-2.1", "Gray Gamma 2.2"].contains(name) else { throw AdobeAPIError.unsupported("This named ICC profile is not available in the native adapter yet.") }
      resource = nil
    }
  }
  func data(resources: [URL: Data], depth: PixelDepth) throws -> Data {
    let bytes: Data
    if let resource {
      guard let data = resources[resource], data.count <= ICCProfile.maximumBytes else { throw AdobeAPIError.invalid("Custom output ICC is missing or exceeds 4 MiB.") }
      bytes = data
    } else {
      let space = name == "Adobe RGB (1998)" ? CGColorSpace.adobeRGB1998 : name == "Gray Gamma 2.2" ? CGColorSpace.genericGrayGamma2_2 : CGColorSpace.sRGB
      guard let data = CGColorSpace(name: space)?.copyICCData() as Data? else { throw AdobeAPIError.unsupported("The standard profile is unavailable.") }
      bytes = try NativeModeProfile.atDepth(data, mode: name == "Gray Gamma 2.2" ? .grayscale : .rgb, depth: depth)
    }
    let mode = try ProofSettings.mode(of: bytes)
    guard mode != .lab, imageMode == nil || imageMode == mode else { throw AdobeAPIError.invalid("Output ICC components do not match imageMode.") }
    try NativeModeProfile.validate(bytes, mode: mode, depth: depth)
    return bytes
  }
  func convert(_ document: CraftDocument, resources: [URL: Data], rasterOutput: Bool) throws -> CraftDocument {
    let profile = try data(resources: resources, depth: document.depth)
    var request = ColorProfileRequest(.convert, profile: profile)
    let destination = try ProofSettings.mode(of: profile)
    request.mergeVisible = rasterOutput && ColorProfileInput.needsMerge(document, destination: destination)
    var result = document
    try ColorProfileInput.command(request, in: document).apply(to: &result)
    return result
  }
}

extension AdobeOutputProfile {
  static var schema: [String: Any] {
    ["oneOf": [
      BrushAPI.object(["type": ["type": "string", "const": "standard", "default": "standard"],
        "name": ["type": "string", "enum": ["sRGB IEC61966-2.1", "Adobe RGB (1998)", "Gray Gamma 2.2"], "default": "sRGB IEC61966-2.1"],
        "imageMode": BrushAPI.enumeration(["rgb", "grayscale"])], required: []),
      BrushAPI.object(["type": ["type": "string", "const": "custom"], "name": ["type": "string", "maxLength": 255],
        "imageMode": BrushAPI.enumeration(["rgb", "grayscale", "cmyk"]),
        "source": BrushAPI.object(["url": ["type": "string", "format": "uri"]], required: ["url"])], required: ["type", "name", "source"])
    ]]
  }
}
