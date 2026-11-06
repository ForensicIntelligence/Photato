import Foundation
import PhotoCraftCore

public enum ColorLookupFileFormat: String, CaseIterable, Codable, Sendable, Hashable {
  case threeDL = "3dl", cube, csp, icc
  public var title: String { switch self {case .threeDL:"3DL";case .cube:"CUBE";case .csp:"CSP";case .icc:"ICC Profile"} }
}
public struct ColorLookupExportRequest: Sendable {
  public var size: Int
  public var title: String
  public var copyright: String
  public var formats: [ColorLookupFileFormat]
  public var baseName: String
  public var created: Date
  public init(size:Int=32,title:String="Color Lookup",copyright:String="",formats:[ColorLookupFileFormat]=[.cube],baseName:String="Color Lookup",created:Date=Date()) {
    self.size=size;self.title=title;self.copyright=copyright;self.formats=formats;self.baseName=baseName;self.created=created
  }
  public func validate() throws {
    guard (2...ColorLUT.maximumSize).contains(size),!formats.isEmpty,Set(formats).count==formats.count,
      title.utf8.count<=1024,copyright.utf8.count<=1024,
      ![title,copyright].contains(where:{$0.unicodeScalars.contains(where:{$0.value<32 || $0.value==127})}),
      !baseName.isEmpty,baseName != ".",baseName != "..",baseName.utf8.count<=120,
      !baseName.contains("/"),!baseName.contains("\\"),!baseName.contains(":"),
      !baseName.unicodeScalars.contains(where:{$0.value<32 || $0.value==127}),
      created.timeIntervalSince1970.isFinite,(1900...9999).contains(year)
    else {throw CraftError.invalid("Choose valid LUT formats, metadata, filename and 2–129 grid points.")}
  }
  public var year:Int {var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(secondsFromGMT:0)!;return c.component(.year,from:created)}
  public var copyrightLine:String {copyright.isEmpty ? "":"© Copyright \(year) \(copyright)"}
}
public struct ColorLookupEncodedFile: Sendable {
  public let format:ColorLookupFileFormat
  public let name:String
  public let data:Data
  public init(format:ColorLookupFileFormat,name:String,data:Data){self.format=format;self.name=name;self.data=data}
}
public enum ColorLookupFormats {
  public static let maximumBundleBytes=4*ColorLUT.maximumFileBytes+8192
  public static func encode(_ lut:ColorLUT,format:ColorLookupFileFormat,request:ColorLookupExportRequest)throws->Data {
    try request.validate();try lut.validate();try Task.checkCancellation()
    guard lut.size==request.size,lut.curve==nil,lut.inputGrid==nil,lut.domainMin==[0,0,0],lut.domainMax==[1,1,1] else {throw CraftError.unsupported("Bake input shapers and domains before exporting this color grid.")}
    if format == .cube {
      let body=try ColorLUTFile.writeCube(lut)
      var data=Data();if !request.copyrightLine.isEmpty {data.append(contentsOf:("# "+request.copyrightLine+"\n").utf8)};data.append(body)
      guard data.count<=ColorLUT.maximumFileBytes else {throw CraftError.unsupported("LUT exceeds64MiB; choose fewer grid points.")};return data
    }
    if format == .icc || format == .threeDL {
      guard lut.values.allSatisfy({(0...1).contains($0)}) else {throw CraftError.unsupported("3DL and ICC integer tables require values from0to1. Use CUBE or CSP for extended-range output.")}
    }
    if format == .icc {return try profile(lut,request:request)}
    var data=Data()
    func line(_ s:String)throws {
      let bytes=Data((s+"\n").utf8);guard bytes.count<=ColorLUT.maximumFileBytes-data.count else {throw CraftError.unsupported("LUT exceeds64MiB; choose fewer grid points.")};data.append(bytes)
    }
    let n=lut.size
    if format == .csp {
      try line("CSPLUTV100\n3D\n\nBEGIN METADATA")
      try line("Description: "+lut.title)
      if !request.copyrightLine.isEmpty {try line(request.copyrightLine)}
      try line("END METADATA\n")
      for _ in 0..<3 {try line("2\n0 1\n0 1")}
      try line("\n\(n) \(n) \(n)")
      for i in stride(from:0,to:lut.values.count,by:3) {
        if i%3072==0 {try Task.checkCancellation()}
        try line("\(lut.values[i]) \(lut.values[i+1]) \(lut.values[i+2])")
      }
    }else {
      // Flame-style 10-bit input knots, 12-bit output, blue index fastest.
      // Explicit comment preserves output scale for our reader even for dark LUTs;
      // some legacy readers still infer scale from the largest sample.
      try line("# Photato 3DL — "+lut.title);try line("# PHOTATO_OUTPUT_BITS 12")
      if !request.copyrightLine.isEmpty {try line("# "+request.copyrightLine)}
      if n>3 {try line((0..<n).map{String(Int((Float($0)/Float(n-1)*1023).rounded()))}.joined(separator:" "))}
      for r in 0..<n {try Task.checkCancellation();for g in 0..<n {for b in 0..<n {
        let i=((b*n+g)*n+r)*3
        try line((0..<3).map{String(Int((lut.values[i+$0]*4095).rounded()))}.joined(separator:" "))
      }}}
    }
    return data
  }
  private static func profile(_ lut:ColorLUT,request:ColorLookupExportRequest)throws->Data {
    func u16(_ n:Int)->Data {Data([UInt8((n>>8)&255),UInt8(n&255)])}
    func u32(_ n:Int)->Data {Data([UInt8((n>>24)&255),UInt8((n>>16)&255),UInt8((n>>8)&255),UInt8(n&255)])}
    func signature(_ s:String)->Data {Data(s.utf8)}
    func mluc(_ s:String)->Data {
      let text=s.data(using:.utf16BigEndian)!
      return signature("mluc")+Data(count:4)+u32(1)+u32(12)+signature("enUS")+u32(text.count)+u32(28)+text
    }
    let n=lut.size
    var table=signature("mft2")+Data(count:4)+Data([3,3,UInt8(n),0])
    for i in 0..<9 {table.append(u32(i%4==0 ? 65536:0))}
    table.append(u16(2)+u16(2))
    for _ in 0..<3 {table.append(u16(0)+u16(65535))}
    for r in 0..<n {try Task.checkCancellation();for g in 0..<n {for b in 0..<n {
      let i=((b*n+g)*n+r)*3
      for c in 0..<3 {table.append(u16(Int((Double(lut.values[i+c])*65535).rounded())))}
    }}}
    for _ in 0..<3 {table.append(u16(0)+u16(65535))}
    // Directly sampled RGB device link; no fictitious contributing profile IDs.
    let sequence=signature("pseq")+Data(count:4)+u32(0)
    let tags:[(String,Data)]=[("desc",mluc(lut.title)),("cprt",mluc(request.copyrightLine)),("pseq",sequence),("A2B0",table)]
    var profile=Data(count:128)
    func put(_ at:Int,_ data:Data){profile.replaceSubrange(at..<at+data.count,with:data)}
    put(8,u32(0x04400000));put(12,signature("link"));put(16,signature("RGB "));put(20,signature("RGB "))
    var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
    let c=calendar.dateComponents([.year,.month,.day,.hour,.minute,.second],from:request.created)
    for (i,v)in[c.year!,c.month!,c.day!,c.hour!,c.minute!,c.second!].enumerated(){put(24+i*2,u16(v))}
    put(36,signature("acsp"));put(40,signature("APPL"));put(68,u32(0x0000f6d6)+u32(0x00010000)+u32(0x0000d32d));put(80,signature("Ptto"))
    profile.append(u32(tags.count));var offset=132+tags.count*12,body=Data()
    for (key,tag)in tags {
      profile.append(signature(key)+u32(offset)+u32(tag.count));body.append(tag)
      let padding=(4-tag.count%4)%4;body.append(Data(count:padding));offset+=tag.count+padding
    }
    profile.append(body);put(0,u32(profile.count));return profile
  }
}
extension ColorLookupExport {
  public static func files(_ document:CraftDocument,request:ColorLookupExportRequest)throws->[ColorLookupEncodedFile] {
    try request.validate();let lut=try bake(document,size:request.size,title:request.title)
    return try ColorLookupFileFormat.allCases.filter{request.formats.contains($0)}.map {format in
      try Task.checkCancellation();return .init(format:format,name:request.baseName+"."+format.rawValue,data:try ColorLookupFormats.encode(lut,format:format,request:request))
    }
  }
  public static func archive(_ files:[ColorLookupEncodedFile])throws->Data {
    try StoredZIP.encode(files.map{.init(name:$0.name,data:$0.data)},maximumBytes:ColorLookupFormats.maximumBundleBytes)
  }
}
