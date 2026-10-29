import CoreGraphics
import Foundation
import PhotoCraftCore

/// Copies an image's PDF object graph through public CoreGraphics accessors. An
/// isolated page lets Quartz apply palettes, Decode arrays, profiles and masks
/// without treating a crop of the original painted page as the source image.
final class PDFImageArchive {
  let resources: CGPDFContentStreamRef
  let limit: Int
  var objects: [Data] = Array(repeating:Data(),count:4)
  var streams: [CGPDFStreamRef:Int] = [:]
  var active = Set<CGPDFObjectRef>()
  var activeStreams = Set<CGPDFStreamRef>()
  var nodes = 0
  var used = 0
  init(resources: CGPDFContentStreamRef,limit: Int) {self.resources = resources;self.limit = limit}
  static func name(_ value: String) -> String {
    "/"+value.utf8.map {b in (33...126).contains(b) && !Array("#%()/<>[]{}".utf8).contains(b) ? String(UnicodeScalar(b)):String(format:"#%02X",b)}.joined()
  }
  func account(_ count: Int) throws {
    guard count >= 0,count <= limit-used else {throw CraftError.invalid("Embedded PDF image data exceeds the memory budget.")};used += count
  }
  func value(_ object: CGPDFObjectRef,depth: Int = 0,color: Bool = false) throws -> String {
    try Task.checkCancellation();nodes += 1
    guard nodes <= 4096,depth <= 32,!active.contains(object) else {throw CraftError.invalid("The PDF image contains an excessive or cyclic object graph.")}
    active.insert(object);defer {active.remove(object)}
    switch CGPDFObjectGetType(object) {
    case .null:return "null"
    case .boolean:var v: CGPDFBoolean = 0;CGPDFObjectGetValue(object,.boolean,&v);return v == 0 ? "false":"true"
    case .integer:var v = 0;CGPDFObjectGetValue(object,.integer,&v);return String(v)
    case .real:
      var v: CGPDFReal = 0;CGPDFObjectGetValue(object,.real,&v)
      guard v.isFinite else {throw CraftError.invalid("Invalid PDF image numeric value.")};return String(format:"%.12f",locale:Locale(identifier:"en_US_POSIX"),Double(v))
    case .name:
      var p: UnsafePointer<CChar>?;CGPDFObjectGetValue(object,.name,&p)
      guard let p else {throw CraftError.invalid("Invalid PDF image name.")};var s = String(cString:p)
      if color {
        s = ["G":"DeviceGray","RGB":"DeviceRGB","CMYK":"DeviceCMYK","I":"Indexed"][s] ?? s
        if !["DeviceGray","DeviceRGB","DeviceCMYK","Pattern","Indexed","CalGray","CalRGB","Lab","ICCBased","Separation","DeviceN"].contains(s),let resolved = CGPDFContentStreamGetResource(resources,"ColorSpace",p) {return try value(resolved,depth:depth+1,color:true)}
      }
      return Self.name(s)
    case .string:
      var v: CGPDFStringRef?;CGPDFObjectGetValue(object,.string,&v)
      guard let v else {throw CraftError.invalid("Invalid PDF image string.")}
      let n = CGPDFStringGetLength(v);try account(n*2)
      guard n > 0 else {return "<>"};guard let bytes = CGPDFStringGetBytePtr(v) else {throw CraftError.invalid("Missing PDF string data.")}
      return "<"+UnsafeBufferPointer(start:bytes,count:n).map{String(format:"%02X",$0)}.joined()+">"
    case .array:
      var a: CGPDFArrayRef?;CGPDFObjectGetValue(object,.array,&a);guard let a else {throw CraftError.invalid("Invalid PDF image array.")}
      let count = CGPDFArrayGetCount(a);guard count <= 4096 else {throw CraftError.invalid("The PDF image array is too large.")}
      var values:[String] = []
      var firstName: UnsafePointer<CChar>?;_ = CGPDFArrayGetName(a,0,&firstName)
      let family = firstName.map{String(cString:$0)} ?? ""
      let baseIndex = ["Indexed","I","Pattern"].contains(family) ? 1:(["Separation","DeviceN"].contains(family) ? 2:-1)
      for i in 0..<count {var item: CGPDFObjectRef?;guard CGPDFArrayGetObject(a,i,&item),let item else {throw CraftError.invalid("Missing PDF array value.")};values.append(try value(item,depth:depth+1,color:color && (i == 0 || i == baseIndex)))}
      return "["+values.joined(separator:" ")+"]"
    case .dictionary:
      var d: CGPDFDictionaryRef?;CGPDFObjectGetValue(object,.dictionary,&d);guard let d else {throw CraftError.invalid("Invalid PDF image dictionary.")}
      return "<< "+(try dictionary(d,depth:depth+1)).joined(separator:" ")+" >>"
    case .stream:
      var s: CGPDFStreamRef?;CGPDFObjectGetValue(object,.stream,&s);guard let s else {throw CraftError.invalid("Missing PDF image stream.")};return "\(try copy(s,depth:depth+1)) 0 R"
    @unknown default:throw CraftError.unsupported("Unsupported PDF image object.")
    }
  }
  static func entries(_ dict: CGPDFDictionaryRef) -> [(String,CGPDFObjectRef)] {
    var values:[(String,CGPDFObjectRef)] = []
    CGPDFDictionaryApplyBlock(dict,{key,value,_ in values.append((String(cString:key),value));return true},nil)
    return values.sorted{$0.0 < $1.0}
  }
  func dictionary(_ dict: CGPDFDictionaryRef,depth: Int,omit: Set<String> = []) throws -> [String] {
    var result:[String] = []
    let aliases = ["W":"Width","H":"Height","BPC":"BitsPerComponent","CS":"ColorSpace","D":"Decode","IM":"ImageMask","I":"Interpolate","F":"Filter","DP":"DecodeParms"]
    for (key,object) in Self.entries(dict) {
      let key = aliases[key] ?? key
      guard !omit.contains(key) else {continue}
      result.append(Self.name(key)+" "+(try value(object,depth:depth,color:key == "ColorSpace")))
    }
    return result
  }
  func copy(_ stream: CGPDFStreamRef,depth: Int = 0) throws -> Int {
    try Task.checkCancellation()
    guard !activeStreams.contains(stream) else {throw CraftError.invalid("The PDF image contains a cyclic stream graph.")}
    if let number = streams[stream] {return number}
    activeStreams.insert(stream);defer {activeStreams.remove(stream)}
    guard depth <= 32,objects.count < 4096,let dict = CGPDFStreamGetDictionary(stream) else {throw CraftError.invalid("Excessive PDF image stream graph.")}
    var width = 0,height = 0
    _ = CGPDFDictionaryGetInteger(dict,"Width",&width);if width == 0 {_ = CGPDFDictionaryGetInteger(dict,"W",&width)}
    _ = CGPDFDictionaryGetInteger(dict,"Height",&height);if height == 0 {_ = CGPDFDictionaryGetInteger(dict,"H",&height)}
    if width != 0 || height != 0 {
      guard width > 0,height > 0,width <= Surface.maxDimension,height <= Surface.maxDimension,
        width <= min(Surface.maxPixels,PDFImport.maximumDecodedBytes/16)/height else {throw CraftError.invalid("Embedded PDF image dimensions exceed the memory budget.")}
    }
    let number = objects.count+1;objects.append(Data());streams[stream] = number
    var format = CGPDFDataFormat.raw
    guard let decoded = CGPDFStreamCopyData(stream,&format) else {throw CraftError.unsupported("Could not decode an embedded PDF image stream.")}
    let data = decoded as Data;try account(data.count)
    // Quartz has decoded preceding filters. Keep only the remaining image codec.
    var fields = try dictionary(dict,depth:depth+1,omit:["Length","Filter","DecodeParms","Type","Subtype"])
    if width > 0 {fields += ["/Type /XObject","/Subtype /Image"]}
    switch format {
    case .raw:break
    case .jpegEncoded:
      fields.append("/Filter /DCTDecode")
      // DCT ColorTransform is the only DCT DecodeParms field; preserve it when
      // the source filter is DCT or the last member of a decoded filter chain.
      var parms: CGPDFObjectRef?
      if CGPDFDictionaryGetObject(dict,"DecodeParms",&parms),let parms {
        if CGPDFObjectGetType(parms) == .dictionary {fields.append("/DecodeParms "+(try value(parms,depth:depth+1)))}
        else if CGPDFObjectGetType(parms) == .array {
          var array: CGPDFArrayRef?;CGPDFObjectGetValue(parms,.array,&array)
          if let array,CGPDFArrayGetCount(array)>0 {var last: CGPDFObjectRef?;CGPDFArrayGetObject(array,CGPDFArrayGetCount(array)-1,&last);if let last {fields.append("/DecodeParms "+(try value(last,depth:depth+1)))}}
        }
      }
    case .JPEG2000:fields.append("/Filter /JPXDecode")
    @unknown default:throw CraftError.unsupported("Unsupported embedded PDF image encoding.")
    }
    fields.append("/Length \(data.count)")
    let body = Data(("<< "+fields.joined(separator:" ")+" >>\nstream\n").utf8)+data+Data("\nendstream".utf8)
    try account(body.count-data.count);objects[number-1] = body;return number
  }
  func page(_ stream: CGPDFStreamRef,width: Int,height: Int) throws -> Data {
    let image = try copy(stream)
    objects[0] = Data("<< /Type /Catalog /Pages 2 0 R >>".utf8)
    objects[1] = Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8)
    objects[2] = Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(width) \(height)] /Resources << /XObject << /Image \(image) 0 R >> >> /Contents 4 0 R >>".utf8)
    let content = "q \(width) 0 0 \(height) 0 0 cm /Image Do Q\n"
    objects[3] = Data("<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream".utf8)
    var result = Data("%PDF-1.7\n".utf8),offsets:[Int] = []
    for (i,object) in objects.enumerated() {try Task.checkCancellation();offsets.append(result.count);result.append(Data("\(i+1) 0 obj\n".utf8));result.append(object);result.append(Data("\nendobj\n".utf8))}
    let start = result.count;result.append(Data("xref\n0 \(objects.count+1)\n0000000000 65535 f \n".utf8))
    for offset in offsets {result.append(Data(String(format:"%010d 00000 n \n",offset).utf8))}
    result.append(Data("trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n".utf8))
    guard result.count <= limit else {throw CraftError.invalid("Extracted PDF image exceeds its memory budget.")};return result
  }
}
