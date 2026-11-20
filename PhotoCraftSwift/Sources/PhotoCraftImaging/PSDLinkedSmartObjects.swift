import Foundation
import PhotoCraftCore

/// Public liFE transport. References are metadata only; this codec never opens them.
enum PSDLinkedSmartObjects {
  static func text(_ value:PSDValue?)->String? {
    guard case .text(let units)=value else{return nil};return String(decoding:units.prefix{$0 != 0},as:UTF16.self)
  }
  static func read(_ item:inout PSDReader,version:Int,length:Int,name:String,type:String,typeBytes:Data?=nil,
    paging: PSDRasterPaging.Context? = nil)throws->PSDSmartObjects.File {
    let descriptor = try PSDDescriptor.readPrefix(&item)
    if version>3 {_ = try item.bytes(16)}
    let size=try item.number(8)
    if version > 2 { try paging?.admitRetainedSource(bytes: length) }
    let bytes = version > 2 ? try item.retainedBytes(length) : Data()
    let savedRelative = text(descriptor["relPath"]).flatMap {
      LinkedSmartObjectSource.isRelativePath($0) ? $0 : nil
    }
    let savedFull = text(descriptor["fullPath"]).flatMap { $0.isEmpty ? nil : $0 }
    var reference = savedFull ?? savedRelative ?? name
    var kind=LinkedSmartObjectSource.Kind.file
    if let url=URL(string:reference),["http","https"].contains(url.scheme?.lowercased() ?? "") {
      var fields=URLComponents(url:url,resolvingAgainstBaseURL:false)!;fields.user=nil;fields.password=nil;fields.query=nil;fields.fragment=nil
      reference=fields.url!.absoluteString;kind = .remote
    }
    let link=try LinkedSmartObjectSource(reference:reference,kind:kind,
      contentHash:bytes.isEmpty ? nil:LinkedSmartObjectSource.fingerprint(bytes),byteLength:size,
      relativePath: kind == .file && savedRelative != reference ? savedRelative : nil)
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
    let relative = link.relativePath ?? (LinkedSmartObjectSource.isRelativePath(link.reference)
      ? link.reference : object.fileName)
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
    filterMasks:[String:PSDSmartFilters.Mask])throws {
    guard let link=file.link,case .raster(let cache)=layer.content,
      case .object(let size)=d["Sz  "],let sw=size["Wdth"]?.number,let sh=size["Hght"]?.number,
      [sw,sh].allSatisfy({$0.isFinite && $0>0 && $0<=Double(Surface.maxDimension)}) else{throw CraftError.invalid("Invalid external placed-file geometry.")}
    let width = Int(ceil(sw)), height = Int(ceil(sh))
    let warp = try PSDWarp.decode(d, width: width, height: height)
    let frame = PSDWarp.Frame.placement(warp, width: width, height: height)
    let quads = try PSDSmartObjects.PlacementQuads(d)
    let toCache = try layer.coordinateTransform.inverted()
    let affine = quads.affine(frame: frame)
    try affine?.validated()
    let projective = affine == nil ? try quads.projective(width: width, height: height, frame: frame).followed(by: toCache) : nil
    let media=LinkedSmartObjectIO.photoshopLinkedMediaType(fileType:file.fileType,fileName:file.name)
    var resolution=72.0
    if case .unit(_,let bits)=d["Rslt"] {resolution=Double(bitPattern:bits)}
    var pdf:PDFSmartObjectSource?
    if media=="application/pdf" {
      let page = d["PgNm"]?.number ?? 1, code = d["Crop"]?.number ?? 3
      guard (1...4096).contains(page), page.rounded() == page,
            let crop = PSDPDFSmartObjects.crops.first(where: { Double($0.value) == code })?.key else {
        throw CraftError.invalid("Invalid linked PDF page or crop.")
      }
      pdf=try .init(page:Int(page),crop:crop,x:0,y:0,width:Double(width)*72/resolution,height:Double(height)*72/resolution)
    }
    let safeName=(file.name.replacingOccurrences(of:"\\",with:"/")as NSString).lastPathComponent
    layer.smartObject=try .init(sourceID:sourceID,fileName:safeName,mediaType:media,data:Data(),width:width,height:height,resolution:resolution,pdfSource:pdf,linkedSource:link)
    if media=="application/octet-stream"{if layer.sourceTags==nil{layer.sourceTags=[:]};layer.sourceTags?["PhFT"]=file.fileTypeBytes ?? Data(file.fileType.utf8)}
    try layer.setLinkedSmartObjectPreview(.init(sourceToCache: affine.map { toCache * $0 } ?? .identity,
      sourceWidth:width,sourceHeight:height,cacheWidth:cache.width,cacheHeight:cache.height,
      projectiveSourceToCache: projective, warp: warp))
    if warp != nil, layer.mask != nil, layer.effectiveMaskProperties.linked {
      var properties = layer.effectiveMaskProperties
      properties.storedAfterWarp = true
      layer.maskProperties = properties
    }
    if let filters=d["filterFX"] {
      var stack=try PSDSmartFilters.read(filters)
      if let placed=PSDSmartObjects.placedIdentifier(in:d),let mask=filterMasks[placed]{stack.mask=mask.pixels;stack.maskProperties.transform=mask.transform}
      layer.smartFilters=stack
    }
  }
  static func unresolvedDescriptor(_ layer:Layer,source:SmartObject)throws->Data? {
    guard try layer.linkedSmartObjectPreview() != nil else { return nil }
    guard layer.warp == nil else {
      throw CraftError.unsupported("Relink this artwork before saving its deferred Warp as PSD or PSB.")
    }
    guard let raw=layer.sourceTags?["SoLd"] ?? layer.sourceTags?["SoLE"] else{return nil}
    var descriptor = try PSDSmartObjects.descriptor(raw)
    let (base, quad) = try PSDSmartObjects.encodedQuads(layer, source: source)
    let placed = PSDSmartObjects.placedIdentifier(for: layer)
    let sourceID = PSDValue.text(Array((source.sourceID.uuidString + "\0").utf16))
    for (key,value) in [("Trnf",base),("nonAffineTransform",quad),("Idnt",sourceID),("placed",.text(Array((placed+"\0").utf16)))] {
      if let index=descriptor.items.firstIndex(where:{$0.key.text==key}){descriptor.items[index].value=value}else{descriptor.items.append(.init(key,value))}
    }
    var writer=PSDWriter();writer.text("soLD");writer.n(4,4);writer.data.append(try descriptor.encoded());return writer.data
  }
}
