import Foundation
import PhotoCraftCore

extension PhotoAlignSettings {
  static var apiSchema: [String:Any] {
    ["type":"object","additionalProperties":false,"properties":[
      "projection":["type":"string","enum":Projection.allCases.map(\.rawValue),"default":"auto"],
      "referenceLayerID":["type":"string","format":"uuid"],
      "focalLengthPixels":["type":"number","minimum":10,"maximum":1_000_000]]]
  }
  static var apiCapabilities: [String:Any] {
    ["command":"photo.autoAlign","settingsSchema":apiSchema,"maximumLayers":PhotoAlign.maximumLayers,"maximumLayerPixels":PhotoAlign.maximumPixels,"maximumTotalPixels":PhotoAlign.maximumTotalPixels,
     "behavior":"Harris/steered-BRIEF matching, robust projective/similarity/rigid/translation fitting, connected placement graph and joint refinement. Auto chooses Perspective or Cylindrical; Spherical, Collage and Reposition are explicit choices. Pixels and effective raster masks are warped together; canvas and selection remain unchanged.",
     "availability":"Two to sixteen visible ordinary pixel layers sharing a parent. One locked reference is allowed for planar projections; other locks, Smart Objects, effects, clipped layers and vector masks reject explicitly. Disconnected matches abort without applying a partial result.",
     "history":"Native desktop and API share prepared transactions, cancellation, stale/busy guards and Undo/Redo. Existing native/PSD persistence; no archive version change.",
     "adobe":"Installed Photoshop StackSupport alignment char-ID descriptor is supported through both action-job interfaces: $Algn, $Usng/$ADSt:ADSContent and $Aply/projection. No invented standalone route.",
     "limits":"900-pixel registration preview; bilinear full-resolution output. Lens distortion/vignette correction, proprietary matching/pixels, richer contexts and large-production-image qualification remain open."]
  }
}
extension AutomationCommand {
  func photoAlignOptions() throws -> (Set<UUID>,PhotoAlignSettings) {
    guard case .array(let values) = parameters["layerIDs"],(2...PhotoAlign.maximumLayers).contains(values.count) else { throw AutomationFailure(status:400,message:"Provide two to sixteen layerIDs.") }
    let ids = try values.map { value -> UUID in guard case .string(let s) = value,let id = UUID(uuidString:s) else { throw AutomationFailure(status:400,message:"Invalid layer UUID.") };return id }
    guard Set(ids).count == ids.count else { throw AutomationFailure(status:400,message:"Layer UUIDs must be unique.") }
    var settings = PhotoAlignSettings()
    if let raw = parameters["settings"] {
      guard case .object(let f) = raw,Set(f.keys).isSubset(of:["projection","referenceLayerID","focalLengthPixels"]) else { throw AutomationFailure(status:400,message:"Invalid Auto-Align settings.") }
      if let value = f["projection"] { guard case .string(let s) = value,let p = PhotoAlignSettings.Projection(rawValue:s) else { throw AutomationFailure(status:400,message:"Unknown projection.") };settings.projection = p }
      if let value = f["referenceLayerID"] { guard case .string(let s) = value,let id = UUID(uuidString:s),ids.contains(id) else { throw AutomationFailure(status:400,message:"Reference must be a selected layer UUID.") };settings.referenceLayerID = id }
      if let value = f["focalLengthPixels"] { guard case .number(let n) = value,n.isFinite,(10...1_000_000).contains(n) else { throw AutomationFailure(status:400,message:"Focal length must be 10–1,000,000 pixels.") };settings.focalLengthPixels = n }
    };return (Set(ids),settings)
  }
}
