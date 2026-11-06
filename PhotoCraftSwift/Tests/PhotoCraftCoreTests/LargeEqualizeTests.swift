import XCTest
@testable import PhotoCraftCore

final class LargeEqualizeTests: XCTestCase {
  func testImplicitOverviewRetainsExactPixelsOfFullyStoredEquivalentIncludingLinearHDRAndZeroAlpha() throws {
    for encoding in [SurfaceColorEncoding.sRGB,.linearRGB] { for alpha:Float in [0,0.37,1] {
      let source=try Surface(width:79,height:53,depth:.f32,fill:Pixel(-0.2,0.18,2.4,alpha),colorEncoding:encoding)
      var dense=try Surface(width:79,height:53,depth:.f32,colorEncoding:encoding)
      for y in 0..<53 {for x in 0..<79 {dense.copyStoredSample(from:source,x:x,y:y,toX:x,toY:y)}}
      XCTAssertGreaterThan(dense.tileCount,0)
      let bounds=IntRect(x:2,y:3,width:75,height:47)
      let expected=try dense.reducedPreview(in:bounds,width:31,height:19)
      let actual=try source.reducedPreview(in:bounds,width:31,height:19)
      XCTAssertEqual(actual,expected,"\(encoding) alpha\(alpha)")
      XCTAssertEqual(actual.tileCount,0);XCTAssertEqual(actual.colorEncoding,encoding)
    } }
  }
  func fixture(_ depth: PixelDepth, linear: Bool = false) throws -> Surface {
    var s = try Surface(width: 129, height: 65, depth: depth, fill: Pixel(0.23,0.51,0.79,0.7), colorEncoding: linear ? .linearRGB : .sRGB)
    for y in 0..<65 { for x in 0..<129 where (x+y)%17 == 0 {
      s.setPixel(x:x,y:y,Pixel(Float((x*7)%255)/255,Float((y*19)%255)/255,Float((x+y)%255)/255,(x+y)%34==0 ? 0:0.4))
    } }; return s
  }
  func testAnalyticalCDFAndPagedEdgesMatchRetainedArrayEngineAtEveryDepthAndEncoding() throws {
    var ramp = try Surface(width:4,height:1)
    for x in 0..<4 { let v=Float(x)/3; ramp.setPixel(x:x,y:0,Pixel(v,v,v)) }
    let mapped = try PagedEqualize.render(ramp,mask:nil)
    XCTAssertEqual(try mapped.rgbaData(depth:.u8),Data([0,0,0,255,85,85,85,255,170,170,170,255,255,255,255,255]))
    for depth in PixelDepth.allCases { for linear in depth == .f32 ? [false,true]:[false] {
      let source=try fixture(depth,linear:linear)
      var mask=try Surface(width:source.width,height:source.height,depth:.u8,fill:.white)
      mask.setPixel(x:128,y:64,.black);mask.setPixel(x:2,y:3,Pixel(1.0/255,1.0/255,1.0/255))
      for selection in [false,true] {
        let dense:[Float]?=selection ? (0..<(source.width*source.height)).map{mask.pixel(x:$0%source.width,y:$0/source.width).r}:nil
        let expected=try ClassicToneEngine.render(source,settings:.init(.equalize),statisticsMask:dense)
        let actual=try PagedEqualize.render(source,mask:selection ? mask:nil)
        XCTAssertEqual(actual,expected,"\(depth) linear\(linear) selected\(selection)")
        XCTAssertEqual(actual.colorEncoding,source.colorEncoding);XCTAssertEqual(actual.depth,source.depth)
      }
    } }
  }
  func testWholeCommandsRetainLegacySelectionAffineAlphaStorageMasksAndMetadata() throws {
    for depth in PixelDepth.allCases { for kind in 0..<6 {
      var d=try CraftDocument(width:38,height:31,depth:depth)
      var pixels=try Surface(width:17,height:13,depth:depth,fill:Pixel(0.2,0.5,0.8,0.6),colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      for y in 0..<13 {for x in 0..<17 { pixels.setPixel(x:x,y:y,Pixel(Float(x)/17,Float(y)/13,Float(x+y)/30,(x+y)%3 == 0 ? 0:0.6)) }}
      d.layers[0].content = .raster(pixels);d.layers[0].x = kind==4 ? -3:9;d.layers[0].y=7
      d.layers[0].mask = try Surface(width:17,height:13,depth:depth,fill:Pixel(0.5,0.5,0.5))
      if kind==3 { d.layers[0].affine = .rotation(17) * .scale(1.1,0.9) }
      if kind==5 { d.layers[0].protection = .transparency }
      if kind>0 {
        var mask=try Surface(width:38,height:31,depth:.u8,fill:.black)
        for y in 8..<20 { for x in 7..<24 { let v=Float((x+y)%3+1)/3; mask.setPixel(x:x,y:y,Pixel(v,v,v)) } }
        d.setCoverageSelection(try SelectionMask(coverage:mask))
      }
      var settings=ClassicToneSettings(.equalize);settings.equalizeEntireImage = kind==2 || kind==4
      let request=ClassicToneRequest(settings,layerID:d.layers[0].id)
      var expected=d;try ClassicToneEngine.retained430BeforeApply(request,to:&expected)
      var actual=d;try Command.toneAdjustment(request).apply(to:&actual)
      XCTAssertEqual(actual,expected,"\(depth) context\(kind)")
      XCTAssertEqual(actual.selection,d.selection);XCTAssertEqual(actual.selectionMask,d.selectionMask)
    } }
  }
  func testMaximumConstantAndSparseCoverageUseImplicitStorageWithoutReducingDimensions() throws {
    for depth in PixelDepth.allCases { for whole in [false,true] {
      var d=try CraftDocument(width:300000,height:300000,depth:depth)
      let original=try Surface(width:d.width,height:d.height,depth:depth,fill:Pixel(0.2,0.5,0.8,0.6))
      d.layers[0].content = .raster(original)
      var mask=try Surface(width:d.width,height:d.height,depth:.u8,fill:.black)
      mask.setPixel(x:299999,y:299999,Pixel(128.0/255,128.0/255,128.0/255))
      d.setCoverageSelection(try SelectionMask(coverage:mask))
      var settings=ClassicToneSettings(.equalize);settings.equalizeEntireImage=whole
      let id=d.layers[0].id;try Command.toneAdjustment(.init(settings,layerID:id)).apply(to:&d)
      guard case .raster(let result)=d.layers[0].content else{return XCTFail("Missing raster")}
      let tiny=try Surface(width:1,height:1,depth:depth,fill:original.pixel(x:0,y:0))
      let expected=try ClassicToneEngine.render(tiny,settings:settings).pixel(x:0,y:0)
      let before=original.pixel(x:0,y:0),covered=whole ? expected:before.mixing(expected,coverage:128.0/255)
      var quantized=try Surface(width:1,height:1,depth:depth);quantized.setPixel(x:0,y:0,covered)
      XCTAssertEqual(result.pixel(x:299999,y:299999),quantized.pixel(x:0,y:0))
      XCTAssertEqual(result.pixel(x:0,y:0),whole ? expected:before)
      XCTAssertEqual(result.width,300000);XCTAssertEqual(result.height,300000)
      XCTAssertLessThan(result.allocatedBytes,2_000_000);XCTAssertLessThan(result.mappedBytes,2_000_000)
      XCTAssertEqual(result.tileCount,whole ? 0:1)
      XCTAssertNoThrow(try d.validate())
    } }
  }
  func testCancelledPreparationAndOtherToneAreaLimitsRemainAtomic() async throws {
    var d=try CraftDocument(width:300000,height:300000);d.layers[0].content = .raster(try Surface(width:d.width,height:d.height,fill:Pixel(0.2,0.5,0.8)))
    let original=d,request=ClassicToneRequest(.init(.equalize),layerID:d.layers[0].id)
    let task=Task { var next=original; try Task.checkCancellation();try Command.toneAdjustment(request).apply(to:&next);return next };task.cancel()
    do {_ = try await task.value;XCTFail("Cancelled edit committed")}catch is CancellationError {}catch {XCTFail("Unexpected \(error)")}
    XCTAssertEqual(d,original)
    XCTAssertThrowsError(try ClassicToneEngine.validateTarget(.init(.init(.matchColor),layerID:d.layers[0].id),in:d))
    XCTAssertEqual(ClassicToneEngine.maximumPixels(for:.equalize),90_000_000_000)
    XCTAssertEqual(ClassicToneEngine.maximumPixels(for:.hdrToning),8_388_608)
  }
}

// Frozen pre-430 array/ClonePainter expression, retained solely for regression comparison.
// Source SHA256 939e5157f97fff75c0bcdf3cd828d12baae4f3a9616618d1d33743c2d7bf80ae; original licensed PhotoCraft expression, not independent Photoshop evidence.
extension ClassicToneEngine {
  static func retained430BeforeApply(_ request:ClassicToneRequest,to document:inout CraftDocument)throws {
    let i=try validateTarget(request,in:document),s=request.settings,id=document.layers[i].id
    if document.layers[i].smartObject != nil {var f=RasterFilter(.shadowsHighlights);f.tone=s;try SmartFilterEngine.append(f,to:id,in:&document);return}
    guard case .raster(let source)=document.layers[i].content else{return}
    let original=document,extent=try SmartFilterEngine.renderBounds(document.layers[i],in:document)
    let ignore=s.kind == .equalize && s.equalizeEntireImage || s.kind == .matchColor && s.ignoreSelection
    let area=(ignore ? IntRect(x:0,y:0,width:document.width,height:document.height):document.selection ?? IntRect(x:0,y:0,width:document.width,height:document.height)).clipped(toWidth:document.width,height:document.height)
    guard area.width>0,area.height>0 else{return};var layer=document.layers[i]
    let mapped:Surface=layer.affine==nil ? try source.expanded(to:IntRect(x:extent.x-layer.x,y:extent.y-layer.y,width:extent.width,height:extent.height),fill:.clear):try RasterGeometry.render(source,transform:layer.coordinateTransform,bounds:extent,method:.bicubic,clampEdges:false)
    guard mapped.width<=maximumPixels/mapped.height else{throw CraftError.unsupported("Expanded tone target exceeds8,388,608 pixels.")}
    var mask=[Float]();mask.reserveCapacity(mapped.width*mapped.height)
    for y in 0..<mapped.height{try Task.checkCancellation();for x in 0..<mapped.width{mask.append(document.selectionCoverage(x:x+extent.x,y:y+extent.y))}}
    let output=try render(mapped,settings:s,statisticsMask:mask,origin:PathPoint(Double(extent.x),Double(extent.y)),canvasSize:PathPoint(Double(document.width),Double(document.height)))
    if output==mapped{return};let protect=document.isTransparencyLocked(id)
    _=try ClonePainter.paintTarget(mask:false,bounds:area,on:&layer,clipping:area,preserveTransparency:protect){pixels,transform,_ in
      guard pixels.width<=maximumPixels/pixels.height else{throw CraftError.unsupported("Expanded tone storage exceeds8,388,608 pixels.")};var changed=false
      for y in 0..<pixels.height{try Task.checkCancellation();for x in 0..<pixels.width{let q=transform.point(Double(x)+0.5,Double(y)+0.5),dx=Int(floor(q.x)),dy=Int(floor(q.y));guard area.contains(dx,dy) else{continue}
        let coverage=ignore ? 1:original.selectionCoverage(x:dx,y:dy);if coverage<=0{continue};let before=pixels.pixel(x:x,y:y);if protect && before.a==0{continue}
        var after=output.pixel(x:dx-extent.x,y:dy-extent.y);after.a=before.a
        let value=coverage>=1 ? after:before.mixing(after,coverage:coverage);if value.hasSameBits(as:before){continue};changed=true;pixels.setPixel(x:x,y:y,value)
      }};return changed
    };document.layers[i]=layer
  }
}
