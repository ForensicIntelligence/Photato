import Foundation
import PhotoCraftCore

public enum LinkedSmartObjectIO {
  /// Editable linked raster layers have separate integer color/alpha and mask
  /// planes in Photoshop. Match that grid before combining their coverage.
  static func integerPreviewDepth(_ layer: Layer, in document: CraftDocument) -> PixelDepth? {
    guard document.colorMode == .rgb, document.depth != .f32,
      let source = layer.smartObject, source.linkedSource != nil, !source.data.isEmpty,
      ["image/png", "image/jpeg", "image/tiff"].contains(source.mediaType),
      layer.smartFilters == nil, layer.warp == nil, layer.sourceProjection == nil,
      layer.importedSmartAppearance == nil, layer.effectiveMaskProperties.feather == 0
    else { return nil }
    return document.depth
  }

  public static func linked(_ layer:Layer,reference:LinkedSmartObjectSource)throws->Layer {
    guard let object=layer.smartObject else{throw CraftError.invalid("Choose a Smart Object.")}
    var result=layer;result.smartObject=try object.linked(to:reference);return result
  }
  public static func place(_ data:Data,fileName:String,reference:LinkedSmartObjectSource,
    in document:CraftDocument,fit:Bool=true)throws->Layer {
    try place(.memory(data), fileName: fileName, reference: reference, in: document, fit: fit)
  }
  public static func place(_ original: EmbeddedSourceBytes, fileName: String, reference: LinkedSmartObjectSource,
    in document: CraftDocument, fit: Bool = true) throws -> Layer {
    try linked(SmartObjectIO.placed(original: original, fileName: fileName, in: document, fit: fit), reference: reference)
  }
  public static func retag(_ document:CraftDocument,layerID:UUID,
    source:SmartObject,allInstances:Bool=true,title:String)throws->Command {
    guard let current=document.layers.first(where:{$0.id==layerID})?.smartObject else{throw CraftError.invalid("Choose a Smart Object.")}
    try source.validate()
    guard source.width==current.width,source.height==current.height,source.resolution==current.resolution,
      source.pdfSource==current.pdfSource,source.rawDevelopment==current.rawDevelopment,
      source.mediaType==current.mediaType else{throw CraftError.invalid("Source conversion must preserve its content and dimensions.")}
    if let expected=current.linkedSource?.contentHash {
      guard !source.data.isEmpty,source.dataFingerprint==expected else{throw CraftError.invalid("The file changed. Update its contents before converting.")}
    } else if current.linkedSource==nil {
      guard source.data==current.data else{throw CraftError.invalid("Source conversion must preserve its original bytes.")}
    }
    let indices=document.layers.indices.filter{document.layers[$0].id==layerID || (allInstances && document.layers[$0].smartObject?.sourceID==current.sourceID)}
    guard indices.allSatisfy({!document.isImageLocked(document.layers[$0].id)})else{throw CraftError.invalid("Unlock all affected Smart Object instances.")}
    var result=document
    for i in indices {
      let previous = result.layers[i].smartObject!
      var value = source
      value.sourceID = allInstances ? current.sourceID : source.sourceID
      value.stackMode = previous.stackMode
      value.layerComps = previous.layerComps
      result.layers[i].smartObject=value
      result.layers[i].sourceTags?.removeValue(forKey:"SoLd");result.layers[i].sourceTags?.removeValue(forKey:"SoLE");result.layers[i].sourceTags?.removeValue(forKey:"PlLd")
    }
    return .linkedSmartObject(try .init(source:document,result:result,title:title))
  }
  /// Refresh retained source data, preserving every instance's placement and masks.
  public static func replacement(_ data:Data,fileName:String,reference:LinkedSmartObjectSource?,
    in document:CraftDocument,layerID:UUID,allInstances:Bool=true,
    preserveSize:Bool=false,title:String="Update Linked Smart Object")throws->Command {
    try replacement(.memory(data), fileName: fileName, reference: reference, in: document, layerID: layerID,
      allInstances: allInstances, preserveSize: preserveSize, title: title)
  }
  public static func replacement(_ original: EmbeddedSourceBytes, fileName: String, reference: LinkedSmartObjectSource?,
    in document: CraftDocument, layerID: UUID, allInstances: Bool = true,
    preserveSize: Bool = false, title: String = "Update Linked Smart Object") throws -> Command {
    let data = original.data
    guard let old=document.layers.first(where:{$0.id==layerID})?.smartObject else{throw CraftError.invalid("Choose a Smart Object.")}
    var result=document
    let command:Command
    if PDFImport.recognizes(data) {
      if let selection=old.pdfSource {
        var settings=PDFImportSettings();settings.pages=[selection.page]
        settings.crop=PDFImportSettings.Crop(rawValue:selection.crop.rawValue)!
        settings.resolution=old.resolution;settings.antialias=selection.antialias
        command=try PDFSmartObjectIO.replacement(data,fileName:fileName,in:document,layerID:layerID,
          settings:settings,image:selection.image,preserveSize:preserveSize,allInstances:allInstances)
      }else{
        command=try PDFSmartObjectIO.replacement(data,fileName:fileName,in:document,layerID:layerID,
          settings:PDFImportSettings(),preserveSize:preserveSize,allInstances:allInstances)
      }
    }else{
      let source:CraftDocument
      if let settings=old.rawDevelopment,RawSourceIO.recognizes(data) {
        // Refresh sensor bytes without discarding the user's nondestructive development.
        source=try RawSourceIO.open(data,fileName:fileName,settings:settings)
      }else{source=try SmartObjectIO.decode(original,fileName:fileName)}
      command=try SmartObjectIO.replacement(in:document,layerID:layerID,source:source,
        original:original,fileName:fileName,preserveSize:preserveSize,allInstances:allInstances)
    }
    try command.apply(to:&result)
    let ids=result.layers.indices.filter{result.layers[$0].id==layerID || (allInstances && result.layers[$0].smartObject?.sourceID==old.sourceID)}
    if let reference {
      for i in ids {result.layers[i]=try linked(result.layers[i],reference:reference)}
    }
    return .linkedSmartObject(try .init(source:document,result:result,title:title))
  }
  /// Bulk embedding prepares every source before exposing one atomic history transaction.
  public static func embed(_ document:CraftDocument,sourceIDs:Set<UUID>?=nil,
    originals:[UUID:Data]=[:],title:String="Embed All Linked")throws->Command {
    try embed(document, sourceIDs: sourceIDs, approvedOriginals: originals.mapValues(EmbeddedSourceBytes.memory), title: title)
  }
  public static func embed(_ document: CraftDocument, sourceIDs: Set<UUID>? = nil,
    approvedOriginals: [UUID: EmbeddedSourceBytes], title: String = "Embed All Linked") throws -> Command {
    let linked=document.layers.compactMap{$0.smartObject}.filter{$0.linkedSource != nil}
    let ids=sourceIDs ?? Set(linked.map(\.sourceID))
    guard !ids.isEmpty,ids.isSubset(of:Set(linked.map(\.sourceID)))else{throw CraftError.invalid("Choose linked Smart Objects to embed.")}
    var result=document,done=Set<UUID>()
    for layer in document.layers {
      guard let object=layer.smartObject,object.linkedSource != nil,ids.contains(object.sourceID),done.insert(object.sourceID).inserted else{continue}
      try Task.checkCancellation()
      let preview=try layer.linkedSmartObjectPreview()
      let command:Command
      if !object.data.isEmpty,preview==nil {
        command=try retag(result,layerID:layer.id,source:object.embedding(),title:title)
      }else{
        guard let original=approvedOriginals[object.sourceID]else{throw CraftError.invalid("Locate the original artwork before embedding all links.")}
        if preview==nil,object.linkedSource?.contentHash==original.fingerprint {
          command=try retag(result,layerID:layer.id,source:object.hydrating(original).embedding(),title:title)
        }else{
          command=try replacement(original,fileName:object.fileName,reference:nil,in:result,layerID:layer.id,title:title)
        }
      }
      try command.apply(to:&result)
    }
    return .linkedSmartObject(try .init(source:document,result:result,title:title))
  }
  public static func combining(_ commands:[Command],source:CraftDocument,title:String)throws->Command {
    var result=source
    for command in commands {try Task.checkCancellation();try command.apply(to:&result)}
    return .linkedSmartObject(try .init(source:source,result:result,title:title))
  }
}
