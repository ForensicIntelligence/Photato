import Foundation
import UniformTypeIdentifiers
import PhotoCraftCore

extension LinkedSmartObjectIO {
  /// Byte signatures follow the licensed PhotoCraft linked.rs classifier; PDF and
  /// empty-cache MIME fallback are native additions. Unknown data is not labelled TIFF.
  public static func photoshopLinkedFileType(_ source:SmartObject)throws->String {
    if source.mediaType=="application/vnd.photato.document" {throw CraftError.unsupported("Photoshop cannot read linked Photato originals. Use a Photato package, or convert the original to a Photoshop-supported file format.")}
    let data=source.data
    if PDFImport.recognizes(data){return "PDF "}
    if data.starts(with:Data([56,66,80,83,0,2])){return "8BPB"}
    if data.starts(with:Data("8BPS".utf8)){return "8BPS"}
    if data.starts(with:Data([0x89,80,78,71])){return "PNGf"}
    if data.starts(with:Data([0xff,0xd8])){return "JPEG"}
    if data.starts(with:Data([73,73,42,0])) || data.starts(with:Data([77,77,0,42])){return "TIFF"}
    if data.starts(with:Data("GIF".utf8)){return "GIFf"}
    switch source.mediaType {
    case "application/pdf":return "PDF "
    case "image/png":return "PNGf"
    case "image/jpeg":return "JPEG"
    case "image/tiff":return "TIFF"
    case "image/gif":return "GIFf"
    case "image/vnd.adobe.photoshop":return "8BPS"
    case "application/x-photoshop":return "8BPB"
    default:return "    "
    }
  }
  public static func photoshopLinkedMediaType(fileType:String,fileName:String)->String {
    switch fileType {
    case "PDF ":return "application/pdf"
    case "PNGf":return "image/png"
    case "JPEG":return "image/jpeg"
    case "TIFF":return "image/tiff"
    case "GIFf":return "image/gif"
    case "8BPS":return "image/vnd.adobe.photoshop"
    case "8BPB":return "application/x-photoshop"
    default:
      let ext=(fileName as NSString).pathExtension.lowercased()
      if ext=="psb"{return "application/x-photoshop"}
      if ext=="psd"{return "image/vnd.adobe.photoshop"}
      if ext=="photato"{return "application/vnd.photato.document"}
      let mime=UTType(filenameExtension:ext)?.preferredMIMEType
      return ["application/pdf","image/png","image/jpeg","image/tiff","image/gif","image/bmp","image/heic"].contains(mime ?? "") ? mime!:"application/octet-stream"
    }
  }

}
