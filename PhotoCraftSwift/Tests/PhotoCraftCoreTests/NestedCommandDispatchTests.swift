import Foundation
import XCTest
@testable import PhotoCraftCore

final class NestedCommandDispatchTests:XCTestCase {
  func testCompositePrimitiveCommandsOnCooperativeWorker()async throws {
    let result=try await Task.detached {
      var d=try CraftDocument(width:8,height:8)
      d.layers[0].content = .raster(try Surface(width:8,height:8,fill:Pixel(0.8,0.2,0.4)))
      let original=d,id=d.layers[0].id
      var session=EditorSession(document:d)
      for kind in AutoCorrection.allCases {try session.execute(.autoCorrection(id,kind))}
      try session.execute(.desaturate(id))
      try session.execute(.addGradientFill(.init(name:"Gradient",content:.gradientFill(.init())),true))
      let pattern=try RasterPattern(name:"Owned pattern",surface:Surface(width:2,height:2,fill:.white))
      try session.execute(.addPatternFill(.init(name:"Pattern",content:.patternFill(.init(patternID:pattern.id))),pattern,true))
      let edited=session.document
      while !session.undoStack.isEmpty {try session.undo()}
      return (original,session.document,edited)
    }.value
    XCTAssertEqual(result.0,result.1)
    XCTAssertEqual(result.2.layers.count,3)
    XCTAssertNotNil(result.2.layers[1].mask);XCTAssertNotNil(result.2.layers[2].mask)
  }
}
