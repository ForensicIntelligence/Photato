import Foundation
import PhotoCraftCore

/// Public PSD placed-file transport, checked against owned Photoshop 2026 PDFs.
/// Source pages stay vector PDFs; the layer channel data is only a compatibility preview.
enum PSDPDFSmartObjects {
  struct Export {let page: Int32;let pages: Int32;let crop: Int32}
  static let crops: [PDFSmartObjectSource.Crop:Int32] = [
    .bounding:2,.media:3,.crop:4,.bleed:5,.trim:6,.art:7
  ]
  static func exportSettings(_ source: SmartObject) throws -> Export? {
    guard let selection = source.pdfSource else {return nil}
    guard selection.image == nil else {throw CraftError.unsupported("Save selected PDF images as Photato to retain their original image selection. PSD image-selection interchange is not yet supported.")}
    guard selection.antialias else {throw CraftError.unsupported("Save non-antialiased PDF sources as Photato. PSD antialias-policy interchange is not yet qualified.")}
    let pdf = try PDFImport.open(source.data,password:nil)
    guard !pdf.isEncrypted,pdf.page(at:selection.page) != nil else {throw CraftError.invalid("The retained PDF page is unavailable.")}
    return Export(page:Int32(selection.page),pages:Int32(pdf.numberOfPages),crop:crops[selection.crop]!)
  }
  static func restore(_ data: Data,fileName: String,descriptor: PSDDescriptor,
    in document: CraftDocument) throws -> (SmartObject,Surface) {
    func integer(_ key: String,_ range: ClosedRange<Int>) throws -> Int {
      guard let n = descriptor[key]?.number,n.isFinite,n.rounded() == n,
        n >= Double(range.lowerBound),n <= Double(range.upperBound) else {throw CraftError.invalid("Invalid PDF placed-file \(key).")}
      return Int(n)
    }
    guard try integer("Type",0...3) == 1 else {throw CraftError.unsupported("Only vector PDF placed-file records are supported.")}
    let page = try integer("PgNm",1...4096),pages = try integer("totalPages",1...4096)
    guard page <= pages else {throw CraftError.invalid("Invalid PDF placed-file page count.")}
    let cropCode = try integer("Crop",2...7)
    guard let crop = crops.first(where:{Int($0.value) == cropCode})?.key else {throw CraftError.invalid("Invalid PDF crop code.")}
    guard try integer("Annt",0...Int(Int32.max)) == 16 else {throw CraftError.unsupported("This PDF placed-file antialias policy is not yet qualified.")}
    guard case .object(let size) = descriptor["Sz  "],let width = size["Wdth"]?.number,
      let height = size["Hght"]?.number,width.isFinite,height.isFinite,width > 0,height > 0,
      width <= Double(Surface.maxDimension),height <= Double(Surface.maxDimension),
      case .unit(let unit,let bits) = descriptor["Rslt"],unit == Data("#Rsl".utf8) else {
      throw CraftError.invalid("Invalid PDF placed-file size or resolution.")
    }
    var settings = PDFImportSettings();settings.pages = [page]
    settings.crop = PDFImportSettings.Crop(rawValue:crop.rawValue)!;settings.resolution = Double(bitPattern:bits)
    let pdf = try PDFImport.open(data,password:nil)
    guard pdf.numberOfPages == pages else {throw CraftError.invalid("PDF source page count disagrees with its placed-file descriptor.")}
    var (source,_) = try PDFSmartObjectIO.embedded(data,fileName:fileName,in:document,settings:settings)
    source.width = Int(ceil(width));source.height = Int(ceil(height));try source.validate()
    return (source,try PDFSmartObjectIO.surface(source,width:source.width,height:source.height,in:document))
  }
}
