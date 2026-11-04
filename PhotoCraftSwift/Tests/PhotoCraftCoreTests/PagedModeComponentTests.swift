import Foundation
import XCTest
@testable import PhotoCraftCore

final class PagedModeComponentTests: XCTestCase {
  func fixture(_ mode:DocumentColorMode,_ depth:PixelDepth,width:Int=5,height:Int=3)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:depth)
    var n=try NativeModeRaster(width:width,height:height,mode:mode,depth:depth)
    if width*height<100 {
      for i in 0..<width*height {for c in 0...mode.componentCount {
        let value:Float = c==mode.componentCount ? Float(i%4)/3 : depth == .f32 ? [Float(-0.0),Float(bitPattern:1),-0.5,2,0.25][(i+c)%5]:Float((i*17+c*23)%256)/255
        try n.set(value,component:c,index:i)
      }}
    }
    d.modeDescriptor=try .init(mode:mode,depth:depth,profile:n.profile)
    d.layers[0].nativeMode=n;d.layers[0].content = .raster(try n.surface())
    return d
  }
  func operations()->[ModeComponentEdit.Operation] {
    var brush=Brush();brush.size=1.5;brush.color=Pixel(0.2,0.4,0.6,0.75)
    var erase=brush;erase.erase=true;erase.backgroundColor=Pixel(0.6,0.3,0.1)
    var configured=brush;configured.settings=BrushSettings()
    var result:[ModeComponentEdit.Operation]=[.fill(0.25,0.6),.invert,.stroke([.init(x:1.5,y:1.5),.init(x:3.5,y:2.5)],brush),.stroke([.init(x:2,y:1)],erase),.stroke([.init(x:2,y:1)],configured)]
    for kind in ModeComponentEdit.filters.sorted(by:{$0.rawValue<$1.rawValue}) {var f=RasterFilter(kind);f.radius=1;f.amount=25;f.seed=37;result.append(.filter(f))}
    return result
  }
  func testForcedPagedPathMatchesPreservedDenseOperationsEveryModeDepthAndContext() throws {
    for mode in DocumentColorMode.componentModes {for depth in mode.depths {
      let original=try fixture(mode,depth)
      for context in 0..<4 {
        var before=original
        if context==1 {before.selection = .init(x:1,y:0,width:3,height:2);before.layers[0].affine = .scale(0.7,1.3)}
        if context==2 {
          before.setCoverageSelection(try SelectionMask(width:5,height:3,bytes:(0..<15).map{UInt8(($0*31)%256)}))
          before.layers[0].x=1;before.layers[0].y = -1
        }
        if context==3 {before.selection = .init(x:0,y:0,width:3,height:3);before.layers[0].affine = .rotation(19)}
        for op in operations() {
          let edit=ModeComponentEdit(layerID:before.layers[0].id,components:Set([0,mode.componentCount-1]),operation:op)
          var dense=before,paged=before
          try edit.apply(to:&dense);try edit.applyPaged(to:&paged)
          XCTAssertEqual(paged,dense,"\(mode)/\(depth)/context\(context)/\(edit.label)")
        }
      }
    }}
  }
  func testMaximumUniformFillInvertRetainRawOtherComponentsAlphaAndHistory() throws {
    for mode in DocumentColorMode.componentModes {for depth in mode.depths {
      let before=try fixture(mode,depth,width:300000,height:300000),id=before.layers[0].id
      let old=try XCTUnwrap(before.layers[0].nativeMode)
      var session=EditorSession(document:before)
      try session.execute(.modeComponents(.init(layerID:id,components:[0],operation:.fill(0.25,1))))
      let after=try XCTUnwrap(session.document.layers[0].nativeMode)
      let expected=depth.quantize(mode == .cmyk ? 0.75:0.25)
      for at in [0,89_999_999_999] {
        XCTAssertEqual(after.value(component:0,index:at),expected)
        for c in 1...mode.componentCount {XCTAssertEqual(after.rawWord(component:c,index:at),old.rawWord(component:c,index:at))}
      }
      XCTAssertLessThan(after.estimatedBytes,2_000_000);XCTAssertEqual(after.mappedComponentSampleBytes,0)
      try session.undo();XCTAssertEqual(session.document,before);try session.redo();XCTAssertEqual(session.document.layers[0].nativeMode,after)
      try session.execute(.modeComponents(.init(layerID:id,components:[0],operation:.invert)))
      XCTAssertEqual(session.document.layers[0].nativeMode?.value(component:0,index:0),depth.quantize(1-expected))
    }}
    let before=try fixture(.cmyk,.u16,width:300000,height:300000);var result=before
    try ModeComponentEdit(layerID:before.layers[0].id,components:[0],operation:.fill(0.25,1)).apply(to:&result)
    try capture("maximum-cmyk-fill",(0..<5).map {result.layers[0].nativeMode!.rawWord(component:$0,index:89_999_999_999)})
  }
  func testMaximumSparseSoftSelectionAndAffineCoverageUseExistingForwardSamples() throws {
    var before=try fixture(.rgb,.f32,width:300000,height:300000)
    var coverage=try Surface(width:300000,height:300000,fill:.black)
    coverage.setPixel(x:299997,y:299996,Pixel(128.0/255,128.0/255,128.0/255));before.setCoverageSelection(try .init(coverage:coverage))
    before.layers[0].x=1;before.layers[0].y=2
    let id=before.layers[0].id;var result=before
    try ModeComponentEdit(layerID:id,components:[0],operation:.fill(1,0.5)).apply(to:&result)
    let n=try XCTUnwrap(result.layers[0].nativeMode),at=299994*300000+299996
    XCTAssertEqual(n.value(component:0,index:at),Float(128)/255*0.5)
    XCTAssertEqual(n.rawWord(component:0,index:at+1),0)
    XCTAssertEqual(n.rawWord(component:3,index:at),0)
    XCTAssertLessThan(n.estimatedBytes,2_000_000)
    try capture("maximum-soft-fill",[n.rawWord(component:0,index:at),n.rawWord(component:0,index:at+1),n.rawWord(component:3,index:at)])
  }
  func testMaximumBrushEraseAndConfiguredBrushKeepUntargetedWords() throws {
    let before=try fixture(.cmyk,.u16,width:300000,height:300000),old=before.layers[0].nativeMode!,id=before.layers[0].id
    for erased in [false,true] {for configured in [false,true] {
      var brush=Brush();brush.size=1;brush.hardness=1;brush.color = .black;brush.erase=erased;brush.backgroundColor = .white
      if configured {brush.settings=BrushSettings()}
      var d=before
      try ModeComponentEdit(layerID:id,components:[0],operation:.stroke([.init(x:299999.5,y:299999.5)],brush)).apply(to:&d)
      let n=d.layers[0].nativeMode!
      XCTAssertEqual(n.value(component:0,index:89_999_999_999),erased ? 0:1)
      for c in 1..<5 {XCTAssertEqual(n.rawWord(component:c,index:89_999_999_999),old.rawWord(component:c,index:89_999_999_999))}
      XCTAssertLessThan(n.estimatedBytes,2_000_000)
    }}
  }
  func testMaximumUniformSevenFiltersMatchSmallDenseResult() throws {
    for depth in PixelDepth.allCases {for linear in [false,true] {
      for pixel in [Pixel.black,.white,.clear,Pixel(-0.0,1,-0.0,1),Pixel(0.2,0.6,0.7,0.8)] {
        for angle in [0.0,31.7] {
          var d=try CraftDocument(width:7,height:5,depth:depth)
          var surface=try Surface(width:7,height:5,depth:depth,fill:pixel)
          if depth == .f32 && linear {surface=try surface.interpretingSamples(as:.linearRGB)}
          d.layers[0].content = .raster(surface)
          var dense=d,paged=d;var motion=RasterFilter(.motionBlur);motion.distance=10;motion.angle=angle
          try RasterFilterEngine.apply(motion,to:d.layers[0].id,in:&dense)
          try PagedRasterFilters.apply(motion,to:d.layers[0].id,in:&paged)
          XCTAssertEqual(paged,dense,"Motion constant/\(depth)/\(linear)/\(angle)/\(pixel)")
        }
      }
    }}
    let large=try fixture(.rgb,.u8,width:300000,height:300000),small=try fixture(.rgb,.u8,width:1,height:1)
    var opaqueSmall=small;let sn=try NativeModeRaster(width:1,height:1,mode:.rgb,depth:.u8);opaqueSmall.layers[0].nativeMode=sn;opaqueSmall.layers[0].content = .raster(try sn.surface())
    for kind in ModeComponentEdit.filters.subtracting([.addNoise]).sorted(by:{$0.rawValue<$1.rawValue}) {
      var a=large,b=opaqueSmall;var f=RasterFilter(kind);f.radius=1
      try ModeComponentEdit(layerID:a.layers[0].id,components:[0],operation:.filter(f)).apply(to:&a)
      try ModeComponentEdit(layerID:b.layers[0].id,components:[0],operation:.filter(f)).apply(to:&b)
      let n=a.layers[0].nativeMode!
      XCTAssertEqual(n.rawWord(component:0,index:89_999_999_999),b.layers[0].nativeMode!.rawWord(component:0,index:0),"\(kind)")
      XCTAssertEqual(n.rawWord(component:3,index:0),large.layers[0].nativeMode!.rawWord(component:3,index:0))
      XCTAssertLessThan(n.estimatedBytes,2_000_000)
    }
  }
  func testLargeNoiseBeyondOldAdmissionUsesDeterministicPagedOutput() throws {
    let before=try fixture(.rgb,.u8,width:4097,height:2048);var d=before
    var f=RasterFilter(.addNoise);f.seed=37;f.amount=25;f.distribution = .uniform;f.monochromatic=true
    try ModeComponentEdit(layerID:d.layers[0].id,components:[0],operation:.filter(f)).apply(to:&d)
    let n=d.layers[0].nativeMode!,indices=[0,1,4_195_327,8_390_655]
    for i in indices {
      var z=UInt64(37) &+ (UInt64(i+1) &* 0x9E3779B97F4A7C15)
      z=(z^(z>>30)) &* 0xBF58476D1CE4E5B9;z=(z^(z>>27)) &* 0x94D049BB133111EB;z ^= z>>31
      let noise=((Double(z>>11)+0.5)/9_007_199_254_740_992*2-1)*0.25
      XCTAssertEqual(n.value(component:0,index:i),PixelDepth.u8.quantize(Float(noise)))
      XCTAssertEqual(n.rawWord(component:1,index:i),0);XCTAssertEqual(n.rawWord(component:3,index:i),0)
    }
    XCTAssertEqual(n.residentComponentEditBytes,0);XCTAssertGreaterThan(n.mappedComponentSampleBytes,0)
    try capture("large-noise",indices.map {n.rawWord(component:0,index:$0)})
  }
  func testCoverageExtremeTransformsAndImplicitMaskMatchLiteralForwardLoop() throws {
    for transform in [Transform2D.scale(0.001,0.001),.scale(1000,1000),.translation(-7,2),.rotation(24)] {
      for implicit in [Float(0),1] {
        var d=try CraftDocument(width:11,height:7)
        var s=try Surface(width:11,height:7,fill:Pixel(implicit,implicit,implicit));s.setPixel(x:4,y:3,Pixel(0.5,0.5,0.5))
        d.setCoverageSelection(try .init(coverage:s))
        let result=try ModeComponentEdit.pagedCoverage(d,transform:transform,width:5,height:3)
        for y in 0..<3 {for x in 0..<5 {let q=transform.point(Double(x)+0.5,Double(y)+0.5);XCTAssertEqual(result.pixel(x:x,y:y).r,d.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y))))}}
        d.selectionMask=nil;d.selection = .init(x:1,y:1,width:9,height:5)
        let rectangle=try ModeComponentEdit.pagedCoverage(d,transform:transform,width:5,height:3)
        for y in 0..<3 {for x in 0..<5 {let q=transform.point(Double(x)+0.5,Double(y)+0.5);XCTAssertEqual(rectangle.pixel(x:x,y:y).r,d.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y))))}}
      }
    }
  }
  func testNumericRGBBridgeMatchesDenseAcrossDepthsAndEncodings() throws {
    for depth in PixelDepth.allCases {for encoded in [false,true] {
      var d=try CraftDocument(width:5,height:3,depth:depth),s=try Surface(width:5,height:3,depth:depth)
      for y in 0..<3 {for x in 0..<5 {s.setPixel(x:x,y:y,Pixel(Float(x)/5,Float(y)/3,0.37,0.5))}}
      if depth == .f32 && !encoded {s=try s.interpretingSamples(as:.linearRGB)}
      d.layers[0].content = .raster(s)
      for op in operations() {var a=d,b=d;let e=ModeComponentEdit(layerID:d.layers[0].id,components:[0,2],operation:op);try e.apply(to:&a);try e.applyPaged(to:&b);XCTAssertEqual(a,b,"\(depth)/\(encoded)/\(e.label)")}
    }}
  }
  func testCancelledInvalidAndLockedLargeEditsAreAtomic() async throws {
    let original=try fixture(.lab,.u16,width:300000,height:300000),id=original.layers[0].id
    for operation:ModeComponentEdit.Operation in [.fill(.nan,1),.fill(0,2),.filter(.init(.cameraRaw))] {
      var d=original;XCTAssertThrowsError(try ModeComponentEdit(layerID:id,components:[0],operation:operation).apply(to:&d));XCTAssertEqual(d,original)
    }
    var locked=original;locked.layers[0].locked=true;let old=locked
    XCTAssertThrowsError(try ModeComponentEdit(layerID:id,components:[0],operation:.invert).apply(to:&locked));XCTAssertEqual(locked,old)
    let task=Task<Void,Error> {withUnsafeCurrentTask{$0?.cancel()};var d=original;XCTAssertThrowsError(try ModeComponentEdit(layerID:id,components:[0],operation:.invert).apply(to:&d));XCTAssertEqual(d,original)}
    try await task.value
  }
  func capture(_ name:String,_ words:[UInt32])throws {
    guard let folder=ProcessInfo.processInfo.environment["PHOTATO_COMPONENT_OUTPUT_DIR"]else{return}
    var data=Data();for word in words {for shift in [0,8,16,24] {data.append(UInt8(truncatingIfNeeded:word>>shift))}}
    try data.write(to:URL(fileURLWithPath:folder).appendingPathComponent(name+".bin"))
  }
}
