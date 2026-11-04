import XCTest
@testable import PhotoCraftCore

final class BoundedChannelArithmeticTests:XCTestCase {
  func fixture(_ mode:DocumentColorMode,_ depth:PixelDepth,width:Int=6,height:Int=2)throws->CraftDocument {
    var document=try CraftDocument(width:width,height:height,depth:depth)
    var native=try NativeModeRaster(width:width,height:height,mode:mode,depth:depth)
    for c in 0..<mode.componentCount {native=try native.replacingChannel(c,with:Surface(width:width,height:height,depth:depth,fill:Pixel(0.125,0.125,0.125)))}
    native=try native.replacingOpacity(with:Surface(width:width,height:height,depth:depth,fill:Pixel(0.5,0.5,0.5)))
    document.modeDescriptor=try .init(mode:mode,depth:depth,profile:native.profile)
    document.layers[0].nativeMode=native;document.layers[0].content = .raster(try native.surface())
    return document
  }
  func testBoundedPlanesMatchEveryDenseWordForAllBlendsModesDepthsAndTargets()throws {
    for mode in DocumentColorMode.componentModes {
      for depth in mode.depths {
        var document=try fixture(mode,depth)
        var native=try XCTUnwrap(document.layers[0].nativeMode)
        for i in 0..<12 {
          for c in 0..<mode.componentCount {try native.set(Float((i+c)%7)/8,component:c,index:i)}
          try native.set([Float(0),0.5,1][i%3],component:mode.componentCount,index:i)
        }
        document.layers[0].nativeMode=native;document.layers[0].content = .raster(try native.surface())
        document.selection = .init(x:1,y:0,width:4,height:2)
        let selection=try AlphaChannel.coverage(document.coverageSelection(),width:6,height:2,depth:.f32)
        let input=ChannelArithmeticInput(samples:try Surface(width:6,height:2,depth:.f32,fill:Pixel(0.75,0.75,0.75)))
        let mask=try Surface(width:6,height:2,depth:.f32,fill:Pixel(0.625,0.625,0.625))
        for blend in ChannelArithmeticOptions.modes {for selected in [[],[0]] {
          var options=ChannelArithmeticOptions();options.blending=blend;options.opacity=0.375;options.scale=1.5;options.offset=17
          var dense=document
          try ChannelArithmeticEngine.apply(input,mask:mask,options:options,target:.pixels(document.layers[0].id,selected),to:&dense)
          let bounded=try ChannelArithmeticEngine.applyingNativePlanes(native,input:input,mask:mask,selection:selection,options:options,components:selected,preserve:!selected.isEmpty,transform:.identity)
          let expected=try XCTUnwrap(dense.layers[0].nativeMode)
          for c in 0...mode.componentCount {
            XCTAssertEqual(try bounded.planeBytes(c),try expected.planeBytes(c),"\(mode) \(depth) \(blend) \(selected) plane\(c)")
          }
        }}
      }
    }
  }
  func testBoundedNativeCompositeSourceKeepsFourthInkSeparateFromOpacity()throws {
    var document=try fixture(.cmyk,.u16)
    let source=ChannelArithmeticInput(samples:try Surface(width:6,height:2,depth:.f32,fill:Pixel(0.75,0.5,0.25,0.125)),components:4,mode:.cmyk)
    let original=try XCTUnwrap(document.layers[0].nativeMode)
    var options=ChannelArithmeticOptions();options.blending="normal";options.opacity=0.75
    let coverage=try Surface(width:6,height:2,depth:.f32,fill:.white)
    let bounded=try ChannelArithmeticEngine.applyingNativePlanes(original,input:source,mask:nil,selection:coverage,options:options,components:[],preserve:false,transform:.identity)
    try ChannelArithmeticEngine.apply(source,options:options,target:.pixels(document.layers[0].id,[]),to:&document)
    XCTAssertEqual(try bounded.planes,try document.layers[0].nativeMode?.planes)
    XCTAssertNotEqual(bounded.rawWord(component:3,index:0),bounded.rawWord(component:4,index:0))
  }
  func testMaximumSparseNativeApplyImageSelectionHistoryAndRawUntouchedPlanes()throws {
    let original=try fixture(.cmyk,.u16,width:300000,height:300000)
    var document=original;document.selection = .init(x:299998,y:299999,width:2,height:1)
    let before=document,native=try XCTUnwrap(document.layers[0].nativeMode)
    var options=ChannelArithmeticOptions();options.blending="normal"
    let input=ChannelArithmeticInput(samples:try Surface(width:document.width,height:document.height,depth:.f32,fill:Pixel(0.25,0.25,0.25)))
    try ChannelArithmeticEngine.apply(input,options:options,target:.pixels(document.layers[0].id,[1]),to:&document)
    let result=try XCTUnwrap(document.layers[0].nativeMode),last=89_999_999_999
    XCTAssertEqual(result.rawWord(component:1,index:0),native.rawWord(component:1,index:0))
    // Selected component painting preserves alpha, so half-opacity destination contributes half weight.
    let b:Float=1-native.value(component:1,index:last),w=native.value(component:4,index:last)
    let expected:UInt32=UInt32((unit(1-(b+(0.25-b)*w))*65535).rounded())
    XCTAssertEqual(result.rawWord(component:1,index:last),expected)
    for c in [0,2,3,4] {for i in [0,last-1,last] {XCTAssertEqual(result.rawWord(component:c,index:i),native.rawWord(component:c,index:i))}}
    XCTAssertLessThan(result.estimatedBytes,4*1024*1024)
    var session=EditorSession(document:before)
    try session.execute(.channelArithmetic(.init(source:before,result:document,title:"Apply Image")))
    XCTAssertEqual(session.undoStack.count,1);try session.undo();XCTAssertEqual(session.document,before)
    try session.redo();XCTAssertEqual(session.document,document)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(document)),document)
  }
  func testSmallNativeLayerExpandsToMaximumCanvasWithoutDenseAllocation()throws {
    var document=try fixture(.grayscale,.u16,width:1,height:1)
    document.width=300000;document.height=300000;document.layers[0].x=2;document.layers[0].y=1
    var options=ChannelArithmeticOptions();options.blending="normal"
    let input=ChannelArithmeticInput(samples:try Surface(width:300000,height:300000,depth:.f32,fill:.white))
    try ChannelArithmeticEngine.apply(input,options:options,target:.pixels(document.layers[0].id,[]),to:&document)
    let result=try XCTUnwrap(document.layers[0].nativeMode)
    XCTAssertEqual(result.width,300000);XCTAssertEqual(result.height,300000)
    XCTAssertEqual(result.rawWord(component:0,index:89_999_999_999),65535)
    XCTAssertEqual(result.rawWord(component:1,index:89_999_999_999),65535)
    XCTAssertLessThan(result.estimatedBytes,4*1024*1024)
  }
  func testBoundedFloatHDRSignedZeroAndOpacityGuards()throws {
    var document=try fixture(.rgb,.f32)
    var native=try XCTUnwrap(document.layers[0].nativeMode)
    try native.set(-0.0,component:1,index:0);try native.set(4,component:0,index:1)
    document.layers[0].nativeMode=native;document.layers[0].content = .raster(try native.surface())
    let input=ChannelArithmeticInput(samples:try Surface(width:6,height:2,depth:.f32,fill:Pixel(2,2,2)))
    var options=ChannelArithmeticOptions();options.blending="linearDodge"
    let selection=try Surface(width:6,height:2,depth:.f32,fill:.white)
    let result=try ChannelArithmeticEngine.applyingNativePlanes(native,input:input,mask:nil,selection:selection,options:options,components:[0],preserve:true,transform:.identity)
    XCTAssertEqual(result.rawWord(component:1,index:0),Float(-0.0).bitPattern)
    // ab=0.5: blend=6; mixed=2+(6-2)*0.5=4; final=4+(4-4)*0.5=4.
    XCTAssertEqual(result.value(component:0,index:1),4)
    var dense=document
    try ChannelArithmeticEngine.apply(input,options:options,target:.pixels(document.layers[0].id,[0]),to:&dense)
    XCTAssertEqual(try result.planes,try dense.layers[0].nativeMode?.planes)
    XCTAssertEqual(try result.opacityChannel().pixel(x:0,y:0).r,native.value(component:3,index:0))
    XCTAssertThrowsError(try native.replacingOpacity(with:Surface(width:6,height:2,depth:.f32,fill:Pixel(2,2,2))))
    XCTAssertThrowsError(try native.replacingOpacity(with:Surface(width:1,height:1,depth:.f32)))
  }
  func testFractionalLocalProjectionMatchesDenseNativeWords()throws {
    var document=try fixture(.rgb,.u16)
    document.layers[0].affine = .translation(0.25,0.5)
    document.selection = .init(x:1,y:0,width:4,height:2)
    var pixels=try Surface(width:6,height:2,depth:.f32,fill:.black)
    for y in 0..<2 {for x in 0..<6 {let v=Float(x+y)/8;pixels.setPixel(x:x,y:y,Pixel(v,v,v))}}
    let input=ChannelArithmeticInput(samples:pixels)
    var options=ChannelArithmeticOptions();options.blending="screen";options.opacity=0.375
    let native=try XCTUnwrap(document.layers[0].nativeMode)
    let coverage=try AlphaChannel.coverage(document.coverageSelection(),width:6,height:2,depth:.f32)
    let bounded=try ChannelArithmeticEngine.applyingNativePlanes(native,input:input,mask:nil,selection:coverage,options:options,components:[0],preserve:true,transform:document.layers[0].coordinateTransform)
    try ChannelArithmeticEngine.apply(input,options:options,target:.pixels(document.layers[0].id,[0]),to:&document)
    XCTAssertEqual(try bounded.planes,try document.layers[0].nativeMode?.planes)
  }
  func testCancelledBoundedArithmeticNeverPublishes()async throws {
    let document=try fixture(.rgb,.u16,width:300000,height:300000),original=document
    let task=Task { ()throws->CraftDocument in
      try await Task.sleep(for:.milliseconds(10));var candidate=document
      let input=ChannelArithmeticInput(samples:try Surface(width:300000,height:300000,depth:.f32,fill:.white))
      try ChannelArithmeticEngine.apply(input,options:.init(),target:.pixels(document.layers[0].id,[]),to:&candidate)
      return candidate
    };task.cancel()
    do {_ = try await task.value;XCTFail("Cancellation must throw")}catch is CancellationError {}
    XCTAssertEqual(document,original)
  }
}
