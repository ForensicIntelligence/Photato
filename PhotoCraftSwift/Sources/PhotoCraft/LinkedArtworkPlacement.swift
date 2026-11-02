import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// One file preparation dispatch for the native chooser and explicitly approved API assets.
enum ArtworkPlacementPreparation {
  static func prepare(_ data:Data,fileName:String,in original:CraftDocument,
    embedded:EmbeddedSourceOptions,pdf:PDFSmartObjectOptions?=nil,decoded:CraftDocument?=nil)throws->Command {
    if let pdf {
      if let frameID=embedded.frameID {
        return try .frame(.replace(frameID,PDFSmartObjectIO.placed(data,fileName:fileName,in:original,
          settings:pdf.settings,image:pdf.image),fit:embedded.frameFit))
      }
      return try PDFSmartObjectAPI.prepare(data,fileName,original,pdf)
    }
    return try EmbeddedSourceAPI.prepare(data,fileName,original,embedded,decoded:decoded)
  }
}

struct LinkedArtworkPlacementOptions:Sendable {
  var embedded=EmbeddedSourceOptions()
  var pdf:PDFSmartObjectOptions?
}
enum LinkedArtworkPlacementAPI {
  static var schema:[String:Any] {
    var pdf=PDFSmartObjectAPI.schema
    var properties=pdf["properties"] as! [String:Any]
    for key in ["fit","transform","layerID","preserveSize","allInstances"]{properties.removeValue(forKey:key)}
    pdf["properties"]=properties
    let common=EmbeddedSourceAPI.schema["properties"] as! [String:Any]
    return BrushAPI.object(["transform":common["transform"]!,"frameID":common["frameID"]!,
      "frameFit":common["frameFit"]!,"rawDevelopment":common["rawDevelopment"]!,"pdf":pdf])
  }
  static func options(_ value:AutomationValue?,fit:Bool,fitExplicit:Bool)throws->LinkedArtworkPlacementOptions {
    do {
      let raw=value ?? .object([:]);_ = try BrushAPI.merge(raw,schema:schema,path:"placement")
      guard case .object(var fields)=raw else{throw CraftError.invalid("placement must be an object.")}
      let pdf=fields.removeValue(forKey:"pdf")
      let header=try JSONSerialization.data(withJSONObject:fields.mapValues(\.jsonValue))
      var embedded=try EmbeddedSourceAPI.options(String(decoding:header,as:UTF8.self));embedded.fit=fit
      guard embedded.frameID==nil || !fitExplicit else{throw CraftError.invalid("fit applies to new layers; choose frameFit for frame placement.")}
      guard embedded.frameID==nil || embedded.transform==nil else{throw CraftError.invalid("Initial transform applies to new layers; transform frame contents separately.")}
      guard pdf==nil || embedded.rawDevelopment==nil else{throw CraftError.invalid("Choose PDF options or RAW development, not both.")}
      var result=LinkedArtworkPlacementOptions(embedded:embedded)
      if let pdf {
        let bytes=try JSONSerialization.data(withJSONObject:pdf.jsonValue)
        result.pdf=try PDFSmartObjectAPI.options(String(decoding:bytes,as:UTF8.self))
      }
      return result
    }catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
  static func prepare(_ file:LinkedArtworkRead,in original:CraftDocument,options:LinkedArtworkPlacementOptions)throws->Command {
    let isPDF=PDFImport.recognizes(file.data)
    guard isPDF || options.pdf==nil else{throw CraftError.invalid("PDF placement options require an original PDF file.")}
    guard !isPDF || options.embedded.rawDevelopment==nil else{throw CraftError.invalid("RAW development requires a camera RAW file.")}
    var pdf:PDFSmartObjectOptions?
    if isPDF {
      var selected=options.pdf ?? .init();selected.fit=options.embedded.fit;selected.transform=options.embedded.transform;pdf=selected
    }
    let prepared=try ArtworkPlacementPreparation.prepare(file.data,fileName:file.fileName,in:original,embedded:options.embedded,pdf:pdf)
    let linked=try LinkedArtworkPreparation.linking(prepared,file:file,in:original)
    return try LinkedSmartObjectIO.combining([linked],source:original,title:"Place Linked")
  }
}
