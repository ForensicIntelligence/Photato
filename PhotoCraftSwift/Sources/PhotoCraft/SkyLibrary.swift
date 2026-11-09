import AppKit
import Observation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging

struct SkyPreset:Codable,Equatable,Identifiable,Sendable {
  var id=UUID()
  var name:String
  var data:Data
  var groupID:UUID?
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
    guard w>0,h>0,w<=Surface.maxDimension,h<=Surface.maxDimension,w<=SkyReplacement.maximumPixels/h else{throw CraftError.unsupported("Sky images must fit within300,000pixels per side; file-size and format decoder limits also apply.")}
    let d=try RasterIO.read(data,name:name)
    guard d.width<=SkyReplacement.maximumPixels/d.height else{throw CraftError.unsupported("Sky images must fit within300,000pixels per side; file-size and format decoder limits also apply.")};return d
  }
}
struct SkyPresetGroup:Codable,Equatable,Identifiable,Sendable {
  var id=UUID()
  var name:String
  func validate()throws {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf16.count<=255 else{throw CraftError.invalid("A sky group needs a name up to255 characters.")}
  }
}
@MainActor @Observable final class SkyLibrary {
  static let shared=SkyLibrary(persistenceURL:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("Photato/Skies.photatoskies"))
  struct File:Codable {
    var version=2
    var skies:[SkyPreset]=[]
    var groups:[SkyPresetGroup]=[]
    init(skies:[SkyPreset],groups:[SkyPresetGroup]=[]){self.skies=skies;self.groups=groups}
    enum CodingKeys:String,CodingKey{case version,skies,groups}
    init(from decoder:Decoder)throws {
      let c=try decoder.container(keyedBy:CodingKeys.self)
      version=try c.decode(Int.self,forKey:.version);skies=try c.decode([SkyPreset].self,forKey:.skies)
      groups=try c.decodeIfPresent([SkyPresetGroup].self,forKey:.groups) ?? []
      guard version==1 || version==2 else{throw CraftError.unsupported("Unsupported sky library version.")}
      guard version != 1 || (groups.isEmpty && skies.allSatisfy{$0.groupID==nil}) else{throw CraftError.invalid("Version1 sky libraries cannot contain groups.")}
    }
  }
  private(set) var skies:[SkyPreset]=[]
  private(set) var groups:[SkyPresetGroup]=[]
  private(set) var revision=0
  private(set) var loadError:String?
  @ObservationIgnored let persistenceURL:URL?
  init(persistenceURL:URL?=nil) {
    self.persistenceURL=persistenceURL
    if let url=persistenceURL,FileManager.default.fileExists(atPath:url.path){do{
      guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<=64*1024*1024 else{throw CraftError.invalid("Sky library exceeds64MiB.")}
      let file=try PropertyListDecoder().decode(File.self,from:Data(contentsOf:url));try Self.validate(file.skies,groups:file.groups);skies=file.skies;groups=file.groups
    }catch{loadError="Saved skies could not be read; the file is preserved. \(error.localizedDescription)"}}
  }
  static func validate(_ skies:[SkyPreset],groups:[SkyPresetGroup]=[])throws {
    guard skies.count<=64,Set(skies.map(\.id)).count==skies.count,skies.reduce(0,{$0+$1.data.count})<=48*1024*1024 else{throw CraftError.invalid("Sky library supports64 images and48MiB of image data.")}
    let ids=Set(groups.map(\.id));guard groups.count<=64,ids.count==groups.count else{throw CraftError.invalid("Sky library supports64 uniquely identified groups.")}
    for group in groups{try group.validate()}
    for sky in skies{try sky.validate();guard sky.groupID.map({ids.contains($0)}) ?? true else{throw CraftError.invalid("The sky group no longer exists.")}}
  }
  func preset(_ id:UUID)throws->SkyPreset {guard let v=skies.first(where:{$0.id==id}) else{throw CraftError.invalid("The sky is no longer in the library.")};return v}
  func update(_ edit:(inout [SkyPreset])throws->Void)throws {
    try updateLibrary{skies,_ in try edit(&skies)}
  }
  func updateLibrary(expectedRevision:Int?=nil,_ edit:(inout [SkyPreset],inout [SkyPresetGroup])throws->Void)throws {
    guard loadError==nil else{throw CraftError.invalid(loadError!)}
    guard expectedRevision.map({$0==revision}) ?? true else{throw CraftError.invalid("The sky library changed. Try again.")}
    var next=skies,nextGroups=groups;try edit(&next,&nextGroups);try Self.validate(next,groups:nextGroups)
    let encoder=PropertyListEncoder();encoder.outputFormat = .binary;let data=try encoder.encode(File(skies:next,groups:nextGroups));guard data.count<=64*1024*1024 else{throw CraftError.invalid("Sky library exceeds64MiB.")}
    if let url=persistenceURL{try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:url,options:.atomic)}
    skies=next;groups=nextGroups;revision+=1
  }
  func add(_ preset:SkyPreset)throws{try update{$0.append(preset)}}
  func remove(_ id:UUID)throws{_=try preset(id);try update{$0.removeAll{$0.id==id}}}
  func rename(_ id:UUID,_ name:String)throws{_=try preset(id);try update{v in v[v.firstIndex{$0.id==id}!].name=name}}
  @discardableResult func createGroup(_ name:String,id:UUID=UUID())throws->UUID {
    try updateLibrary{_,groups in groups.append(.init(id:id,name:name))};return id
  }
  func renameGroup(_ id:UUID,_ name:String)throws {
    try updateLibrary{_,groups in guard let i=groups.firstIndex(where:{$0.id==id}) else{throw CraftError.invalid("The sky group no longer exists.")};groups[i].name=name}
  }
  func deleteGroup(_ id:UUID,removeSkies:Bool)throws {
    try updateLibrary{skies,groups in
      guard groups.contains(where:{$0.id==id}) else{throw CraftError.invalid("The sky group no longer exists.")}
      groups.removeAll{$0.id==id}
      if removeSkies{skies.removeAll{$0.groupID==id}}else{for i in skies.indices where skies[i].groupID==id{skies[i].groupID=nil}}
    }
  }
  func move(_ ids:[UUID],to groupID:UUID?)throws {
    guard !ids.isEmpty,ids.count<=64,Set(ids).count==ids.count,ids.allSatisfy({id in skies.contains{$0.id==id}}) else{throw CraftError.invalid("Choose one or more existing, unique sky IDs.")}
    try update{skies in for i in skies.indices where ids.contains(skies[i].id){skies[i].groupID=groupID}}
  }
  func append(_ presets:[SkyPreset],to groupID:UUID?,expectedRevision:Int)throws {
    guard !presets.isEmpty,presets.count<=64 else{throw CraftError.invalid("Choose1–64 sky images.")}
    try updateLibrary(expectedRevision:expectedRevision){skies,groups in
      guard groupID.map({id in groups.contains{$0.id==id}}) ?? true else{throw CraftError.invalid("The sky group no longer exists.")}
      skies += presets.map{var p=$0;p.groupID=groupID;return p}
    }
  }
}
