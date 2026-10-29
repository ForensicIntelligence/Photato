import Foundation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging

/// Pinned v2 EditRequest / LightroomEdits light/color/effects/detail subset.
/// The request contract is supported; Adobe Camera Raw numerical parity is not.
struct AdobeColorEditRequest: Sendable {
  let settings: CameraRawSettings
  let request: AdobeActionsRequest
  let input: URL
  init(data: Data) throws {
    guard data.count <= AdobeActionsRequest.maximumBodyBytes else { throw AdobeAPIError.invalid("Edit request exceeds 4 MiB.") }
    let raw: Any
    do { raw = try JSONSerialization.jsonObject(with:data) }
    catch { throw AdobeAPIError(status:400,code:"invalid_json",message:"Expected a JSON object.") }
    let root = try AdobeActionsRequest.Object(raw,at:"request",allowed:["image","edits","outputs"])
    var value = CameraRawSettings()
    if root.fields["edits"] != nil {
      let edits = try root.object("edits",allowed:["light","color","effects","noiseReduction","sharpness","sharpen"])
      let mappings: [(String,[String:String])] = [
        ("light",["exposure":"exposure","contrast":"contrast","highlights":"highlights","shadows":"shadows","whites":"whites","blacks":"blacks"]),
        ("color",["saturation":"saturation","vibrance":"vibrance"]),
        ("effects",["texture":"texture","clarity":"clarity","dehaze":"dehaze","vignette":"vignetteAmount"]),
        ("noiseReduction",["color":"noiseColor","luminance":"noiseLuminance"]),
        ("sharpen",["detail":"sharpenDetail","edgeMasking":"sharpenMasking","radius":"sharpenRadius"])]
      for (group,mapping) in mappings where edits.fields[group] != nil {
        let object = try edits.object(group,allowed:Set(mapping.keys))
        for (key,target) in mapping where object.fields[key] != nil {
          let control = CameraRawSettings.controls.first { $0.key == target }!
          guard let n = object.fields[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
            (Double(control.minimum)...Double(control.maximum)).contains(n.doubleValue),
            key == "exposure" || key == "radius" || n.doubleValue.rounded() == n.doubleValue else { throw AdobeAPIError.invalid("Invalid edits.\(group).\(key).") }
          value[target] = n.floatValue
        }
      }
      if edits.fields["sharpness"] != nil { value.sharpenAmount = Float(try edits.integer("sharpness",range:0...150)) }
    }
    try value.validate(); settings = value
    let outputs = try root.array("outputs",count:1...25)
    for raw in outputs {
      let output = try AdobeActionsRequest.Object(raw,at:"outputs",allowed:["mediaType","destination","compression","quality"])
      guard ["image/png","image/jpeg"].contains(try output.string("mediaType")), output.fields["destination"] != nil else { throw AdobeAPIError.unsupported("Edit supports PNG or JPEG output with a destination.") }
    }
    let action: [[String:Any]] = [["_obj":"vibrance","vibrance":0,"saturation":0]]
    let content = String(decoding:try JSONSerialization.data(withJSONObject:action),as:UTF8.self)
    var adapter: [String:Any] = ["options":["actions":[["source":["contentType":"application/json","content":content]]]],"outputs":outputs]
    adapter["image"] = root.fields["image"]
    request = try AdobeActionsRequest(data:JSONSerialization.data(withJSONObject:adapter))
    guard let source = request.input else { throw AdobeAPIError.invalid("Edit requires an image source.") }
    input = source
  }
  func execute(input data: Data) throws -> [AdobeActionAssets.Encoded] {
    guard data.count <= AdobeActionAssets.maximumResourceBytes else { throw AdobeAPIError.invalid("Input exceeds 64 MiB.") }
    let source: CraftDocument
    if RawSourceIO.recognizes(data) {
      let info = try RawSourceIO.inspect(data)
      guard info.nativeWidth <= AdobeActionAssets.maximumCanvasPixels/info.nativeHeight else { throw AdobeAPIError.invalid("RAW input exceeds the local4MP resource limit.") }
      source = try RawSourceIO.open(data,fileName:input.lastPathComponent)
    } else if data.starts(with:[0xff,0xd8]) {
      guard let image = CGImageSourceCreateWithData(data as CFData,nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(image,0,nil) as? [CFString:Any],
        let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int,
        w > 0, h > 0, w <= AdobeActionAssets.maximumCanvasPixels / h else { throw AdobeAPIError.invalid("Invalid or oversized JPEG input.") }
      source = try RasterIO.read(data,name:"Color Edit")
    } else { source = try AdobeActionAssets.decode(data) }
    try AdobeActionAssets.check(source)
    var flat = source
    let layer = Layer(name:"Color Edit",content:.raster(try Renderer.composite(source)))
    flat.layers = [layer]; flat.activeLayerID = layer.id; flat.selection = nil; flat.selectionMask = nil
    var filter = RasterFilter(.cameraRaw); filter.cameraRaw = settings
    try Command.applyFilter(layer.id,filter).apply(to:&flat)
    return try AdobeActionAssets.encode(request,document:flat)
  }
}
