import Foundation
import PhotoCraftCore

public enum AdjustmentBrushPreparation {
  public static func object(_ request:AdjustmentBrushRequest,at point:PathPoint,in document:CraftDocument,detector:any ObjectDetecting = VisionForegroundDetector()) async throws -> Command {
    try request.validate();try ForegroundSelection.checkSize(document.width,document.height)
    guard request.points.isEmpty,request.objectMask==nil else {throw CraftError.invalid("Object application does not accept stroke samples or a supplied mask.")}
    guard point.x.isFinite,point.y.isFinite,point.x>=0,point.y>=0,point.x<Double(document.width),point.y<Double(document.height) else{throw CraftError.invalid("Click inside the image to select an object.")}
    let input=try Renderer.composite(document)
    let proxy=try ColorManagement.converted(input,from:document,to:CraftDocument(width:1,height:1))
    var result=request;result.objectMask=try await detector.mask(for:proxy,at:point)
    try Task.checkCancellation();return .adjustmentBrush(result)
  }
}
