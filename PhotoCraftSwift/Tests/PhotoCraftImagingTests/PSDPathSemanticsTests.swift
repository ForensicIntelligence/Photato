import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDPathSemanticsTests: XCTestCase {
  private var folder: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/psd-path-semantics")
  }
  func testLeadingSubtractIntersectAndJoinedWindingMatchEveryPhotoshopRedGreenWord() throws {
    let data = try Data(contentsOf: folder.appendingPathComponent("photoshop-path-semantics.psd"))
    let expected = try Data(contentsOf: folder.appendingPathComponent("photoshop-path-semantics.rgb"))
    let document = try PSDCodec.read(data)
    let actual = try Renderer.composite(document)
    XCTAssertEqual(document.width, 128)
    XCTAssertEqual(document.height, 96)
    XCTAssertEqual(expected.count, 128 * 96 * 3)
    var blueDifferences = 0, blueMaximum = 0
    for y in 0..<96 { for x in 0..<128 {
      let pixel = actual.pixel(x: x, y: y)
      let i = (y * 128 + x) * 3
      XCTAssertEqual(UInt8((pixel.r * 255).rounded()), expected[i], "red \(x),\(y)")
      XCTAssertEqual(UInt8((pixel.g * 255).rounded()), expected[i+1], "green \(x),\(y)")
      let delta = abs(Int((pixel.b * 255).rounded()) - Int(expected[i+2]))
      if delta != 0 { blueDifferences += 1; blueMaximum = max(blueMaximum,delta) }
    }}
    print("PSD_PATH_BLUE_DIAGNOSTIC pixels=\(blueDifferences) maximum=\(blueMaximum); not qualified by red/green assertions")
    XCTAssertEqual(document.layers.first(where:{$0.name == "Subtract then Intersect"})?
      .vectorMask?.path.components.map(\.operation),[.subtract,.intersect])
    XCTAssertEqual(document.layers.first(where:{$0.name == "Joined same winding"})?
      .vectorMask?.path.fillRule,.evenOdd)
  }
  func rectangle(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
    _ operation: PathOperation = .combine) -> PathComponent {
    PathComponent(knots:[PathPoint(x,y),.init(x+w,y),.init(x+w,y+h),.init(x,y+h)]
      .map {PathKnot($0)},closed:true,operation:operation)
  }
  func testPSDBothFormatsPreserveEditableLeadingOperationsAndEvenOddContours() throws {
    let source = try PSDCodec.read(Data(contentsOf:folder.appendingPathComponent("photoshop-path-semantics.psd")))
    for format in [PSDFileFormat.psd,.psb] {
      let output = try PSDCodec.writeRasterLayers(source,format:format)
      let restored = try PSDCodec.read(output)
      for (before,after) in zip(source.layers,restored.layers) {
        XCTAssertEqual(after.vectorMask?.path,before.vectorMask?.path)
        XCTAssertEqual(after.vectorMask?.enabled,before.vectorMask?.enabled)
        XCTAssertEqual(after.vectorMask?.linked,before.vectorMask?.linked)
      }
      let expected = try Renderer.composite(source), actual = try Renderer.composite(restored)
      for y in 0..<96 {for x in 0..<128 {
        XCTAssertTrue(expected.pixel(x:x,y:y).hasSameBits(as:actual.pixel(x:x,y:y)))
      }}
    }
  }
  func testNonzeroExportRejectsActualEvenOddLossAndAllowsEquivalentRules() throws {
    let path = VectorPath(components:[rectangle(2,2,20,20),rectangle(6,6,8,8,.join)])
    XCTAssertTrue(try VectorPathGeometry.fillRulesDiffer(path))
    XCTAssertThrowsError(try PSDPaths.write(path,width:32,height:32))
    var evenOdd = path; evenOdd.fillRule = .evenOdd
    XCTAssertEqual(try PSDPaths.read(PSDPaths.write(evenOdd,width:32,height:32),width:32,height:32),evenOdd)
    var opposite = path; opposite.components[1].knots.reverse()
    XCTAssertFalse(try VectorPathGeometry.fillRulesDiffer(opposite))
    XCTAssertEqual(try PSDPaths.read(PSDPaths.write(opposite,width:32,height:32),width:32,height:32),opposite)
    XCTAssertEqual(path.fillRule,.nonZero)
  }
  func testDenseAndPagedComplementCoverageMatchAcrossPatchesAndAtMaximumCanvas() throws {
    for operation in [PathOperation.combine,.subtract,.intersect,.exclude] {
      for inverted in [false,true] {
        let path = VectorPath(components:[rectangle(2040.25,59.5,20,8,.subtract),
          rectangle(2045.75,60.25,15,8,operation)],inverted:inverted)
        for aa in [false,true] {
          let dense = try VectorRasterizer.coverage(path,width:2113,height:69,antiAlias:aa)
          let paged = try VectorRasterizer.pagedCoverage(path,width:2113,height:69,antiAlias:aa)
          XCTAssertEqual(try dense.bytes,try SelectionMask(coverage:paged).bytes,"\(operation)/\(inverted)/\(aa)")
        }
      }
    }
    let maximum = VectorPath(components:[rectangle(299_970,299_970,20,20,.subtract),
      rectangle(299_980,299_980,16,16,.intersect)])
    let output = try VectorRasterizer.coverage(maximum,width:300_000,height:300_000,antiAlias:false)
    XCTAssertEqual(output.coverage(x:299_985,y:299_985),0)
    XCTAssertEqual(output.coverage(x:299_993,y:299_985),1)
    XCTAssertEqual(output.coverage(x:0,y:0),0)
    XCTAssertLessThanOrEqual(try output.coverageSurface().tileCount,4)
  }
  func testComplementFeatherDensityAndFinalInversionMatchFiniteBooleanEquivalentAtEveryDepth() throws {
    for depth in PixelDepth.allCases {for inverted in [false,true] {
      var document = try CraftDocument(width:32,height:32,depth:depth)
      let path = VectorPath(components:[rectangle(3,3,14,18,.subtract),
        rectangle(11,0,16,14,.intersect)],inverted:inverted)
      var mask = VectorMask(path:path);mask.density=0.7;mask.feather=1.25
      document.layers[0].vectorMask=mask
      var equivalent=document
      equivalent.layers[0].vectorMask?.path=VectorPath(components:[rectangle(11,0,16,14),
        rectangle(3,3,14,18,.subtract)],inverted:inverted)
      let a=try Renderer.composite(document),b=try Renderer.composite(equivalent)
      for y in 0..<32 {for x in 0..<32 {
        XCTAssertTrue(a.pixel(x:x,y:y).hasSameBits(as:b.pixel(x:x,y:y)))
      }}
      let saved=try NativeArchive.decode(NativeArchive.encode(document))
      XCTAssertEqual(saved,document)
    }}
  }
}
