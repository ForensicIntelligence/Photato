import Foundation
import XCTest
@testable import PhotoCraftCore

final class PagedSelectionCoverageTests:XCTestCase {
  private var fixtures:URL {URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/paged-selection")}
  private func compare(_ mask:PagedSelectionCoverage,_ name:String)throws {
    let expected=try Data(contentsOf:fixtures.appendingPathComponent(name+".gray"))
    XCTAssertEqual(Data(try mask.denseBytes()),expected,name)
    let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:fixtures.appendingPathComponent("manifest.json")))as![[String:Any]]
    let entry=try XCTUnwrap(manifest.first {$0["name"]as?String==name})
    let actual=try mask.bounds.map {[$0.x,$0.y,$0.width,$0.height]}
    XCTAssertEqual(actual,entry["bounds"]as?[Int],name)
  }
  func testAll76PriorNativeShapeKernelCombinationAndGeometryVectors()throws {
    let shapes:[SelectionShape]=[.rectangle(.init(x:-2,y:4,width:57,height:51)),.ellipse(.init(x:7,y:-4,width:117,height:67)),.polygon([.init(3.125,2.75),.init(123.25,9.125),.init(44.875,62.375),.init(17.25,31.5)])]
    var count=0
    for(i,shape)in shapes.enumerated(){for aa in [false,true]{for feather:Double in [0,3]{
      let mask=try PagedSelectionCoverage.make(shape,width:129,height:65,antiAlias:aa).feathered(radius:feather)
      let name="s\(i)-aa\(aa)-f\(Int(feather))";try compare(mask,name);try compare(mask.inverted(),name+"-inverse");count+=2
      for(j,t)in [Transform2D.identity,.scale(1.3,0.7),.rotation(21),.init(a:-1,tx:129)].enumerated(){try compare(mask.transformed(by:t,width:173,height:91),name+"-transform\(j)");count+=1}
    }}}
    let old=try PagedSelectionCoverage.make(shapes[0],width:129,height:65),new=try PagedSelectionCoverage.make(shapes[1],width:129,height:65)
    for mode in SelectionMode.allCases {try compare(new.combined(with:old,mode:mode),"combine-"+mode.rawValue);count+=1}
    XCTAssertEqual(count,76)
  }
  func testMaximumSparseEllipseCombinationsAndResampling()throws {
    let a=try PagedSelectionCoverage.make(.ellipse(.init(x:299900,y:299900,width:80,height:80)),width:300000,height:300000)
    XCTAssertEqual(try a.bounds,IntRect(x:299900,y:299900,width:80,height:80));XCTAssertEqual(a.byte(x:299940,y:299940),255)
    XCTAssertEqual(a.byte(x:0,y:0),0);XCTAssertLessThan(a.allocatedBytes,1024*1024)
    let inverse=try a.inverted();XCTAssertEqual(inverse.byte(x:0,y:0),255);XCTAssertEqual(try inverse.bounds,IntRect(x:0,y:0,width:300000,height:300000))
    XCTAssertEqual(try inverse.inverted(),a)
    let empty=try a.combined(with:a,mode:.subtract);XCTAssertNil(try empty.bounds)
    let small=try a.transformed(by:.scale(0.5,0.5),width:150000,height:150000)
    XCTAssertEqual(small.byte(x:149970,y:149970),255);XCTAssertLessThan(small.allocatedBytes,1024*1024)
    XCTAssertThrowsError(try a.denseBytes())
  }
  func testMaximumImplicitAndSharedRectangleBounds()throws {
    let full=try PagedSelectionCoverage.make(.rectangle(.init(x:0,y:0,width:300000,height:300000)),width:300000,height:300000)
    XCTAssertEqual(full.surface.tileCount,0);XCTAssertLessThan(full.allocatedBytes,1024)
    XCTAssertEqual(try full.bounds,IntRect(x:0,y:0,width:300000,height:300000))
    let stripe=try PagedSelectionCoverage.make(.rectangle(.init(x:0,y:0,width:1,height:300000)),width:300000,height:300000)
    XCTAssertEqual(try stripe.bounds,IntRect(x:0,y:0,width:1,height:300000));XCTAssertLessThan(stripe.allocatedBytes,1024*1024)
    let trimmed=try stripe.combined(with:full,mode:.subtract)
    XCTAssertEqual(try trimmed.bounds,IntRect(x:1,y:0,width:299999,height:300000))
    XCTAssertEqual(trimmed.byte(x:0,y:100),0);XCTAssertEqual(trimmed.byte(x:1,y:100),255)
    XCTAssertLessThan(trimmed.allocatedBytes,1024*1024)
  }
  func testNumericQuantizationAndCheckedDenseExtraction()throws {
    var source=try Surface(width:3,height:1,depth:.f32,fill:.black).interpretingSamples(as:.linearRGB)
    source.setLinearPixel(x:0,y:0,Pixel(0.5,0.5,0.5,0));source.setLinearPixel(x:1,y:0,Pixel(-1,-1,-1,0));source.setLinearPixel(x:2,y:0,Pixel(4,4,4,0))
    let plane=try PagedSelectionCoverage(surface:source)
    XCTAssertEqual(try plane.denseBytes(),[188,0,255]);XCTAssertEqual(plane.surface.depth,.u8)
    XCTAssertThrowsError(try plane.denseBytes(maximumPixels:2));XCTAssertThrowsError(try PagedSelectionCoverage(width:3,height:2,bytes:[0]))
    XCTAssertThrowsError(try plane.feathered(radius:101))
  }
  func testActual40MPDenseInputPagesWithoutRetainingTheArray()throws {
    let w=8000,h=5000
    var bytes=[UInt8](repeating:0,count:w*h)
    for y in 0..<h {for x in 0..<w {bytes[y*w+x]=UInt8((x+3*y)%256)}}
    let plane=try PagedSelectionCoverage(width:w,height:h,bytes:bytes)
    XCTAssertGreaterThan(plane.mappedBytes,36_000_000);XCTAssertLessThan(plane.allocatedBytes,1024*1024)
    XCTAssertThrowsError(try plane.denseBytes())
    XCTAssertEqual(try plane.denseBytes(maximumPixels:w*h),bytes)
    XCTAssertEqual(try plane.bounds,IntRect(x:0,y:0,width:w,height:h))
  }
  func testCancellationIncludesImplicitFastPaths()async throws {
    let plane=try PagedSelectionCoverage.make(.rectangle(.init(x:0,y:0,width:300000,height:300000)),width:300000,height:300000)
    let cancelled=await Task.detached {() -> Int in
      withUnsafeCurrentTask {$0?.cancel()};var failures=0
      do {_ = try plane.inverted()}catch is CancellationError {failures+=1}catch{}
      do {_ = try plane.combined(with:nil,mode:.add)}catch is CancellationError {failures+=1}catch{}
      do {_ = try plane.bounds}catch is CancellationError {failures+=1}catch{}
      return failures
    }.value
    XCTAssertEqual(cancelled,3);XCTAssertEqual(plane.byte(x:0,y:0),255)
  }
}
