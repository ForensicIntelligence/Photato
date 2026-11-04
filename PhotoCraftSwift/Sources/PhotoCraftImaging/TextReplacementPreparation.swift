import Foundation
import PhotoCraftCore

public enum TextReplacementPreparation {
  public struct Result:Sendable {public let command:Command;public let occurrences:Int;public let layers:Int}
  public static func prepare(_ source:CraftDocument,request:RecordedTextReplacement) throws -> Result {
    try request.validate();try source.validate()
    let id=try request.target?.resolve(in:source);var candidate=source,count=0,changed=0
    for layer in try NativeTextSearch.layers(in:source,layerID:id) {
      try Task.checkCancellation();guard case .text(let text)=layer.content else{continue}
      let found=try request.settings.ranges(in:text.text,start:request.start)
      let ranges=request.replaceAll ? found:Array(found.prefix(1));guard !ranges.isEmpty else{continue}
      let edited=try NativeTextSearch.replacing(text.promoted(dpi:source.pixelsPerInch),ranges:ranges,with:request.replacement)
      count+=ranges.count
      if edited.text != text.text {
        let command=try ShapedTextLayout.replacement(layer,content:edited,document:candidate)
        try command.apply(to:&candidate);changed+=1
      }
      if !request.replaceAll{break}
    }
    let title=request.replaceAll ? "Replace All Text":"Replace Text"
    let prepared=PreparedActionEdit(source:source,result:candidate,title:title,recording:.replaceText(request))
    return .init(command:.preparedAction(prepared),occurrences:count,layers:changed)
  }
}
