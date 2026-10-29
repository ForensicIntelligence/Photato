import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore

/// Shared page-import engine. Native dialogs and automation must explicitly select
/// pages; ordinary image opening must not silently choose a PDF's first page.
public struct PDFImportSettings: Codable, Equatable, Sendable {
  public enum Crop: String, Codable, CaseIterable, Sendable {
    case bounding, media, crop, bleed, trim, art
    var box: CGPDFBox {
      switch self {
      case .bounding, .trim: .trimBox
      case .media: .mediaBox
      case .crop: .cropBox
      case .bleed: .bleedBox
      case .art: .artBox
      }
    }
  }
  public var pages = [1]
  public var crop: Crop = .bounding
  public var resolution = 300.0
  public var width: Int?
  public var height: Int?
  public var constrainProportions = true
  public var antialias = true
  public var mode: DocumentColorMode = .rgb
  public var depth: PixelDepth = .u8
  public var profile: Data?
  public init() {}
  public func validate() throws {
    guard !pages.isEmpty, pages.count <= PDFImport.maximumOutputPages,
      Set(pages).count == pages.count, pages.allSatisfy({ $0 > 0 }),
      resolution.isFinite, (1...10000).contains(resolution),
      [width,height].compactMap({$0}).allSatisfy({(1...Surface.maxDimension).contains($0)}),
      DocumentColorMode.componentModes.contains(mode), mode.depths.contains(depth) else {
      throw CraftError.invalid("Choose distinct PDF pages, valid dimensions, resolution, color mode and bit depth.")
    }
    if let profile { try NativeModeProfile.validate(profile,mode:mode,depth:depth) }
  }
}

public struct PDFPageInfo: Codable, Equatable, Sendable {
  public let number: Int
  public let rotation: Int
  /// Oriented width and height in PDF points, including inherited page boxes.
  public let boxes: [String:[Double]]
}
public struct PDFImportInfo: Codable, Equatable, Sendable {
  public let pages: [PDFPageInfo]
  public let encrypted: Bool
}

public enum PDFImport {
  public static let maximumSourceBytes = 64 * 1024 * 1024
  public static let maximumOutputPages = 32
  public static let maximumPageCount = 4096
  public static let maximumDecodedBytes = 512 * 1024 * 1024
  public static func recognizes(_ data: Data) -> Bool {
    guard let header = data.prefix(1024).range(of:Data("%PDF-".utf8)) else {return false}
    if header.lowerBound == data.startIndex {return true}
    // A PDF header may follow leading bytes, but text metadata in another
    // supported container must not turn an ordinary image/document into a PDF.
    for signature in ["PHOTATO\0", "bplist00", "8BPS"] {
      if data.starts(with:Data(signature.utf8)) {return false}
    }
    if let image = CGImageSourceCreateWithData(data as CFData,
      [kCGImageSourceShouldCache:false] as CFDictionary), CGImageSourceGetCount(image) > 0,
      let type = CGImageSourceGetType(image), type as String != "com.adobe.pdf" {
      return false
    }
    return true
  }
  static func open(_ data: Data,password: String?) throws -> CGPDFDocument {
    try Task.checkCancellation()
    guard !data.isEmpty, data.count <= maximumSourceBytes, recognizes(data),
      let provider = CGDataProvider(data:data as CFData), let pdf = CGPDFDocument(provider) else {
      throw CraftError.invalid("Choose a valid PDF file no larger than64MiB.")
    }
    if !pdf.isUnlocked, let password {
      guard password.utf8.count <= 1024, !password.contains("\0") else {throw CraftError.invalid("The PDF password is invalid.")}
      _ = password.withCString {pdf.unlockWithPassword($0)}
    }
    guard pdf.isUnlocked else {throw CraftError.unsupported("This PDF requires its password before importing.")}
    guard (1...maximumPageCount).contains(pdf.numberOfPages) else {throw CraftError.unsupported("PDF import supports one to4096 source pages.")}
    return pdf
  }
  static func orientedBox(_ page: CGPDFPage,_ box: CGPDFBox) throws -> CGRect {
    let media = page.getBoxRect(.mediaBox),rect = page.getBoxRect(box).intersection(media)
    guard !rect.isNull, !rect.isInfinite,
      [rect.minX,rect.minY,rect.width,rect.height].allSatisfy(\.isFinite),
      rect.width > 0, rect.height > 0, rect.width <= 1_000_000, rect.height <= 1_000_000 else {
      throw CraftError.invalid("The PDF contains invalid or empty page bounds.")
    }
    let rotation = ((page.rotationAngle % 360)+360)%360
    guard rotation % 90 == 0 else {throw CraftError.unsupported("PDF page rotation must be a multiple of90degrees.")}
    return CGRect(x:0,y:0,width:rotation % 180 == 0 ? rect.width:rect.height,
      height:rotation % 180 == 0 ? rect.height:rect.width)
  }
  public static func inspect(_ data: Data,password: String? = nil) throws -> PDFImportInfo {
    let pdf = try open(data,password:password)
    let pages = try (1...pdf.numberOfPages).map {number in
      try Task.checkCancellation()
      guard let page = pdf.page(at:number) else {throw CraftError.invalid("A PDF page is missing.")}
      var boxes: [String:[Double]] = [:]
      for crop in PDFImportSettings.Crop.allCases where crop != .bounding {
        let rect = try orientedBox(page,crop.box);boxes[crop.rawValue] = [rect.width,rect.height]
      }
      return PDFPageInfo(number:number,rotation:Int(page.rotationAngle),boxes:boxes)
    }
    return PDFImportInfo(pages:pages,encrypted:pdf.isEncrypted)
  }
  public static func thumbnail(_ data: Data,page: Int,password: String? = nil) throws -> Data {
    var settings = PDFImportSettings();settings.pages = [page];settings.crop = .media
    settings.resolution = 72;settings.width = 160;settings.height = 160
    let document = try pages(data,name:"Preview",settings:settings,password:password,
      maximumPixels:160*160,maximumBytes:8*1024*1024)[0]
    return try RasterIO.encoded(document)
  }
  struct Plan {
    let page: CGPDFPage
    let full: CGRect
    var region: CGRect
    let number: Int
  }
  static func dimensions(_ size: CGSize,maximumPixels: Int) throws -> (Int,Int) {
    let w = size.width.rounded(),h = size.height.rounded()
    guard w.isFinite,h.isFinite,w >= 1,h >= 1,w <= Double(Surface.maxDimension),
      h <= Double(Surface.maxDimension),maximumPixels > 0,w*h <= Double(maximumPixels) else {
      throw CraftError.invalid("The requested PDF dimensions exceed the pixel or side-length limit.")
    }
    return (Int(w),Int(h))
  }
  static func surface(_ plan: Plan,box: CGPDFBox,width: Int,height: Int,
    depth: PixelDepth,antialias: Bool,maximumBytes: Int) throws -> Surface {
    try Task.checkCancellation()
    // Float bitmap + native tiles + conversion scratch must fit before allocation.
    let tiles = ((width+63)/64)*((height+63)/64)*65536
    guard width*height <= maximumBytes/32, tiles <= maximumBytes-width*height*32 else {
      throw CraftError.invalid("PDF rendering exceeds the decoded-memory budget.")
    }
    let space = depth == .f32 ? CGColorSpace(name:CGColorSpace.linearSRGB)!:try RasterIO.colorSpace()
    // Quartz's Float32 PDF image scaling repeats source columns on the current
    // platform (owned two-pixel fixture). A 16-bit render buffer preserves the
    // image geometry; RasterIO then converts into the requested editing depth.
    // Float32 PDF import therefore has a 16-bit intermediate, tracked as an
    // unqualified precision/HDR difference rather than claimed Adobe equality.
    guard let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:16,
      bytesPerRow:width*8,space:space,bitmapInfo:CGBitmapInfo.byteOrder16Little.rawValue
        | CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw CraftError.unavailable("Could not allocate the PDF rendering buffer.")
    }
    context.setAllowsAntialiasing(antialias);context.setShouldAntialias(antialias)
    context.setShouldSmoothFonts(false)
    context.interpolationQuality = antialias ? .high:.none
    // Quartz bitmap images already become top-down surfaces through RasterIO.
    // Applying a view-style Y flip here would invert the PDF a second time.
    context.scaleBy(x:CGFloat(width)/plan.region.width,y:CGFloat(height)/plan.region.height)
    context.translateBy(x:-plan.region.minX,y:-plan.region.minY)
    context.concatenate(plan.page.getDrawingTransform(box,rect:plan.full,rotate:0,preserveAspectRatio:false))
    context.drawPDFPage(plan.page)
    try Task.checkCancellation()
    guard let image = context.makeImage() else {throw CraftError.invalid("The PDF page could not be rendered.")}
    return try RasterIO.surface(image,depth:depth,space:space,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
  }
  static func plan(_ pdf: CGPDFDocument, number: Int, settings: PDFImportSettings,
    maximumPixels: Int, maximumBytes: Int) throws -> Plan {
      guard let page = pdf.page(at:number) else {throw CraftError.invalid("A selected PDF page does not exist.")}
      let full = try orientedBox(page,settings.crop.box)
      var plan = Plan(page:page,full:full,region:full,number:number)
      if settings.crop == .bounding {
        let (w,h) = try dimensions(CGSize(width:full.width*settings.resolution/72,height:full.height*settings.resolution/72),maximumPixels:maximumPixels)
        let rendered = try surface(plan,box:settings.crop.box,width:w,height:h,depth:.f32,
          antialias:settings.antialias,maximumBytes:maximumBytes)
        if let bounds = try rendered.contentBounds() {
          // Alpha bounds at the requested resolution, not a claim of Adobe's
          // proprietary vector-content bounding algorithm. Blank pages retain trim.
          plan.region = CGRect(x:Double(bounds.x)*full.width/Double(w),
            y:Double(h-bounds.y-bounds.height)*full.height/Double(h),
            width:Double(bounds.width)*full.width/Double(w),height:Double(bounds.height)*full.height/Double(h))
        }
      }
    return plan
  }
  public static func pages(_ data: Data,name: String,settings: PDFImportSettings,
    password: String? = nil,maximumPixels: Int = Surface.maxPixels,
    maximumBytes: Int = maximumDecodedBytes) throws -> [CraftDocument] {
    try settings.validate();try Task.checkCancellation()
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf8.count <= 240,
      maximumBytes > 0 else {throw CraftError.invalid("Choose a PDF document name of at most240bytes and a positive memory budget.")}
    let pdf = try open(data,password:password)
    let pixelLimit = settings.mode == .rgb ? maximumPixels:min(maximumPixels,NativeModeRaster.maximumPixels)
    var plans: [Plan] = []
    for number in settings.pages {
      try Task.checkCancellation()
      let plan = try plan(pdf,number:number,settings:settings,maximumPixels:pixelLimit,maximumBytes:maximumBytes)
      plans.append(plan)
    }
    let maxW = plans.map(\.region.width).max()!,maxH = plans.map(\.region.height).max()!
    let dpiScale = settings.resolution/72
    let targetW = settings.width.map(Double.init) ?? maxW*dpiScale
    let targetH = settings.height.map(Double.init) ?? maxH*dpiScale
    let explicitSize = settings.width != nil || settings.height != nil
    let scale: Double
    if settings.width != nil,settings.height != nil {scale = min(targetW/maxW,targetH/maxH)}
    else if settings.width != nil {scale = targetW/maxW}
    else if settings.height != nil {scale = targetH/maxH}
    else {scale = dpiScale}
    let sizes = try plans.map {plan in
      let size = !settings.constrainProportions && explicitSize
        ? CGSize(width:targetW,height:targetH)
        : CGSize(width:plan.region.width*scale,height:plan.region.height*scale)
      return try dimensions(size,maximumPixels:pixelLimit)
    }
    // All output geometry is checked before creating any returned documents.
    guard sizes.reduce(0,{$0+$1.0*$1.1}) <= maximumBytes/16 else {
      throw CraftError.invalid("The selected PDF pages exceed the combined decoded-memory budget.")
    }
    var result: [CraftDocument] = [],used = 0
    for (i,plan) in plans.enumerated() {
      try Task.checkCancellation();let (w,h) = sizes[i]
      let pixels = try surface(plan,box:settings.crop.box,width:w,height:h,depth:settings.depth,
        antialias:settings.antialias,maximumBytes:maximumBytes-used)
      var document = try CraftDocument(width:w,height:h,depth:settings.depth,
        name:plans.count == 1 ? name:"\(name)-\(plan.number)")
      document.layers[0].name = "Layer 1";document.layers[0].content = .raster(pixels)
      document.resolution = settings.resolution
      if settings.mode != .rgb || settings.profile != nil {
        document = try document.convertingMode(.init(mode:settings.mode,depth:settings.depth,profile:settings.profile))
      }
      try document.validate();used += document.estimatedBytes
      guard used <= maximumBytes else {throw CraftError.invalid("Imported PDF documents exceed the decoded-memory budget.")}
      result.append(document)
    }
    try Task.checkCancellation();return result
  }
}
