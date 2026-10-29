import AppKit
import Observation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging

struct SkyPreset:Codable,Equatable,Identifiable,Sendable {
  var id=UUID()
  var name:String
  var data:Data
  func validate()throws {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf16.count<=255,!data.isEmpty,data.count<=16*1024*1024 else{throw CraftError.invalid("A sky needs a name and an image up to16MiB.")}
  }
  func document()throws->CraftDocument {
    try validate()
    let w:Int,h:Int
    if data.starts(with:Data("8BPS".utf8)),data.count>=26 {
      func integer(_ offset:Int)->Int{(offset..<offset+4).reduce(0){($0<<8)|Int(data[$1])}}
      w=integer(18);h=integer(14)
    }else{
      guard let image=CGImageSourceCreateWithData(data as CFData,nil),let properties=CGImageSourceCopyPropertiesAtIndex(image,0,nil) as? [CFString:Any],let width=properties[kCGImagePropertyPixelWidth] as? Int,let height=properties[kCGImagePropertyPixelHeight] as? Int else{throw CraftError.invalid("Choose a supported raster sky image.")};w=width;h=height
    }
    guard w>0,h>0,w<=SkyReplacement.maximumPixels/h else{throw CraftError.unsupported("Sky images support up to8,388,608 pixels.")}
    let d=try RasterIO.read(data,name:name)
    guard d.width<=SkyReplacement.maximumPixels/d.height else{throw CraftError.unsupported("Sky images support up to8,388,608 pixels.")};return d
  }
}
@MainActor @Observable final class SkyLibrary {
  static let shared=SkyLibrary(persistenceURL:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("Photato/Skies.photatoskies"))
  struct File:Codable {var version=1;var skies:[SkyPreset]=[]}
  private(set) var skies:[SkyPreset]=[]
  private(set) var revision=0
  private(set) var loadError:String?
  @ObservationIgnored let persistenceURL:URL?
  init(persistenceURL:URL?=nil) {
    self.persistenceURL=persistenceURL
    if let url=persistenceURL,FileManager.default.fileExists(atPath:url.path){do{
      guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<=64*1024*1024 else{throw CraftError.invalid("Sky library exceeds64MiB.")}
      let file=try PropertyListDecoder().decode(File.self,from:Data(contentsOf:url));guard file.version==1 else{throw CraftError.unsupported("Unsupported sky library version.")};try Self.validate(file.skies);skies=file.skies
    }catch{loadError="Saved skies could not be read; the file is preserved. \(error.localizedDescription)"}}
  }
  static func validate(_ skies:[SkyPreset])throws {
    guard skies.count<=64,Set(skies.map(\.id)).count==skies.count,skies.reduce(0,{$0+$1.data.count})<=48*1024*1024 else{throw CraftError.invalid("Sky library supports64 images and48MiB of image data.")};for sky in skies{try sky.validate()}
  }
  func preset(_ id:UUID)throws->SkyPreset {guard let v=skies.first(where:{$0.id==id}) else{throw CraftError.invalid("The sky is no longer in the library.")};return v}
  func update(_ edit:(inout [SkyPreset])throws->Void)throws {
    guard loadError==nil else{throw CraftError.invalid(loadError!)};var next=skies;try edit(&next);try Self.validate(next)
    let encoder=PropertyListEncoder();encoder.outputFormat = .binary;let data=try encoder.encode(File(skies:next));guard data.count<=64*1024*1024 else{throw CraftError.invalid("Sky library exceeds64MiB.")}
    if let url=persistenceURL{try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:url,options:.atomic)}
    skies=next;revision+=1
  }
  func add(_ preset:SkyPreset)throws{try update{$0.append(preset)}}
  func remove(_ id:UUID)throws{_=try preset(id);try update{$0.removeAll{$0.id==id}}}
  func rename(_ id:UUID,_ name:String)throws{_=try preset(id);try update{v in v[v.firstIndex{$0.id==id}!].name=name}}
}
