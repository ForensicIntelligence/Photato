import Foundation
import PhotoCraftCore

/// Public liFE transport. References are metadata only; this codec never opens them.
enum PSDLinkedSmartObjects {
  static func text(_ value:PSDValue?)->String? {
    guard case .text(let units)=value else{return nil};return String(decoding:units.prefix{$0 != 0},as:UTF16.self)
  }
  static func read(_ item:inout PSDReader,version:Int,length:Int,name:String,type:String,typeBytes:Data?=nil)throws->PSDSmartObjects.File {
    let (descriptor,used)=try PSDDescriptor.readPrefix(Data(item.data.dropFirst(item.offset)))
    _ = try item.bytes(used)
    if version>3 {_ = try item.bytes(16)}
    let size=try item.number(8)
    let bytes=version>2 ? try item.bytes(length):Data()
    var reference=text(descriptor["fullPath"]) ?? text(descriptor["relPath"]) ?? name
    var kind=LinkedSmartObjectSource.Kind.file
    if let url=URL(string:reference),["http","https"].contains(url.scheme?.lowercased() ?? "") {
      var fields=URLComponents(url:url,resolvingAgainstBaseURL:false)!;fields.user=nil;fields.password=nil;fields.query=nil;fields.fragment=nil
      reference=fields.url!.absoluteString;kind = .remote
    }
    let link=try LinkedSmartObjectSource(reference:reference,kind:kind,
      contentHash:bytes.isEmpty ? nil:LinkedSmartObjectSource.fingerprint(bytes),byteLength:size)
    return .init(name:name,data:bytes,link:link,fileType:type,fileTypeBytes:typeBytes)
  }
  static func append(_ object:SmartObject,typeHint:Data?=nil,to out:inout PSDWriter)throws {
    guard let link=object.linkedSource else{throw CraftError.invalid("Missing external source reference.")}
    try object.validate();try link.validate()
    var item=PSDWriter();item.text("liFE");item.n(7,4)
    let id=object.sourceID.uuidString;item.n(id.utf8.count,1);item.text(id)
    let units=Array((object.fileName+"\0").utf16);item.n(units.count,4);for unit in units{item.n(Int(unit),2)}
    let classified=try LinkedSmartObjectIO.photoshopLinkedFileType(object)
    let type:Data
    if object.mediaType=="application/octet-stream",object.data.isEmpty,let typeHint {
      guard typeHint.count==4 else{throw CraftError.invalid("An opaque linked file type must contain four bytes.")};type=typeHint
    }else{type=Data(classified.utf8)}
    guard type.count==4 else{throw CraftError.invalid("Invalid linked file type.")}
    item.data.append(type);item.text("8BIM");item.n(0,8);item.n(0,1)
    let full=URL(string:link.reference).flatMap{$0.isFileURL ? $0.path:nil} ?? link.reference
    let relative=(!full.hasPrefix("/") && URL(string:link.reference)?.scheme==nil) ? link.reference:object.fileName
    let descriptor=PSDDescriptor("filespec",items:[.init("Nm  ",.text(Array((object.fileName+"\0").utf16))),.init("fullPath",.text(Array((full+"\0").utf16))),.init("relPath",.text(Array((relative+"\0").utf16)))])
    item.data.append(try descriptor.encoded())
    var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
    let parts=calendar.dateComponents([.year,.month,.day,.hour,.minute,.second],from:link.modificationDate ?? Date(timeIntervalSince1970:0))
    item.n(parts.year ?? 1970,4);for value in [parts.month,parts.day,parts.hour,parts.minute]{item.n(value ?? 0,1)}
    var seconds=Double(parts.second ?? 0).bitPattern.bigEndian;withUnsafeBytes(of:&seconds){item.data.append(contentsOf:$0)}
    guard link.byteLength<=UInt64(Int.max)else{throw CraftError.invalid("External file size overflows.")};item.n(Int(link.byteLength),8)
    item.n(0,4);item.n(0,8);item.n(0,1)
    out.n(item.data.count,8);out.data.append(item.data);while out.data.count%4 != 0{out.n(0,1)}
  }
  static func restore(_ layer:inout Layer,descriptor d:PSDDescriptor,file:PSDSmartObjects.File,sourceID:UUID,
    document:CraftDocument,filterMasks:[String:PSDSmartFilters.Mask])throws {
    guard let link=file.link,case .raster(let cache)=layer.content,
      case .object(let size)=d["Sz  "],let sw=size["Wdth"]?.number,let sh=size["Hght"]?.number,
      [sw,sh].allSatisfy({$0.isFinite && $0>0 && $0<=Double(Surface.maxDimension)}),
      case .list(let values)=d["Trnf"],values.count==8,values.allSatisfy({$0.number?.isFinite==true}) else{throw CraftError.invalid("Invalid external placed-file geometry.")}
    let width=Int(ceil(sw)),height=Int(ceil(sh)),q=values.map{$0.number!},w=Double(width),h=Double(height)
    let transform=Transform2D(a:(q[2]-q[0])/w,b:(q[3]-q[1])/w,c:(q[6]-q[0])/h,d:(q[7]-q[1])/h,tx:q[0],ty:q[1])
    try transform.validated();let corner=transform.point(w,h)
    guard abs(corner.x-q[4])<0.001,abs(corner.y-q[5])<0.001 else{throw CraftError.unsupported("Resolve a perspective linked source before editing its placement.")}
    let media=LinkedSmartObjectIO.photoshopLinkedMediaType(fileType:file.fileType,fileName:file.name)
    var resolution=72.0
    if case .unit(_,let bits)=d["Rslt"] {resolution=Double(bitPattern:bits)}
    var pdf:PDFSmartObjectSource?
    if media=="application/pdf" {
      let page=Int(d["PgNm"]?.number ?? 1),code=Int(d["Crop"]?.number ?? 3)
      let crop=PSDPDFSmartObjects.crops.first{Int($0.value)==code}?.key ?? .media
      pdf=try .init(page:page,crop:crop,x:0,y:0,width:w*72/resolution,height:h*72/resolution)
    }
    let safeName=(file.name.replacingOccurrences(of:"\\",with:"/")as NSString).lastPathComponent
    layer.smartObject=try .init(sourceID:sourceID,fileName:safeName,mediaType:media,data:Data(),width:width,height:height,resolution:resolution,pdfSource:pdf,linkedSource:link)
    if media=="application/octet-stream"{if layer.sourceTags==nil{layer.sourceTags=[:]};layer.sourceTags?["PhFT"]=file.fileTypeBytes ?? Data(file.fileType.utf8)}
    try layer.setLinkedSmartObjectPreview(.init(sourceToCache:layer.coordinateTransform.inverted()*transform,
      sourceWidth:width,sourceHeight:height,cacheWidth:cache.width,cacheHeight:cache.height))
    if let filters=d["filterFX"] {
      var stack=try PSDSmartFilters.read(filters)
      if let placed=text(d["placed"]),let mask=filterMasks[placed]{stack.mask=mask.pixels;stack.maskProperties.transform=mask.transform}
      layer.smartFilters=stack
    }
  }
  static func unresolvedDescriptor(_ layer:Layer,source:SmartObject)throws->Data? {
    guard try layer.linkedSmartObjectPreview() != nil,
      let raw=layer.sourceTags?["SoLd"] ?? layer.sourceTags?["SoLE"] else{return nil}
    var descriptor=try PSDSmartObjects.descriptor(raw);let t=try layer.smartObjectSourceTransform(),w=Double(source.width),h=Double(source.height)
    let points=[t.point(0,0),t.point(w,0),t.point(w,h),t.point(0,h)]
    let quad=PSDValue.list(points.flatMap{[.number($0.x),.number($0.y)]})
    for (key,value) in [("Trnf",quad),("nonAffineTransform",quad),("placed",.text(Array((layer.id.uuidString+"\0").utf16)))] {
      if let index=descriptor.items.firstIndex(where:{$0.key.text==key}){descriptor.items[index].value=value}else{descriptor.items.append(.init(key,value))}
    }
    var writer=PSDWriter();writer.text("soLD");writer.n(4,4);writer.data.append(try descriptor.encoded());return writer.data
  }
}
