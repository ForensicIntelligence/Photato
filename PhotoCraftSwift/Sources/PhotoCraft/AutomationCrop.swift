import Foundation
import PhotoCraftCore

extension CropRequest {
  static var stateSchema:[String:Any]{["type":"object","required":["available","canRetainCroppedPixels","workspaceOpen","previewBusy","previewReady","previewError","maximumDimension","maximumPixels","maximumPreviewDimension"],"properties":["available":["type":"boolean"],"canRetainCroppedPixels":["type":"boolean"],"workspaceOpen":["type":"boolean"],"previewBusy":["type":"boolean"],"previewReady":["type":"boolean"],"previewError":["type":["string","null"]],"maximumDimension":["type":"integer","const":Surface.maxDimension],"maximumPixels":["type":"integer","const":maximumPixels],"maximumPreviewDimension":["type":"integer","const":1024]]]}
  static var apiCapabilities: [String:Any] {
    ["command":"document.crop","maximumCanvasPixels":maximumPixels,"maximumDimension":Surface.maxDimension,"maximumPreviewDimension":1024,"maximumRasterPatchPixels":RasterGeometry.maximumPatchPixels,"maximumContentAwarePixels":ContentAwareSynthesis.maximumPixels,
     "geometry":"x/y/width/height describe the unrotated crop rectangle in original document pixels. angle is its clockwise angle; output straightens by the inverse rotation.",
     "fill":"transparent, background or contentAware. Fill only newly exposed gaps outside the old canvas. Existing interior transparency is retained. Generated output is an additional editable raster layer in component modes; Indexed/Bitmap fill maps into the existing flat stored samples.",
     "storage":"Delete Cropped Pixels trims ordinary raster pixels. Otherwise layer storage is retained with affine geometry. Smart Object source content, vector/text data and masks remain editable. Background remains an opaque canvas layer after deleting Crop and uses the captured background color. Convert it explicitly before nondestructive cropping; layered Background/Content-Aware cases remain unqualified. Indexed/Bitmap require deleteCroppedPixels=true and have an 8,388,608-pixel limit; nearest sampling preserves indices/bits.",
     "history":"Shared desktop/API prepared edit with preview cancellation and one Undo/Redo transaction. Current selection is cleared; saved channels and paths follow the crop.",
     "limits":"RGB source/output crop admits300,000 pixels per side/90gigapixels. Raster delete/straighten and background fill stream bounded patches; preview images are at most1024pixels per side. Dense maximum-size speed/storage remains unqualified. Indexed/Bitmap/ink/native component processing retains separate8MP limits; Content-Aware exposed output retains4MP synthesis limit. Exact Photoshop interpolation/model/UX remains unqualified. Adobe auto-crop is a separate detection API; manual crop actionJSON remains unsupported."]
  }
  static func apiSchema(_ key: String) -> [String:Any]? {
    switch key {
    case "x","y": ["type":"integer","minimum":-1000000,"maximum":1000000]
    case "width","height": ["type":"integer","minimum":1,"maximum":Surface.maxDimension]
    case "angle": ["type":"number","minimum":-360,"maximum":360,"default":0]
    case "deleteCroppedPixels": ["type":"boolean","default":true]
    case "fill": ["type":"string","enum":Fill.allCases.map(\.rawValue),"default":"transparent"]
    case "backgroundColor": ["type":"array","minItems":3,"maxItems":3,"items":["type":"number","minimum":0,"maximum":1],"default":[1,1,1]]
    case "seed": ["type":"integer","minimum":0,"maximum":UInt32.max,"default":1]
    default:nil
    }
  }
}
extension AutomationCommand {
  func cropOptions() throws -> CropRequest {
    var r = CropRequest(x:try integer("x",range:-1000000...1000000),y:try integer("y",range:-1000000...1000000),width:try integer("width",range:1...Double(Surface.maxDimension)),height:try integer("height",range:1...Double(Surface.maxDimension)))
    if parameters["angle"] != nil { r.angle = try number("angle",range:-360...360) }
    if let raw = parameters["deleteCroppedPixels"] { guard case .bool(let value) = raw else { throw AutomationFailure(status:400,message:"Invalid Delete Cropped Pixels.") };r.deleteCroppedPixels = value }
    if parameters["fill"] != nil { guard let fill = CropRequest.Fill(rawValue:try string("fill")) else { throw AutomationFailure(status:400,message:"Unknown crop fill.") };r.fill = fill }
    if parameters["seed"] != nil { r.seed = UInt32(try integer("seed",range:0...Double(UInt32.max))) }
    if let raw = parameters["backgroundColor"] {
      guard case .array(let values) = raw,values.count == 3 else { throw AutomationFailure(status:400,message:"Background color requires three RGB values.") }
      let rgb = try values.map { value -> Float in guard case .number(let n) = value,n.isFinite,(0...1).contains(n) else { throw AutomationFailure(status:400,message:"Invalid background color.") };return Float(n) };r.backgroundColor = Pixel(rgb[0],rgb[1],rgb[2],1)
    }
    do { try r.validate() } catch { throw AutomationFailure(status:400,message:error.localizedDescription) };return r
  }
}
