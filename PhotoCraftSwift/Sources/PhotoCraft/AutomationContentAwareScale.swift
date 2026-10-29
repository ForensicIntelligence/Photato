import Foundation
import PhotoCraftCore

extension ContentAwareScaleRequest {
  static var apiCapabilities: [String:Any] {
    ["command":"contentAware.scale","maximumPixels":SeamCarving.maximumPixels,"maximumWork":SeamCarving.maximumWork,
     "region":"Current coverage selection, otherwise the full transformed raster layer bounds, including off-canvas pixels.",
     "position":"x/y specify output top-left in document pixels. Omitted coordinates keep the old region center fixed; dimensions are pixels.",
     "protection":"Optional saved alpha channel UUID and/or skin-tone heuristic. Amount0–100 blends ordinary bilinear and seam-carved pixels.",
     "history":"One cancellable prepared native edit with Undo/Redo, working depth/profile and matching desktop/API output.",
     "limits":"Ordinary raster layer; unlock image, position and transparency. Exact Photoshop synthesis and complex mask deformation remain unqualified. No dedicated published Adobe endpoint; content-aware scale actionJSON remains unsupported."]
  }
  static func apiSchema(_ key: String) -> [String:Any]? {
    switch key {
    case "width","height": ["type":"integer","minimum":1,"maximum":60000]
    case "x","y": ["type":"integer","minimum":-1000000,"maximum":1000000]
    case "amount": ["type":"number","minimum":0,"maximum":100,"default":100]
    case "protectChannelID": ["type":"string","format":"uuid"]
    case "protectSkinTones": ["type":"boolean","default":false]
    default: nil
    }
  }
}
extension AutomationCommand {
  func contentAwareScaleOptions() throws -> (id:UUID,request:ContentAwareScaleRequest) {
    guard let id = UUID(uuidString:try string("layerID")) else { throw AutomationFailure(status:400,message:"Invalid layerID.") }
    var request = ContentAwareScaleRequest(width:try integer("width",range:1...60000),height:try integer("height",range:1...60000))
    if parameters["x"] != nil { request.x = try integer("x",range:-1000000...1000000) }
    if parameters["y"] != nil { request.y = try integer("y",range:-1000000...1000000) }
    if parameters["amount"] != nil { request.amount = Float(try number("amount",range:0...100)) }
    if parameters["protectChannelID"] != nil { guard let channel = UUID(uuidString:try string("protectChannelID")) else { throw AutomationFailure(status:400,message:"Invalid protection channel UUID.") };request.protectChannelID = channel }
    if let value = parameters["protectSkinTones"] { guard case .bool(let skin) = value else { throw AutomationFailure(status:400,message:"Invalid Protect Skin Tones.") };request.protectSkinTones = skin }
    do { try request.validate() } catch { throw AutomationFailure(status:400,message:error.localizedDescription) };return (id,request)
  }
}
