import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PagedImageStatisticsTests:XCTestCase {
  func source(_ value:Float,depth:PixelDepth = .f32,width:Int=300000,height:Int=300000)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:depth)
    var pixels=try Surface(width:width,height:height,depth:depth,fill:Pixel(value,value,value))
    if depth == .f32{pixels=try pixels.interpretingSamples(as:.linearRGB)}
    d.layers[0].content = .raster(pixels);return d
  }
  func frames(_ d:CraftDocument)throws->[Surface] {
    var roots=d.layers.filter{$0.parentID==nil};let outer=roots.count==1 && roots[0].isGroup ? roots[0]:nil
    if let outer{roots=d.layers.filter{$0.parentID==outer.id}}
    return try roots.filter{$0.visible && (outer?.visible ?? true)}.map{root in
      var isolated=d;let ids=Set(d.subtreeIDs(root.id)).union(outer.map{[$0.id]} ?? [])
      isolated.layers=d.layers.filter{ids.contains($0.id)};LayerLinks.prune(in:&isolated);isolated.activeLayerID=root.id
      isolated.selection=nil;isolated.selectionMask=nil;isolated.quickMask=nil
      for i in isolated.layers.indices where isolated.layers[i].id==root.id || isolated.layers[i].id==outer?.id{isolated.layers[i].blendMode = .normal;isolated.layers[i].clipped=false}
      return try Renderer.composite(isolated)
    }
  }
  func testAll99LegacyProgramsRetainEverySampleBitInOrdinaryAndPagedPaths()throws {
    let h=LegacyImageStackCaptureTests(),folder=Bundle.module.url(forResource:"Fixtures",withExtension:nil)!.appendingPathComponent("paged-image-statistics")
    let expected=try Data(contentsOf:folder.appendingPathComponent("image-stack-small.f32le"));var ordinary=Data(),paged=Data()
    for depth in PixelDepth.allCases{for variant in 0..<3{for mode in ImageStackMode.allCases{
      let d=try h.source(depth,variant:variant)
      ordinary.append(try h.words(ImageStack.render(d,mode:mode,in:d),depth:depth))
      paged.append(try h.words(PagedImageStatistics.surface(frames(d),width:d.width,height:d.height,depth:depth,mode:mode),depth:depth))
    }}}
    XCTAssertEqual(expected.count,152064);XCTAssertEqual(ordinary,expected);XCTAssertEqual(paged,expected)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{
      try ordinary.write(to:URL(fileURLWithPath:path).appendingPathComponent("image-stack-current.f32le"))
      try paged.write(to:URL(fileURLWithPath:path).appendingPathComponent("image-stack-paged.f32le"))
    }
  }
  func testMaximumSparseGeometryAllDepthsAndElevenAnalyticalModes()throws {
    let values:[ImageStackMode:Float]=[.mean:0.5,.median:0.5,.minimum:0,.maximum:1,.range:1,.summation:1,.variance:0.5,.standardDeviation:Float(sqrt(0.5)),.skewness:0,.kurtosis:0.5,.entropy:1]
    for depth in PixelDepth.allCases{
      var d=try source(0,depth:depth);d.layers.append(try source(1,depth:depth).layers[0]);d.activeLayerID=d.layers[0].id
      let before=d
      for mode in ImageStackMode.allCases{
        let output=try ImageStack.render(d,mode:mode,in:d),expected=Pixel(values[mode]!,values[mode]!,values[mode]!).quantized(depth)
        let p=depth == .f32 ? output.linearPixel(x:299999,y:299999):output.pixel(x:299999,y:299999)
        XCTAssertEqual(p,expected,"\(depth) \(mode)");XCTAssertEqual(output.tileCount,0);XCTAssertEqual(output.width,300000)
      }
      XCTAssertEqual(d,before)
    }
  }
  func testSixtyFiveFramesRetainOrderVisibilityAndHDRWithoutOldSixteenFrameCap()throws {
    var d=try source(0,width:1,height:1);d.layers=[]
    for i in 0..<65{d.layers.append(try source(Float(i)/64,width:1,height:1).layers[0])};d.activeLayerID=d.layers[0].id
    for(mode,value)in [(ImageStackMode.mean,Float(0.5)),(.median,0.5),(.minimum,0),(.maximum,1),(.range,1),(.summation,32.5),(.variance,Float(65*66)/Float(12*4096))]{
      XCTAssertEqual(try ImageStack.render(d,mode:mode,in:d).linearPixel(x:0,y:0).r,value)
    }
    d.layers[64].visible=false;XCTAssertEqual(try ImageStack.render(d,mode:.summation,in:d).linearPixel(x:0,y:0).r,31.5)
    d.layers[0].opacity=0;XCTAssertEqual(try ImageStack.render(d,mode:.minimum,in:d).linearPixel(x:0,y:0).r,Float(1)/64)
  }
  func testBackingRetainsRawImplicitSignedZeroHDRAndPatchBoundaryWords()throws {
    for depth in PixelDepth.allCases{
      var pixels=try Surface(width:2113,height:67,depth:depth,fill:Pixel(-0.125,0.25,2))
      if depth == .f32{pixels=try pixels.interpretingSamples(as:.linearRGB)}
      for(x,y)in [(0,0),(63,63),(64,64),(2047,63),(2048,64),(2112,66)]{
        let p=Pixel(Float(bitPattern:0x80000000),Float(bitPattern:0x3eaaaaab),2,0.5)
        if depth == .f32{pixels.setLinearPixel(x:x,y:y,p)}else{pixels.setPixel(x:x,y:y,p)}
      }
      let before=pixels,backed=try PagedImageStatistics.backed(pixels)
      XCTAssertEqual(backed,pixels);XCTAssertEqual(pixels,before);XCTAssertEqual(backed.mappedTileCount,backed.tileCount);XCTAssertGreaterThan(backed.mappedBytes,0)
      XCTAssertEqual(try PagedImageStatistics.backed(backed),backed)
    }
  }
  func testActualDensePagedFramesCrossCombinedBudgetAndMatchSmallKernelAtEdges()throws {
    let w=4096,h=2049;var patch=try Surface(width:64,height:64,fill:Pixel(0.25,0.5,0.75))
    patch.setPixel(x:0,y:0,Pixel(0.75,0.25,0.5))
    let builder=try Surface.PagedBuilder(width:w,height:h)
    for y in stride(from:0,to:h,by:64){for x in stride(from:0,to:w,by:64){try builder.append(y+64<=h ? patch:patch.cropped(to:.init(x:0,y:0,width:64,height:1)),atX:x,atY:y)}}
    let full=try builder.finish();var d=try source(0.5,depth:.u8,width:w,height:h);d.layers.append(Layer(name:"Allocated photo",content:.raster(full)))
    var small=try source(0.5,depth:.u8,width:64,height:64);small.layers.append(Layer(name:"Same patch",content:.raster(patch)))
    XCTAssertGreaterThan(w*h*2,ImageStack.maximumTotalPixels);XCTAssertGreaterThan(full.mappedBytes,128*1024*1024)
    let before=d,output=try ImageStack.render(d,mode:.mean,in:d),expected=try ImageStack.render(small,mode:.mean,in:small)
    for(x,y)in [(0,0),(63,63),(64,64),(2047,1023),(2048,1024),(4095,2047),(0,2048),(4095,2048)]{XCTAssertEqual(output.pixel(x:x,y:y),expected.pixel(x:x%64,y:y%64))}
    XCTAssertGreaterThan(output.mappedBytes,0);XCTAssertEqual(d,before)
  }
  func testOwnedSourceAboveSmartObjectHeapBudgetCanPrepareEditablePagedContents()throws {
    let w=4096,h=4097;var owned=try Surface(width:w,height:h,fill:Pixel(0.25,0.5,0.75))
    for y in stride(from:0,to:h,by:64){for x in stride(from:0,to:w,by:64){owned.setPixel(x:x,y:y,Pixel(0.75,0.25,0.5))}}
    var a=try source(0,depth:.u8,width:w,height:h);a.layers[0].content = .raster(owned)
    XCTAssertGreaterThan(a.estimatedBytes,256*1024*1024);XCTAssertThrowsError(try SmartObjectIO.check(a))
    var settings=ImageStackSettings();settings.createSmartObject=true
    let result=try ImageStack.prepare([a,source(0.5,depth:.u8,width:w,height:h)],settings:settings).document
    let object=try XCTUnwrap(result.layers[0].smartObject),contents=try SmartObjectIO.sourceDocument(object)
    guard case .raster(let retained)=contents.layers[0].content else{return XCTFail("Missing retained photo")}
    XCTAssertEqual(retained,owned);XCTAssertGreaterThan(retained.mappedBytes,0);XCTAssertLessThan(contents.estimatedBytes,256*1024*1024)
    XCTAssertEqual(a.layers[0].content,.raster(owned));XCTAssertNil(object.stackMode);XCTAssertEqual(contents.layers.count,2)
  }
  func testManyMaximumSourcesRemainEditableThroughModeNoneNativeArchiveAndUndo()throws {
    let inputs=try (0..<17).map{try source(Float($0)/16)},before=inputs
    var settings=ImageStackSettings();settings.createSmartObject=true;settings.mode = .mean
    let d=try ImageStack.prepare(inputs,settings:settings).document,id=d.layers[0].id,object=try XCTUnwrap(d.layers[0].smartObject)
    XCTAssertEqual(try SmartObjectIO.sourceDocument(object).layers.count,17);XCTAssertEqual(inputs,before)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(d)),d)
    var session=EditorSession(document:d);try session.execute(ImageStack.command(in:d,layerID:id,mode:.summation))
    XCTAssertEqual(try Renderer.compositePaged(session.document).linearPixel(x:299999,y:299999).r,8.5)
    XCTAssertEqual(session.document.layers[0].smartObject?.data,object.data)
    try session.execute(ImageStack.command(in:session.document,layerID:id,mode:nil));XCTAssertNil(session.document.layers[0].smartObject?.stackMode)
    try session.undo();XCTAssertEqual(session.document.layers[0].smartObject?.stackMode,.summation)
  }
  func testCancellationOverflowAndAlignmentCapacityRejectWithoutChangingSources()async throws {
    let sources=try [source(Float.greatestFiniteMagnitude),source(Float.greatestFiniteMagnitude)],before=sources
    var settings=ImageStackSettings();settings.createSmartObject=true;settings.mode = .summation
    XCTAssertThrowsError(try ImageStack.prepare(sources,settings:settings));XCTAssertEqual(sources,before)
    settings.align=true;settings.mode = .mean
    XCTAssertThrowsError(try ImageStack.prepare(Array(repeating:source(0,width:1,height:1),count:17),settings:settings))
    let options=settings,task=Task.detached{withUnsafeCurrentTask{$0?.cancel()};return try ImageStack.prepare(sources,settings:options)}
    do{_ = try await task.value;XCTFail("Cancelled preparation returned a document")}catch is CancellationError{}
    XCTAssertEqual(sources,before);XCTAssertEqual(ImageStack.maximumSources,LayerLimits.maximumLayers)
  }
}
