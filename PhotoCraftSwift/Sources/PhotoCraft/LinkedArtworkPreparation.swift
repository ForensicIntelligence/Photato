import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// A staged writer is transferred between tasks sequentially, never used concurrently.
final class LinkedArtworkExport:@unchecked Sendable {
  private let writer:AtomicFileWriter
  private let url:URL
  private let scoped:Bool
  init(url:URL,data:Data,followSymbolicLinks:Bool=true)throws {
    self.url=url;scoped=url.startAccessingSecurityScopedResource()
    do{writer=try AtomicFileWriter(to:url,maximumBytes:SmartObject.maximumSourceBytes,followSymbolicLinks:followSymbolicLinks);try writer.append(data)}
    catch{if scoped{url.stopAccessingSecurityScopedResource()};throw error}
  }
  func discard(){writer.discard()}
  func commit()throws{try Task.checkCancellation();try writer.commit()}
  deinit{writer.discard();if scoped{url.stopAccessingSecurityScopedResource()}}
}
enum LinkedArtworkPreparation {
  static func linking(_ command:Command,file:LinkedArtworkRead,in original:CraftDocument)throws->Command {
    let reference=try file.reference
    switch command {
    case .addLayer(let layer):return try .addLayer(LinkedSmartObjectIO.linked(layer,reference:reference))
    default:
      var result=original;try command.apply(to:&result)
      let old=Dictionary(uniqueKeysWithValues:original.layers.compactMap{layer in layer.smartObject.map{(layer.id,$0)}})
      var count=0
      for i in result.layers.indices {
        guard let source=result.layers[i].smartObject,old[result.layers[i].id] != source else{continue}
        result.layers[i]=try LinkedSmartObjectIO.linked(result.layers[i],reference:reference);count+=1
      }
      guard count>0 else{throw CraftError.invalid("The placement did not produce linked artwork.")}
      return .linkedSmartObject(try .init(source:original,result:result,title:"Place Linked"))
    }
  }
}
