import Foundation
import PhotoCraftCore

public struct FocusAreaInput:Sendable {
  public let refinement:SelectionRefinementInput
  public let analysis:FocusAreaAnalysis
  public static func prepare(_ original:CraftDocument,layerID:UUID,sampleAllLayers:Bool=false)throws->Self {
    let input=try SelectionRefinementInput.prepare(original,layerID:layerID,sampleAllLayers:sampleAllLayers)
    let proxy=try ColorManagement.converted(input.guide,from:original,to:CraftDocument(width:1,height:1))
    return try Self(refinement:input,analysis:FocusAreaAnalysis.prepare(proxy))
  }
  public func edit(settings:FocusAreaSettings,output:SelectionRefinementOutput = .selection,strokes:[SelectionRefinementStroke]=[])throws->SelectionRefinementEdit {
    guard strokes.allSatisfy({$0.tool == .add || $0.tool == .subtract}) else{throw CraftError.invalid("Focus Area accepts Add/Subtract brushes. Use Select and Mask for other refinement tools.")}
    return try refinement.edit(settings:.init(),output:output,strokes:strokes,initial:analysis.mask(settings:settings))
  }
}
