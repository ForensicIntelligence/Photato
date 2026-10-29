import CoreGraphics
import Foundation
import PhotoCraftCore

public struct PDFImageInfo: Codable,Equatable,Sendable {
  public let number: Int
  public let page: Int
  public let width: Int
  public let height: Int
  public let bitsPerComponent: Int
  public let imageMask: Bool
  public let colorSpace: String
}
public struct PDFImageImportSettings: Codable,Equatable,Sendable {
  public var images = [1]
  public var resolution = 72.0
  public var mode: DocumentColorMode = .rgb
  public var depth: PixelDepth = .u8
  public init() {}
  public func validate() throws {
    guard !images.isEmpty,images.count <= 32,Set(images).count == images.count,
      images.allSatisfy({(1...4096).contains($0)}),resolution.isFinite,(1...10000).contains(resolution),
      DocumentColorMode.componentModes.contains(mode),mode.depths.contains(depth) else {throw CraftError.invalid("Choose distinct PDF images, valid resolution, color mode and depth.")}
  }
}
public enum PDFImages {
  private struct Key: Hashable {let stream: CGPDFStreamRef;let color: CGPDFObjectRef?}
  private final class Scan {
    let selected: Set<Int>
    let limit: Int
    var info: [PDFImageInfo] = []
    var pages: [Int:Data] = [:]
    var seen = Set<Key>()
    var active = Set<CGPDFStreamRef>()
    var failure: Error?
    var page = 0
    var operations = 0
    var used = 0
    init(selected: Set<Int>,limit: Int) {self.selected = selected;self.limit = limit}
    func scan(_ content: CGPDFContentStreamRef) throws {
      try Task.checkCancellation()
      guard active.count <= 32 else {throw CraftError.invalid("The PDF contains excessively nested Form images.")}
      guard let table = CGPDFOperatorTableCreate() else {throw CraftError.unavailable("Could not create the PDF image scanner.")}
      CGPDFOperatorTableSetCallback(table,"Do") {scanner,context in Unmanaged<Scan>.fromOpaque(context!).takeUnretainedValue().visit(scanner,inline:false)}
      CGPDFOperatorTableSetCallback(table,"EI") {scanner,context in Unmanaged<Scan>.fromOpaque(context!).takeUnretainedValue().visit(scanner,inline:true)}
      let scanner = CGPDFScannerCreate(content,table,Unmanaged.passUnretained(self).toOpaque())
      let scanned = CGPDFScannerScan(scanner)
      if let failure {throw failure}
      guard scanned else {throw CraftError.invalid("The PDF image content stream is damaged.")}
    }
    func visit(_ scanner: CGPDFScannerRef,inline: Bool) {
      guard failure == nil else{return}
      do {
        try Task.checkCancellation();operations += 1
        guard operations <= 100000 else {throw CraftError.invalid("The PDF contains too many image/form operations.")}
        let content = CGPDFScannerGetContentStream(scanner)
        var stream: CGPDFStreamRef?
        if inline {guard CGPDFScannerPopStream(scanner,&stream) else {throw CraftError.invalid("Missing inline PDF image.")}}
        else {
          var name: UnsafePointer<CChar>?
          guard CGPDFScannerPopName(scanner,&name),let name,
            let object = CGPDFContentStreamGetResource(content,"XObject",name),CGPDFObjectGetValue(object,.stream,&stream) else {throw CraftError.invalid("Missing PDF image/form resource.")}
        }
        guard let stream,let dict = CGPDFStreamGetDictionary(stream) else {throw CraftError.invalid("Missing PDF image dictionary.")}
        var subtype: UnsafePointer<CChar>?;_ = CGPDFDictionaryGetName(dict,"Subtype",&subtype)
        let type = inline ? "Image":(subtype.map{String(cString:$0)} ?? "")
        if type == "Form" {
          guard active.insert(stream).inserted else {throw CraftError.invalid("The PDF contains a cyclic Form resource.")};defer {active.remove(stream)}
          var resources: CGPDFDictionaryRef?;_ = CGPDFDictionaryGetDictionary(dict,"Resources",&resources)
          try scan(CGPDFContentStreamCreateWithStream(stream,resources ?? dict,content));return
        }
        guard type == "Image" else {return}
        func integer(_ key: String,_ short: String) -> Int {var v = 0;if !CGPDFDictionaryGetInteger(dict,key,&v) {_ = CGPDFDictionaryGetInteger(dict,short,&v)};return v}
        let width = integer("Width","W"),height = integer("Height","H"),bits = integer("BitsPerComponent","BPC")
        guard (1...Surface.maxDimension).contains(width),(1...Surface.maxDimension).contains(height),[0,1,2,4,8,16].contains(bits) else {throw CraftError.unsupported("Unsupported PDF image dimensions or bit depth.")}
        var mask: CGPDFBoolean = 0;if !CGPDFDictionaryGetBoolean(dict,"ImageMask",&mask) {_ = CGPDFDictionaryGetBoolean(dict,"IM",&mask)}
        var color: CGPDFObjectRef?;if !CGPDFDictionaryGetObject(dict,"ColorSpace",&color) {_ = CGPDFDictionaryGetObject(dict,"CS",&color)}
        var colorName = mask != 0 ? "Stencil":"Embedded"
        if let object = color,CGPDFObjectGetType(object) == .name {
          var name: UnsafePointer<CChar>?;CGPDFObjectGetValue(object,.name,&name)
          if let name {colorName = String(cString:name);color = CGPDFContentStreamGetResource(content,"ColorSpace",name) ?? object}
        }
        // Inline stream handles can be reused by the scanner after a callback;
        // copy selected images while their content/resource context is alive.
        if !inline,!seen.insert(Key(stream:stream,color:color)).inserted {return}
        guard info.count < 4096 else {throw CraftError.invalid("A PDF can expose at most4096 images in this import workflow.")}
        let number = info.count+1
        info.append(PDFImageInfo(number:number,page:page,width:width,height:height,bitsPerComponent:mask != 0 ? 1:bits,imageMask:mask != 0,colorSpace:colorName))
        if selected.contains(number) {
          let data = try PDFImageArchive(resources:content,limit:min(PDFImport.maximumSourceBytes,limit-used)).page(stream,width:width,height:height)
          used += data.count;pages[number] = data
        }
      } catch {failure = error}
    }
  }
  private static func discover(_ data: Data,password: String?,selected: Set<Int>,maximumBytes: Int) throws -> Scan {
    guard maximumBytes > 0 else {throw CraftError.invalid("Choose a positive PDF image memory budget.")}
    let pdf = try PDFImport.open(data,password:password),scan = Scan(selected:selected,limit:maximumBytes)
    for number in 1...pdf.numberOfPages {
      try Task.checkCancellation();scan.page = number
      guard let page = pdf.page(at:number) else {throw CraftError.invalid("Missing PDF image source page.")}
      try scan.scan(CGPDFContentStreamCreateWithPage(page))
    }
    return scan
  }
  public static func inspect(_ data: Data,password: String? = nil) throws -> [PDFImageInfo] {
    try discover(data,password:password,selected:[],maximumBytes:PDFImport.maximumDecodedBytes).info
  }
  /// Copies only the selected image graph for rendering; callers retain the
  /// original whole PDF as the editable/source-download identity.
  static func selectedPage(_ data: Data, image: Int) throws -> (PDFImageInfo,Data) {
    guard (1...4096).contains(image) else {throw CraftError.invalid("Choose one embedded PDF image.")}
    let scan = try discover(data,password:nil,selected:[image],maximumBytes:PDFImport.maximumSourceBytes)
    guard let page = scan.pages[image],let info = scan.info.first(where:{$0.number == image}) else {
      throw CraftError.invalid("The embedded PDF image does not exist.")
    }
    return (info,page)
  }
  public static func documents(_ data: Data,name: String,settings: PDFImageImportSettings,password: String? = nil,
    maximumPixels: Int = Surface.maxPixels,maximumBytes: Int = PDFImport.maximumDecodedBytes) throws -> [CraftDocument] {
    try settings.validate()
    let scan = try discover(data,password:password,selected:Set(settings.images),maximumBytes:maximumBytes)
    guard scan.pages.count == settings.images.count else {throw CraftError.invalid("A selected embedded PDF image does not exist.")}
    var documents:[CraftDocument] = [],used = scan.used
    for number in settings.images {
      try Task.checkCancellation();let info = scan.info[number-1]
      guard info.width <= maximumPixels/info.height else {throw CraftError.invalid("The selected PDF image exceeds the pixel limit.")}
      var options = PDFImportSettings();options.crop = .media;options.resolution = 72;options.mode = settings.mode;options.depth = settings.depth;options.antialias = false
      var document = try PDFImport.pages(scan.pages[number]!,name:settings.images.count == 1 ? name:"\(name)-\(number)",settings:options,maximumPixels:maximumPixels,maximumBytes:maximumBytes-used)[0]
      document.resolution = settings.resolution;used += document.estimatedBytes
      guard used <= maximumBytes else {throw CraftError.invalid("Selected PDF images exceed the decoded-memory budget.")}
      documents.append(document)
    }
    try Task.checkCancellation();return documents
  }
  public static func thumbnail(_ data: Data,image: Int,password: String? = nil) throws -> Data {
    guard (1...4096).contains(image) else {throw CraftError.invalid("Choose an embedded PDF image.")}
    let scan = try discover(data,password:password,selected:[image],maximumBytes:PDFImport.maximumDecodedBytes)
    guard let page = scan.pages[image] else {throw CraftError.invalid("The embedded PDF image does not exist.")}
    return try PDFImport.thumbnail(page,page:1)
  }
}
