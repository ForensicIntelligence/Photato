import XCTest
@testable import PhotoCraftCore

final class SelectionSegmentationTests:XCTestCase {
  func testGraphMatchesExhaustiveIndependentCuts()throws {
    var rng=SelectionRandom(88213)
    for count in 2...8 {for _ in 0..<20 {
      let graph=SelectionGraph(nodes:count,edges:count*count)
      let sources=(0..<count).map{_ in rng.unit()*12-5},sinks=(0..<count).map{_ in rng.unit()*12-5}
      var edges:[(Int,Int,Float,Float)]=[]
      for i in 0..<count {graph.addTerminal(i,source:sources[i],sink:sinks[i]);for j in 0..<i {let a=rng.unit()*3,b=rng.unit()*3;edges.append((i,j,a,b));graph.addEdge(i,j,capacity:a,reverse:b)}}
      let flow=try graph.maxflow()
      func capacity(_ bits:Int)->Double {
        var sum=0.0
        for i in 0..<count {sum+=Double(bits & (1<<i) != 0 ? sinks[i]:sources[i])}
        for (i,j,a,b) in edges {let x=bits & (1<<i) != 0,y=bits & (1<<j) != 0;if x && !y {sum+=Double(a)};if y && !x {sum+=Double(b)}}
        return sum
      }
      let optimum=(0..<(1<<count)).map(capacity).min()!,actual=(0..<count).reduce(0){$0 | (graph.inSource($1) ? 1<<$1:0)}
      XCTAssertEqual(flow,optimum,accuracy:0.0001);XCTAssertEqual(capacity(actual),optimum,accuracy:0.0001)
    }}
  }
  func scene(_ w:Int=120,_ h:Int=100)throws->(Surface,[Bool]) {
    var surface=try Surface(width:w,height:h),truth=[Bool](repeating:false,count:w*h),rng=SelectionRandom(817)
    let radius=Float(min(w,h))*0.3,cx=Float(w)/2,cy=Float(h)/2
    for y in 0..<h {for x in 0..<w {
      let dx=Float(x)+0.5-cx,dy=Float(y)+0.5-cy,inside=dx*dx+dy*dy<radius*radius,n=(rng.unit()-0.5)*0.07
      let t=sin(Float(x+y)*0.35)*0.5+0.5
      truth[y*w+x]=inside;surface.setPixel(x:x,y:y,inside ? Pixel(0.85+0.05*t+n,0.2+0.3*t+n,0.15+n):Pixel(0.25+n,0.45+n,0.7+n))
    }}
    return (surface,truth)
  }
  func overlap(_ mask:SelectionMask,_ truth:[Bool])->Double {
    var intersection=0,union=0
    for i in truth.indices {let actual=mask.byte(at:i)>=128;if actual && truth[i]{intersection+=1};if actual || truth[i]{union+=1}}
    return Double(intersection)/Double(max(1,union))
  }
  func testObjectRectangleAndLassoExtractTexturedSubject()throws {
    let (image,truth)=try scene()
    let rect=try SelectionMask.make(.rectangle(.init(x:22,y:12,width:76,height:76)),width:120,height:100,antiAlias:false)
    let result=try SelectionSegmentation.object(image,region:rect)
    XCTAssertGreaterThan(overlap(result,truth),0.95);XCTAssertLessThan(result.bounds!.width,rect.bounds!.width)
    let polygon=try SelectionMask.make(.polygon([.init(20,8),.init(100,15),.init(102,91),.init(20,90)]),width:120,height:100,antiAlias:false)
    XCTAssertGreaterThan(overlap(try SelectionSegmentation.object(image,region:polygon),truth),0.95)
  }
  func testQuickSelectionFollowsEdgesBeyondStrokeAndSubtractableCoverage()throws {
    let (image,truth)=try scene();let result=try SelectionSegmentation.quick(image,points:[.init(56,46),.init(64,54)],size:12)
    XCTAssertGreaterThan(overlap(result,truth),0.9);XCTAssertGreaterThan(result.bounds!.width,40)
    XCTAssertLessThan(result.coverage(x:0,y:0),0.1)
    let missed=try SelectionSegmentation.quick(image,points:[.init(-100,-100)],size:10);XCTAssertNil(missed.bounds)
  }
  func testDownsampledAnalysisRecutsFullResolutionBoundary()throws {
    let (image,truth)=try scene(200,160)
    let region=try SelectionMask.make(.rectangle(.init(x:38,y:18,width:124,height:124)),width:200,height:160,antiAlias:false)
    XCTAssertGreaterThan(overlap(try SelectionSegmentation.object(image,region:region,workPixels:1000),truth),0.95)
    XCTAssertGreaterThan(overlap(try SelectionSegmentation.quick(image,points:[.init(90,80),.init(110,80)],size:15,workPixels:1000),truth),0.9)
  }
  func testFlatColorModelsAndInvalidInputs()throws {
    let green=SelectionRGB(0.1,0.8,0.2),red=SelectionRGB(0.9,0.1,0.2)
    let model=try XCTUnwrap(SelectionColorModel.fit(Array(repeating:green,count:100)+Array(repeating:red,count:100),count:5,ridge:2e-5))
    XCTAssertTrue(model.cost(green).isFinite);XCTAssertLessThan(model.cost(green),model.cost(.init(0.1,0.1,0.9)))
    let image=try Surface(width:10,height:10)
    XCTAssertThrowsError(try SelectionSegmentation.quick(image,points:[],size:10))
    XCTAssertThrowsError(try SelectionSegmentation.quick(image,points:[.init(.nan,2)],size:10))
    XCTAssertThrowsError(try SelectionSegmentation.quick(image,points:[.init(2,2)],size:.infinity))
    XCTAssertThrowsError(try SelectionSegmentation.object(image,region:.init(width:1,height:1,bytes:[255])))
  }
  func testCancellationTerminatesSegmentation()async throws {
    let (image,_)=try scene(100,100)
    let task=Task.detached {try Task.checkCancellation();return try SelectionSegmentation.quick(image,points:[.init(50,50)],size:10)}
    task.cancel()
    do {_=try await task.value;XCTFail("Expected cancellation")}catch is CancellationError {}catch {XCTFail("Unexpected error: \(error)")}
  }
}
