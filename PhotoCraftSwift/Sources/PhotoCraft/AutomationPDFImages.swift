import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum PDFImageImportAPI {
  static let inspectPath = "/v1/pdf/images"
  static let importPath = "/v1/documents/import/pdf/images"
  static var schema: [String:Any] {
    BrushAPI.object(["images":["type":"array","minItems":1,"maxItems":32,"uniqueItems":true,"items":["type":"integer","minimum":1,"maximum":4096]],
      "resolution":["type":"number","minimum":1,"maximum":10000],
      "mode":["type":"string","enum":DocumentColorMode.componentModes.map(\.rawValue)],
      "depth":["type":"string","enum":PixelDepth.allCases.map(\.rawValue)]])
  }
  static func options(_ value: String?) throws -> PDFImageImportSettings {
    do {
      guard let value else{return .init()}
      guard value.utf8.count <= 4096 else {throw CraftError.invalid("PDF image options exceed4KiB.")}
      let raw = try JSONDecoder().decode(AutomationValue.self,from:Data(value.utf8))
      let merged = try BrushAPI.merge(raw,schema:schema,base:BrushAPI.json(PDFImageImportSettings()),path:"pdfImages")
      let options = try JSONDecoder().decode(PDFImageImportSettings.self,from:JSONSerialization.data(withJSONObject:merged))
      try options.validate();return options
    } catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
  static var capabilities: [String:Any] {
    let item = BrushAPI.object(["number":["type":"integer","minimum":1,"maximum":4096],"page":["type":"integer","minimum":1,"maximum":4096],
      "width":["type":"integer","minimum":1,"maximum":Surface.maxDimension],"height":["type":"integer","minimum":1,"maximum":Surface.maxDimension],
      "bitsPerComponent":["type":"integer","enum":[0,1,2,4,8,16]],"imageMask":["type":"boolean"],"colorSpace":["type":"string"]],required:["number","page","width","height","bitsPerComponent","imageMask","colorSpace"])
    return ["inspect":["method":"POST","path":inspectPath,"resultSchema":BrushAPI.object(["images":["type":"array","maxItems":4096,"items":item],"thumbnails":["type":"object","additionalProperties":BrushAPI.object(["contentType":["type":"string","const":"image/png"],"data":["type":"string","contentEncoding":"base64"]],required:["contentType","data"])]],required:["images","thumbnails"])],
      "import":["method":"POST","path":importPath,"successStatus":201,"optionsHeader":"X-Photato-PDF-Options","schema":schema,"result":"Same atomic {documents:[shared document state,...],count:N} result as page import."],
      "headers":"Same application/pdf body, optional password/name and inspection thumbnail-selection headers as PDF page routes; thumbnail IDs here identify images.",
      "cancelPath":PDFImportAPI.cancelPath,
      "defaults":"Image1;72ppi;RGB8. Resolution changes print size, never intrinsic pixel dimensions. Exact Photoshop defaults remain unqualified.",
      "discovery":"Paint order through page and Form content, reused XObjects deduplicated; inline images have separate IDs. Unpainted resources and masks attached to other images are not separate entries. No Adobe ordering equivalence asserted.",
      "limits":"4096 source images,32 selections,64MiB source/extracted image PDF,512MiB native combined budget; API8 sharing slots/4MP per image/128MiB. Scanner/render cancellation is cooperative between callbacks/pages.",
      "remaining":"Exact Photoshop ordering/dedup/defaults/depth/color/masks, image codecs/platform behavior, pattern/annotation images and live UI. Vector Smart Objects and Photoshop PDF editing data remain separate gaps."]
  }
}
