import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension Layer {
  var sourceSmartAPIState:[String:Any]? {
    guard requiresSourceSmartArchive else{return nil}
    var appearance:Any=NSNull()
    if let value=importedSmartAppearance {
      appearance=["cacheAvailable":value.pixels != nil,"pristine":pristineSmartAppearance != nil,
        "x":value.x,"y":value.y,"width":value.pixels.map{$0.width as Any} ?? NSNull(),"height":value.pixels.map{$0.height as Any} ?? NSNull(),
        "placedRecordByteLength":value.placedRecord?.count ?? 0] as [String:Any]
    }
    return ["projection":sourceProjection.map{$0.values as Any} ?? NSNull(),
      "sourceWarpBounds":warp?.sourceBounds.map{BrushAPI.json($0)} ?? NSNull(),"originalAppearance":appearance]
  }
}
enum SourceSmartObjectAPI {
  static var stateSchema:[String:Any] {
    let number:[String:Any] = ["type":"number"]
    let bounds=BrushAPI.object(["x":number,"y":number,"width":number,"height":number])
    let appearance=BrushAPI.object(["cacheAvailable":BrushAPI.flag,"pristine":BrushAPI.flag,"x":["type":"integer"],"y":["type":"integer"],
      "width":["type":["integer","null"]],"height":["type":["integer","null"]],"placedRecordByteLength":["type":"integer","minimum":0]])
    let state=BrushAPI.object(["projection":["type":["array","null"],"items":number,"minItems":9,"maxItems":9],
      "sourceWarpBounds":["anyOf":[["type":"null"],bounds]],"originalAppearance":["anyOf":[["type":"null"],appearance]]])
    return ["anyOf":[["type":"null"],state],"readOnly":true]
  }
  static var capabilities:[String:Any] {
    ["nativeArchiveVersion":70,"relightArchiveVersion":71,"lightingArchiveVersion":72,"sourceDisplacementArchiveVersion":73,"layerStateKey":"sourceSmartObject","layerStateSchema":stateSchema,
      "sourceFilterCommands":PcraftImport.sourceSmartFilterCommands,
      "sourceFilterCoverage":["declaredCommands":110,"mappedCommands":PcraftImport.sourceSmartFilterCommands.count,"unmappedCommands":PcraftImport.unsupportedSourceSmartFilterCommands,"parameterLimits":PcraftImport.sourceSmartFilterLimitations],
      "placementOrder":"projection maps source pixels before the ordinary layer transform. Together they equal the original full placement; the retained manifest preserves original coefficients.",
      "editable":"Embedded original files, nested supported PhotoCraft projects, affine/projective placement, preset/custom source Warp frames, eleven image-stack modes, mapped ordered filter controls/blending/visibility and masks. The original document-space appearance is authoritative until the represented source/program changes.",
      "operations":"Existing Photato import, original-source upload/download, shared-source replacement, affine delta transforms, reset, filter/mask editing, rasterization, history and native70 downloads share desktop transactions.",
      "originalData":"Original file bytes and immutable outer manifest provenance are retained. Native Save As preserves the model; imports never overwrite source projects.",
      "adobe":"PhotoCraft inputs and Smart Object resource files remain Photato-only. Adobe's published input contract is unchanged.",
      "limits":"Linked source projects without original extents, unmapped source filters/adjustments, unsupported native parameter ranges/source color/format data and exceeded decoder/heap/source-file limits reject the whole import. Projective linked-mask rerendering, full PSD/PSB editing, exact source/Photoshop kernels, larger dense capacity and native/platform qualification remain open."]
  }
}
