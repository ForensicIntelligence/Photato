import Foundation
import PhotoCraftCore
import PhotoCraftImaging

struct AdobeBackgroundEdit:Sendable {
  let operation:String
  let name:String?
  let identifier:Int32?
  let url:URL?
  let visible:Bool?
  let convert:Bool
  let convertedName:String?
  init(_ raw:Any,path:String)throws {
    typealias Object=AdobeActionsRequest.Object
    let object=try Object(raw,at:path,allowed:["type","operation","name","id","image","isVisible","convertToLayer","convertedLayerName"])
    guard try object.string("type")=="background_layer" else{throw AdobeAPIError.invalid("Expected background_layer.")}
    let op=try object.object("operation",allowed:["type"]);operation=try op.string("type")
    guard ["add","edit","delete"].contains(operation) else{throw AdobeAPIError.unsupported("Background move and placement are unavailable; convert to a regular layer first.")}
    name=try object.fields["name"].map{_ in try object.string("name")};identifier=try object.fields["id"].map{_ in Int32(try object.integer("id",range:0...Int(Int32.max)))}
    if operation != "add",(name==nil)==(identifier==nil){throw AdobeAPIError.invalid("Background requires exactly one id or name reference.")}
    if operation == "add",identifier != nil{throw AdobeAPIError.invalid("Added backgrounds cannot specify an id.")}
    visible=try object.optionalBool("isVisible");convert=try object.optionalBool("convertToLayer") ?? false
    convertedName=try object.fields["convertedLayerName"].map{_ in try object.string("convertedLayerName")}
    guard convertedName==nil || convert else{throw AdobeAPIError.invalid("convertedLayerName requires convertToLayer.")}
    if object.fields["image"] != nil {let image=try object.object("image",allowed:["source"]),source=try image.object("source",allowed:["url"]);url=try AdobeActionsRequest.url(source.string("url"),path:path+".image.source.url",httpsOnly:false)}else{url=nil}
    if operation=="add",url==nil{throw AdobeAPIError.invalid("Adding Background requires image.source.")}
    if operation != "edit",convert || convertedName != nil || (operation=="delete" && (url != nil || visible != nil)){throw AdobeAPIError.invalid("Invalid Background operation properties.")}
    for value in [name,convertedName].compactMap({$0}) {guard !value.isEmpty,value.utf16.count<=65535 else{throw AdobeAPIError.invalid("Invalid Background layer name.")}}
  }
  func apply(to session:inout EditorSession,resources:[URL:Data])throws {
    var document=session.document
    guard document.colorMode == .rgb else{throw AdobeAPIError.unsupported("Background pixel operations currently require RGB.")}
    let id:UUID
    if operation=="add" {
      guard !document.layers.contains(where:{$0.isBackground}),document.layers.count<LayerLimits.maximumLayers else{throw AdobeAPIError.invalid("The input already has Background or reached its layer limit.")}
      let surface=try image(in:document,resources:resources)
      var layer=Layer(name:name ?? "Background",content:.raster(surface));layer.background=true;layer.visible=visible ?? true;layer.sourceTags=["lyid":Data(repeating:0,count:4)];document.layers.insert(layer,at:0);id=layer.id
    }else {
      let matches=document.layers.filter{layer in
        guard layer.isBackground else{return false}
        if let name{return layer.name==name}
        guard let identifier else{return false}
        if identifier==0{return true}
        guard let bytes=layer.sourceTags?["lyid"],bytes.count==4 else{return false};return Int32(bitPattern:bytes.reduce(UInt32(0)){($0<<8)|UInt32($1)})==identifier
      }
      guard matches.count==1,let layer=matches.first else{throw AdobeAPIError.invalid("Background reference must match exactly one layer.")};id=layer.id
      let i=document.layers.firstIndex{$0.id==id}!
      if operation=="delete" {document.layers.remove(at:i);if document.activeLayerID==id{document.activeLayerID=document.layers.last?.id}}
      else {
        if url != nil {document.layers[i].content = .raster(try image(in:document,resources:resources))}
        if let visible{document.layers[i].visible=visible}
        if convert {try BackgroundLayer.apply(.toLayer(id,.init(name:convertedName ?? "Layer 0")),to:&document)}
      }
    }
    try document.validate();session=EditorSession(document:document)
  }
  private func image(in destination:CraftDocument,resources:[URL:Data])throws->Surface {
    guard let url,let data=resources[url] else{throw AdobeAPIError.invalid("Missing Background image resource.")}
    let source=try AdobeActionAssets.decode(data)
    guard source.colorMode == .rgb else{throw AdobeAPIError.unsupported("Background image conversion requires RGB.")}
    let composite=try Renderer.composite(source),converted=try ColorManagement.converted(composite,from:source,to:destination)
    let placement=Transform2D.scale(Double(destination.width)/Double(source.width),Double(destination.height)/Double(source.height))
    let pixels=try RasterGeometry.render(converted,transform:placement,bounds:.init(x:0,y:0,width:destination.width,height:destination.height),method:.bicubic)
    return try BackgroundLayer.opaque(pixels,over:.white)
  }
}
