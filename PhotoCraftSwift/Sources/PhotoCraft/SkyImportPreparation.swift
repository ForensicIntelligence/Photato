import Foundation
import PhotoCraftCore

enum SkyImportPreparation {
  static func validate(_ presets:[SkyPreset])throws {
    guard !presets.isEmpty,presets.count<=64 else{throw CraftError.invalid("Choose1–64 sky images.")}
    guard presets.reduce(0,{$0+$1.data.count})<=48*1024*1024 else{throw CraftError.invalid("Sky images exceed48MiB.")}
    for preset in presets{try Task.checkCancellation();_=try preset.document()}
  }
  static func load(_ urls:[URL])throws->[SkyPreset] {
    guard !urls.isEmpty,urls.count<=64 else{throw CraftError.invalid("Choose1–64 sky images.")}
    var presets:[SkyPreset]=[],total=0
    for url in urls{
      try Task.checkCancellation()
      guard url.isFileURL else{throw CraftError.invalid("Choose local sky images.")}
      let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
      let file=try FileHandle(forReadingFrom:url);defer{try? file.close()}
      var data=Data()
      while let chunk=try file.read(upToCount:min(65536,16*1024*1024+1-data.count)),!chunk.isEmpty{
        try Task.checkCancellation();data.append(chunk)
        guard data.count<=16*1024*1024,total+data.count<=48*1024*1024 else{throw CraftError.invalid("Each sky must fit16MiB and all imported skies48MiB.")}
      }
      total+=data.count;presets.append(.init(name:url.deletingPathExtension().lastPathComponent,data:data))
    }
    try validate(presets);return presets
  }
}
