import Foundation
import Observation
import PhotoCraftCore
import PhotoCraftImaging

struct ShapePreset:Codable,Equatable,Identifiable,Sendable {
  var id=UUID()
  var name:String
  var path:VectorPath
  func validate()throws {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf16.count<=255 else{throw CraftError.invalid("A shape needs a name up to255 characters.")}
    var geometry=ShapeGeometry(kind:.custom);geometry.customPath=path;try geometry.validate()
  }
}
@MainActor @Observable final class ShapeLibrary {
  static let shared=ShapeLibrary(persistenceURL:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("Photato/Shapes.photatoshapes"))
  struct File:Codable {var version=1;var shapes:[ShapePreset]}
  private(set) var shapes:[ShapePreset]=[]
  private(set) var revision=0
  private(set) var loadError:String?
  @ObservationIgnored let persistenceURL:URL?
  init(persistenceURL:URL?=nil){
    self.persistenceURL=persistenceURL
    if let url=persistenceURL,FileManager.default.fileExists(atPath:url.path){do{shapes=try Self.decode(Self.read(url))}catch{loadError="Saved shapes could not be read; the file is preserved. \(error.localizedDescription)"}}
  }
  static func read(_ url:URL)throws->Data {guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<=16*1024*1024 else{throw CraftError.invalid("Shape library exceeds16MiB.")};return try Data(contentsOf:url)}
  static func validate(_ shapes:[ShapePreset])throws{guard shapes.count<=128,Set(shapes.map(\.id)).count==shapes.count else{throw CraftError.invalid("Choose up to128 distinct shape presets.")};for shape in shapes{try shape.validate()}}
  static func decode(_ data:Data)throws->[ShapePreset]{guard data.count<=16*1024*1024 else{throw CraftError.invalid("Shape library exceeds16MiB.")};let file=try JSONDecoder().decode(File.self,from:data);guard file.version==1 else{throw CraftError.unsupported("Unsupported shape library version.")};try validate(file.shapes);return file.shapes}
  func export(_ id:UUID?=nil)throws->Data{let values=try id.map{[try preset($0)]} ?? shapes;return try JSONEncoder().encode(File(shapes:values))}
  func preset(_ id:UUID)throws->ShapePreset{guard let shape=shapes.first(where:{$0.id==id}) else{throw CraftError.invalid("The shape preset is no longer available.")};return shape}
  func update(_ edit:(inout [ShapePreset])throws->Void)throws{
    guard loadError==nil else{throw CraftError.invalid(loadError!)};var next=shapes;try edit(&next);try Self.validate(next)
    let data=try JSONEncoder().encode(File(shapes:next));guard data.count<=16*1024*1024 else{throw CraftError.invalid("Shape library exceeds16MiB.")}
    if let url=persistenceURL{try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:url,options:.atomic)}
    shapes=next;revision+=1
  }
  func add(_ shape:ShapePreset)throws{try update{$0.append(shape)}}
  func remove(_ id:UUID)throws{_=try preset(id);try update{$0.removeAll{$0.id==id}}}
  func rename(_ id:UUID,_ name:String)throws{_=try preset(id);try update{v in v[v.firstIndex{$0.id==id}!].name=name}}
  func importData(_ data:Data)throws{let incoming=try Self.decode(data);try update{values in for var item in incoming {if values.contains(where:{$0.id==item.id}){item.id=UUID()};values.append(item)}}}
}
