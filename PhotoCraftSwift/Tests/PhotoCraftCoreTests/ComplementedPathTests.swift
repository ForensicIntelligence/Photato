import Foundation
import XCTest
@testable import PhotoCraftCore

final class ComplementedPathTests: XCTestCase {
  func rectangle(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
    _ operation: PathOperation) -> PathComponent {
    PathComponent(knots: [PathPoint(x,y), .init(x+w,y), .init(x+w,y+h), .init(x,y+h)]
      .map { PathKnot($0) }, closed: true, operation: operation)
  }
  func testEveryThreeOperationSequenceMatchesIndependentBooleanTruthTable() throws {
    let operations: [PathOperation] = [.combine, .subtract, .intersect, .exclude]
    let boxes: [(Double,Double,Double,Double)] = [(3,3,14,18),(11,0,16,14),(0,9,23,15),(8,8,15,18)]
    for a in operations { for b in operations { for c in operations { for inversion in [false,true] {
      let sequence: [PathOperation] = [.subtract,a,b,c]
      let path = VectorPath(components: zip(boxes,sequence).map {
        rectangle($0.0.0,$0.0.1,$0.0.2,$0.0.3,$0.1)
      }, inverted: inversion)
      let before = path
      let region = try VectorPathGeometry.filledRegion(path)
      for y in stride(from:0,to:32,by:2) { for x in stride(from:0,to:32,by:2) {
        let px = Double(x)+0.5, py = Double(y)+0.5
        let inside = boxes.map { px >= $0.0 && px < $0.0+$0.2 && py >= $0.1 && py < $0.1+$0.3 }
        var expected = !inside[0]
        for i in 1..<4 {
          switch sequence[i] {
          case .combine: expected = expected || inside[i]
          case .subtract: expected = expected && !inside[i]
          case .intersect: expected = expected && inside[i]
          case .exclude: expected = expected != inside[i]
          case .join: XCTFail("Join has grouped contour semantics")
          }
        }
        expected = expected != inversion
        XCTAssertEqual(region.path.contains(.init(x:px,y:py)) != region.inverted,expected,
          "\(a)/\(b)/\(c)/\(inversion) at \(px),\(py)")
      }}
      XCTAssertEqual(path,before)
    }}}}
  }
  func testFiniteOutlineDoesNotInventBoundsForAnUnboundedExterior() throws {
    var path = VectorPath(components:[rectangle(3,3,14,18,.subtract)])
    XCTAssertThrowsError(try VectorPathGeometry.filledPath(path))
    let exterior = try VectorPathGeometry.filledRegion(path)
    XCTAssertTrue(exterior.inverted)
    XCTAssertFalse(exterior.path.contains(.init(x:900_000,y:-900_000)))
    path.components.append(rectangle(11,0,16,14,.intersect))
    let finite = try VectorPathGeometry.filledPath(path)
    XCTAssertTrue(finite.contains(.init(x:20,y:5)))
    XCTAssertFalse(finite.contains(.init(x:12,y:5)))
  }
  func testCancelledResolutionAndExistingArchiveKeepOriginalControlsAndOperations() async throws {
    var path = VectorPath(components:[rectangle(3,3,14,18,.subtract),rectangle(11,0,16,14,.intersect)])
    path.components[0].knots[0].outgoing = .init(4,6)
    var document = try CraftDocument(width:32,height:32)
    document.paths = [NamedPath(name:"Complemented",path:path,isWorkPath:false)]
    document.layers[0].vectorMask = VectorMask(path:path)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)),document)
    let worker = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      _ = try VectorPathGeometry.filledRegion(path)
      return true
    }
    do { _ = try await worker.value; XCTFail("Cancelled geometry accepted") }
    catch is CancellationError {}
  }

  func testGradientFramesRespectResolvedExteriorAndFinalInversion() throws {
    let path=VectorPath(components:[rectangle(3,3,14,18,.subtract)])
    var layer=Layer(name:"Complemented gradient",content:.gradientFill(GradientFill()))
    layer.vectorMask=VectorMask(path:path)
    XCTAssertEqual(try layer.fillFrame(width:32,height:32),IntRect(x:0,y:0,width:32,height:32))
    layer.vectorMask?.path.inverted=true
    XCTAssertEqual(try layer.fillFrame(width:32,height:32),IntRect(x:3,y:3,width:14,height:18))
    layer.vectorMask?.path.inverted=false
    layer.vectorMask?.path.components.append(rectangle(11,0,16,14,.intersect))
    var equivalent=layer
    equivalent.vectorMask?.path=VectorPath(components:[rectangle(11,0,16,14,.combine),rectangle(3,3,14,18,.subtract)])
    XCTAssertEqual(try layer.fillFrame(width:32,height:32),try equivalent.fillFrame(width:32,height:32))
  }
  func testFiniteShapeAndInsideTextRejectUnboundedPathBeforePublication() throws {
    var path=VectorPath(components:[rectangle(3,3,14,18,.subtract)])
    var text=TextGeometry();text.mode = .inside;text.width=32;text.height=32;text.path=path
    XCTAssertThrowsError(try text.validate())
    var shape=ShapeGeometry(kind:.custom,width:1,height:1)
    shape.customPath=path.transformed(.scale(1/32,1/32))
    XCTAssertThrowsError(try shape.validate())
    XCTAssertThrowsError(try ShapeDefinition.regularPathComponent(path))
    path.components.append(rectangle(11,0,16,14,.intersect))
    text.path=path;shape.customPath=path.transformed(.scale(1/32,1/32))
    XCTAssertNoThrow(try text.validate())
    XCTAssertNoThrow(try shape.validate())
    XCTAssertNoThrow(try ShapeDefinition.regularPathComponent(path))
  }
}
