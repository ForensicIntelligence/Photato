import Foundation
import PhotoCraftCore

extension PhotoBlendSettings {
  static var apiSchema: [String:Any] {
    ["type":"object","additionalProperties":false,"properties":[
      "method":["type":"string","enum":Method.allCases.map(\.rawValue),"default":"panorama"],
      "seamlessTones":["type":"boolean","default":true],"fillTransparentAreas":["type":"boolean","default":true]]]
  }
  static var apiCapabilities: [String:Any] {
    ["command":"photo.autoBlend","settingsSchema":apiSchema,"maximumLayers":PhotoBlend.maximumLayers,"maximumOutputPixels":PhotoBlend.maximumPixels,"maximumInputPixels":PhotoBlend.maximumTotalPixels,
     "behavior":"Panorama minimum-cost seams or local-sharpness focus stacking; optional multiband seamless tones/colors and content-aware transparent-area fill. Sources retain their IDs, names, geometry, alpha and editable masks. Seamless color corrections update contributing source RGB; pixels outside the processed canvas remain unchanged. Only transparent-area fill adds a merged layer. Sources remain visible unless partial alpha requires isolation to avoid double compositing. Original mask effects are included in the resulting masks.",
     "history":"Shared desktop/native prepared transaction, cancellation, stale/busy guards and Undo/Redo. Existing native and supported PSD layer/mask persistence; no new archive version.",
     "availability":"Two to sixteen visible unlocked ordinary raster layers in one group, Normal blending, full opacity, no vector masks/effects/Smart Objects. Work is clipped to the canvas; existing selection is preserved, not used as a processing boundary.",
     "adobe":"The installed Photoshop StackSupport.jsx panorama mergeAlignedLayers descriptor is supported through both execute-actions interfaces using $Aply/autoBlendType:panorama, $ClrC boolean and autoTransparencyFill boolean. Other descriptor variants and exact Adobe results remain unqualified.",
     "limits":"Use photo.autoAlign first when inputs need registration. Use document.photomerge to create a panorama from shared documents. HDR and stack statistics remain under development."]
  }
}
extension AutomationCommand {
  func photoBlendOptions() throws -> (Set<UUID>,PhotoBlendSettings) {
    guard case .array(let values) = parameters["layerIDs"],(2...PhotoBlend.maximumLayers).contains(values.count) else { throw AutomationFailure(status:400,message:"Provide two to sixteen layerIDs.") }
    let ids = try values.map { value -> UUID in
      guard case .string(let value) = value,let id = UUID(uuidString:value) else { throw AutomationFailure(status:400,message:"Invalid layer UUID.") };return id
    }
    guard Set(ids).count == ids.count else { throw AutomationFailure(status:400,message:"Layer UUIDs must be unique.") }
    var settings = PhotoBlendSettings()
    if let raw = parameters["settings"] {
      guard case .object(let fields) = raw,Set(fields.keys).isSubset(of:["method","seamlessTones","fillTransparentAreas"]) else { throw AutomationFailure(status:400,message:"Invalid Auto-Blend settings.") }
      if let field = fields["method"] {
        guard case .string(let value) = field,let method = PhotoBlendSettings.Method(rawValue:value) else { throw AutomationFailure(status:400,message:"Unknown blend method.") };settings.method = method
      }
      for key in ["seamlessTones","fillTransparentAreas"] {
        if let field = fields[key] {
          guard case .bool(let value) = field else { throw AutomationFailure(status:400,message:"\(key) must be boolean.") }
          if key == "seamlessTones" { settings.seamlessTones = value } else { settings.fillTransparentAreas = value }
        }
      }
    }
    return (Set(ids),settings)
  }
}
