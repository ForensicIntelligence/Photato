import Foundation
import PhotoCraftCore
import Vision

public protocol LiquifyFaceDetecting: Sendable {
  func faces(in image: Surface) async throws -> [LiquifyFaceGeometry]
}
public struct VisionLiquifyFaces: LiquifyFaceDetecting {
  public init() {}
  private final class Request: @unchecked Sendable { let value = VNDetectFaceLandmarksRequest() }
  public func faces(in image: Surface) async throws -> [LiquifyFaceGeometry] {
    guard image.width <= RasterFilterEngine.maximumPixels/image.height else { throw CraftError.invalid("Face detection input exceeds the filter size limit.") }
    let request = Request()
    let worker = Task.detached(priority:.userInitiated) {
      try Task.checkCancellation()
      let handler = VNImageRequestHandler(cgImage:try RasterIO.displayImage(image),options:[:])
      try handler.perform([request.value]); try Task.checkCancellation()
      return try (request.value.results ?? []).prefix(16).compactMap { observation -> LiquifyFaceGeometry? in
        guard let landmarks = observation.landmarks else { return nil }
        let box = observation.boundingBox
        func bounded(_ x: Double,_ y: Double,_ w: Double,_ h: Double) -> [Double] {
          let left = max(0,min(0.9999,x)), top = max(0,min(0.9999,y))
          return [left,top,max(0.0001,min(1-left,w)),max(0.0001,min(1-top,h))]
        }
        let bounds = bounded(box.minX,1-box.maxY,box.width,box.height)
        func region(_ landmark: VNFaceLandmarkRegion2D?, fallback: [Double]) -> [Double] {
          guard let points = landmark?.normalizedPoints, !points.isEmpty else {
            return bounded(bounds[0]+fallback[0]*bounds[2],bounds[1]+fallback[1]*bounds[3],fallback[2]*bounds[2],fallback[3]*bounds[3])
          }
          let xs = points.map { Double(box.minX)+Double($0.x)*Double(box.width) }
          let ys = points.map { 1-Double(box.minY)-Double($0.y)*Double(box.height) }
          let x = xs.min()!, y = ys.min()!
          return bounded(x,y,max(bounds[2]*0.03,xs.max()!-x),max(bounds[3]*0.03,ys.max()!-y))
        }
        let face = LiquifyFaceGeometry(bounds:bounds,leftEye:region(landmarks.leftEye,fallback:[0.18,0.3,0.2,0.1]),rightEye:region(landmarks.rightEye,fallback:[0.62,0.3,0.2,0.1]),nose:region(landmarks.nose,fallback:[0.38,0.38,0.24,0.28]),mouth:region(landmarks.outerLips,fallback:[0.28,0.67,0.44,0.13]))
        try face.validate(); return face
      }
    }
    return try await withTaskCancellationHandler { try await worker.value } onCancel:{ request.value.cancel(); worker.cancel() }
  }
}
