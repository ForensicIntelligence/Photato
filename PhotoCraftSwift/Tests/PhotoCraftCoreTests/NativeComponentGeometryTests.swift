import Foundation
import XCTest
@testable import PhotoCraftCore

final class NativeComponentGeometryTests:XCTestCase {
  func fixture(_ mode:DocumentColorMode,_ depth:PixelDepth)throws->NativeModeRaster {
    var n=try NativeModeRaster(width:5,height:3,mode:mode,depth:depth)
    for i in 0..<15 {
      for c in 0..<mode.componentCount {
        let v:Float=depth == .f32 ? [-0.0,Float(bitPattern:1),2,-3.5,0.25][(i+c)%5]:Float((i*17+c*31)%257)/256
        try n.set(v,component:c,index:i)
      }
      try n.set([Float(0),0.25,0.5,1][i%4],component:mode.componentCount,index:i)
    }
    return n
  }
  func testEveryModeDepthMethodAndEdgeRuleMatchesPreservedDenseGeometry() throws {
    let transforms:[Transform2D]=[.identity,.scale(1.7,1.3),.rotation(23),.translation(0.25,-0.25),CanvasTurn.clockwise.transform(width:5,height:3)]
    for mode in DocumentColorMode.componentModes {for depth in mode.depths {
      let n=try fixture(mode,depth)
      for t in transforms {for method in Resampling.allCases {for clamp in [false,true] {
        let bounds=try t.bounds(width:n.width,height:n.height)
        let actual=try n.transformed(by:t,bounds:bounds,method:method,clampEdges:clamp)
        let expected=try legacy(n,t,bounds,method,clamp)
        XCTAssertEqual(actual,expected,"\(mode)/\(depth)/\(method)/\(clamp)/\(t)")
        XCTAssertEqual(actual.profile,n.profile);XCTAssertEqual(actual.intent,n.intent)
      }}}
    }}
  }
  func testMaximumNearestGridTurnsPreserveLiteralWords() throws {
    var n=try NativeModeRaster(width:300000,height:300000,mode:.rgb,depth:.f32)
    let at=90_000_000_000-1,words:[UInt32]=[1,0x80000000,0x40000000,0x3f800000]
    for c in 0..<4 {try n.set(Float(bitPattern:words[c]),component:c,index:at)}
    for turn in CanvasTurn.allCases {
      let t=turn.transform(width:n.width,height:n.height),bounds=try t.bounds(width:n.width,height:n.height)
      let p=t.point(299999.5,299999.5),index=(Int(floor(p.y))-bounds.y)*bounds.width+Int(floor(p.x))-bounds.x
      let result=try n.transformed(by:t,bounds:bounds,method:.nearest)
      for c in 0..<4 {XCTAssertEqual(result.rawWord(component:c,index:index),words[c])}
      XCTAssertLessThan(result.estimatedBytes,2_000_000);XCTAssertEqual(result.rawWord(component:3,index:index==0 ? 1:0),0)
    }
    let flipped=try n.transformed(by:CanvasTurn.horizontal.transform(width:n.width,height:n.height),bounds:.init(x:0,y:0,width:n.width,height:n.height),method:.nearest)
    try capture("grid-maximum-words",(0..<4).map {flipped.rawWord(component:$0,index:299999*300000)})
  }
  func testMaximumSparseNearestResizeUsesImplicitDefaultsAndLastPixel() throws {
    var n=try NativeModeRaster(width:300000,height:300000,mode:.cmyk,depth:.u16)
    try n.set(0.75,component:3,index:90_000_000_000-1);try n.set(1,component:4,index:90_000_000_000-1)
    let result=try n.transformed(by:.scale(0.5,0.5),bounds:.init(x:0,y:0,width:150000,height:150000),method:.nearest,clampEdges:true)
    XCTAssertEqual(result.rawWord(component:3,index:22_500_000_000-1),49151)
    XCTAssertEqual(result.rawWord(component:4,index:22_500_000_000-1),65535)
    XCTAssertEqual(result.rawWord(component:3,index:0),0);XCTAssertLessThan(result.estimatedBytes,2_000_000)
  }
  func testHugeUniformSourceToSmallInterpolationMatchesIndependentDenseKernel() throws {
    let pixels=try Surface(width:300000,height:300000,depth:.f32,fill:Pixel(0.25,0.5,0.75,0.5)).interpretingSamples(as:.linearRGB)
    let n=try NativeModeRaster.retainingRGBSamples(pixels),t=Transform2D.scale(13.0/300000,7.0/300000),bounds=IntRect(x:0,y:0,width:13,height:7),inverse=try t.inverted()
    for method in Resampling.allCases {
      let result=try n.transformed(by:t,bounds:bounds,method:method,clampEdges:true)
      var words:[UInt32]=[]
      for y in 0..<7 {for x in 0..<13 {
        let p=inverse.point(Double(x)+0.5,Double(y)+0.5)
        let q=oldSample(width:300000,height:300000,x:p.x,y:p.y,method:method,clamp:true) {_,_ in Pixel(0.25,0.5,0.75,0.5)}
        let expected=[q.r,q.g,q.b,q.a]
        for c in 0..<4 {let word=result.rawWord(component:c,index:y*13+x);XCTAssertEqual(word,expected[c].bitPattern);words.append(word)}
      }}
      try capture("uniform-resample-\(method.rawValue)",words)
      let smallest=try n.transformed(by:.scale(1.0/300000,1.0/300000),bounds:.init(x:0,y:0,width:1,height:1),method:method,clampEdges:true)
      XCTAssertEqual((0..<4).map {smallest.rawWord(component:$0,index:0)},[0.25,0.5,0.75,0.5].map {Float($0).bitPattern})
    }
    for rejected in [Transform2D.scale(0,1),.scale(1e-7,1e-7),.init(a:1,b:1,c:1,d:1),.init(a:.nan),.init(tx:.infinity)] {
      XCTAssertThrowsError(try rejected.inverted())
    }
  }
  func testReframeKeepsAllRawSamplesAgainstPriorRowAlgorithm() throws {
    for mode in DocumentColorMode.componentModes {for depth in mode.depths {
      let n=try fixture(mode,depth)
      for box in [IntRect(x:-2,y:-1,width:9,height:6),.init(x:1,y:-1,width:5,height:4),.init(x:100,y:0,width:3,height:3)] {
        for background:Pixel? in [nil,Pixel(0.2,0.4,0.6,1)] {
          let actual=try n.reframedExactly(bounds:box,background:background)
          var expected=try NativeModeRaster(width:box.width,height:box.height,mode:mode,depth:depth,profile:n.profile,intent:n.intent)
          let values=try background.map {try NativeModeTransform(mode:mode,depth:depth,profile:n.profile,intent:n.intent).components(depth == .f32 ? SRGBTransfer.linear($0):$0)} ?? Array(repeating:Float(0),count:mode.componentCount+1)
          for y in 0..<box.height {for x in 0..<box.width {for c in 0...mode.componentCount {
            let sx=box.x+x,sy=box.y+y,v=sx>=0 && sy>=0 && sx<n.width && sy<n.height ? n.value(component:c,index:sy*n.width+sx):values[c]
            try expected.set(v,component:c,index:y*box.width+x)
          }}}
          XCTAssertEqual(actual,expected,"\(mode)/\(depth)/\(box)")
        }
      }
    }}
  }
  func testMaximumUniformExpandedReframeStaysImplicit() throws {
    let n=try NativeModeRaster(width:300000,height:299999,mode:.rgb,depth:.f32)
    let result=try n.reframedExactly(bounds:.init(x:0,y:-1,width:300000,height:300000))
    XCTAssertEqual(result.height,300000);XCTAssertEqual(result.residentComponentEditBytes,0)
    XCTAssertEqual(result.mappedComponentSampleBytes,0);XCTAssertEqual(result.rawWord(component:3,index:90_000_000_000-1),0)
    let outside=try n.reframedExactly(bounds:.init(x:500000,y:500000,width:300000,height:300000))
    XCTAssertEqual(outside.mappedComponentSampleBytes,0)
  }
  func testContrastReframeBeyondOldAdmissionUsesCheckedMappedOutput() throws {
    let n=try NativeModeRaster(width:300000,height:31,mode:.rgb,depth:.u16)
    let result=try n.reframedExactly(bounds:.init(x:0,y:-1,width:300000,height:33),background:Pixel(0.2,0.4,0.6,1))
    XCTAssertEqual(result.height,33);XCTAssertEqual(result.residentComponentEditBytes,0)
    XCTAssertGreaterThan(result.mappedComponentSampleBytes,0)
    XCTAssertLessThan(result.mappedComponentSampleBytes,20_000_000)
    let expected:[UInt32]=[13107,26214,39321,65535]
    for (c,word) in expected.enumerated() {
      XCTAssertEqual(result.rawWord(component:c,index:0),word)
      XCTAssertEqual(result.rawWord(component:c,index:300000),0)
      XCTAssertEqual(result.rawWord(component:c,index:300000*33-1),word)
    }
  }
  func testTrimMatchesPriorNumericalScanIncludingImplicitGaps() throws {
    for mode in DocumentColorMode.componentModes {for depth in mode.depths {
      let n=try fixture(mode,depth)
      for basis in [TrimOptions.Basis.transparent,.topLeft,.bottomRight] {
        var options=TrimOptions(basis:basis);options.right=false
        let ref=n.components(index:basis == .bottomRight ? 14:0)
        var x0=5,y0=3,x1=0,y1=0
        for y in 0..<3 {for x in 0..<5 {
          let i=y*5+x,keep=basis == .transparent ? n.value(component:mode.componentCount,index:i)>0:n.components(index:i) != ref
          if keep {x0=min(x0,x);y0=min(y0,y);x1=max(x1,x+1);y1=max(y1,y+1)}
        }}
        XCTAssertEqual(try n.trimBounds(options),options.bounds(content:.init(x:x0,y:y0,width:x1-x0,height:y1-y0),width:5,height:3))
      }
    }}
    var big=try NativeModeRaster(width:300000,height:300000,mode:.rgb,depth:.u16)
    try big.set(1,component:3,index:30*300000+40);try big.set(1,component:3,index:299997*300000+299998)
    XCTAssertEqual(try big.trimBounds(.init(basis:.transparent)),.init(x:40,y:30,width:299959,height:299968))
    let opaque=try NativeModeRaster.retainingRGBSamples(Surface(width:300000,height:300000,depth:.u8,fill:.white))
    XCTAssertEqual(try opaque.trimBounds(.init(basis:.transparent)),.init(x:0,y:0,width:300000,height:300000))
  }
  func testBudgetIOAndCancellationLeaveSourceUnchanged() async throws {
    let n=try fixture(.rgb,.f32),copy=n
    XCTAssertThrowsError(try n.resampled(by:.identity,bounds:.init(x:0,y:0,width:5,height:3),method:.nearest,clampEdges:false,scratchMaximumBytes:0,directory:nil))
    let missing=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    XCTAssertThrowsError(try n.resampled(by:.scale(2,2),bounds:.init(x:0,y:0,width:10,height:6),method:.bicubic,clampEdges:true,scratchMaximumBytes:1_000_000,directory:missing))
    XCTAssertEqual(n,copy)
    let task=Task<Void,Error> {withUnsafeCurrentTask {$0?.cancel()};XCTAssertThrowsError(try n.transformed(by:.identity,bounds:.init(x:0,y:0,width:5,height:3),method:.nearest))}
    try await task.value;XCTAssertEqual(n,copy)
  }
  func testDerivedSurfacesAndChannelsStreamBeyondSmallWorkingSet() throws {
    var n=try NativeModeRaster(width:128,height:2048,mode:.rgb,depth:.f32)
    for block in 0..<64 {let i=block*4096+1;try n.set(Float(block+1)/64,component:0,index:i);try n.set(1,component:3,index:i)}
    let surface=try n.surface(),channel=try n.channel(0),view=try n.presentingComponents([0])
    XCTAssertGreaterThan(surface.mappedBytes,0);XCTAssertLessThan(surface.allocatedBytes,100_000)
    XCTAssertGreaterThan(channel.mappedBytes,0);XCTAssertGreaterThan(view.mappedBytes,0)
    for y in 0..<2048 {for x in 0..<128 {
      let i=y*128+x,v=n.value(component:0,index:i),a=n.value(component:3,index:i)
      XCTAssertTrue(surface.linearPixel(x:x,y:y).hasSameBits(as:Pixel(v,0,0,a)))
      XCTAssertTrue(channel.pixel(x:x,y:y).hasSameBits(as:Pixel(v,v,v)))
      XCTAssertTrue(view.pixel(x:x,y:y).hasSameBits(as:Pixel(v,v,v,a)))
    }}
  }
  func capture(_ name:String,_ words:[UInt32])throws {
    guard let folder=ProcessInfo.processInfo.environment["PHOTATO_COMPONENT_OUTPUT_DIR"]else{return}
    var bytes=Data();for word in words {for shift in [0,8,16,24] {bytes.append(UInt8(truncatingIfNeeded:word>>shift))}}
    try bytes.write(to:URL(fileURLWithPath:folder).appendingPathComponent(name+".bin"))
  }
  // Preserved pre392 implementation from391, with the old kernel below. This is
  // an owned native regression oracle, not a Photoshop rendering comparison.
  func legacy(_ n:NativeModeRaster,_ t:Transform2D,_ box:IntRect,_ method:Resampling,_ clamp:Bool)throws->NativeModeRaster {
    let inverse=try t.inverted();var out=try NativeModeRaster(width:box.width,height:box.height,mode:n.mode,depth:n.depth,profile:n.profile,intent:n.intent)
    for c in 0..<n.mode.componentCount {
      var channel=try Surface(width:n.width,height:n.height,depth:.f32)
      for y in 0..<n.height {for x in 0..<n.width {let i=y*n.width+x,v=n.value(component:c,index:i);channel.setPixel(x:x,y:y,Pixel(v,v,v,n.value(component:n.mode.componentCount,index:i)))}}
      for y in 0..<box.height {for x in 0..<box.width {
        let p=inverse.point(Double(box.x+x)+0.5,Double(box.y+y)+0.5)
        if p.x<0 || p.y<0 || p.x>=Double(n.width) || p.y>=Double(n.height) {continue}
        let q=oldSample(width:n.width,height:n.height,x:p.x,y:p.y,method:method,clamp:clamp) {channel.pixel(x:$0,y:$1)}
        try out.set(q.r,component:c,index:y*box.width+x)
        if c==0 {try out.set(q.a,component:n.mode.componentCount,index:y*box.width+x)}
      }}
    }
    return out
  }
  func oldSample(width:Int,height:Int,x:Double,y:Double,method:Resampling,clamp:Bool,source:(Int,Int)->Pixel)->Pixel {
    guard x.isFinite, y.isFinite, abs(x) < 10_000_000, abs(y) < 10_000_000 else { return .clear }
    func pixel(_ ix:Int,_ iy:Int)->Pixel {
      let x=clamp ? min(width-1,max(0,ix)):ix,y=clamp ? min(height-1,max(0,iy)):iy
      return source(x,y)
    }
    if method == .nearest { return pixel(Int(floor(x)), Int(floor(y))) }
    let sx = x - 0.5
    let sy = y - 0.5
    let ix = Int(floor(sx))
    let iy = Int(floor(sy))
    func pm(_ p: Pixel) -> SIMD4<Float> { SIMD4(p.r * p.a, p.g * p.a, p.b * p.a, p.a) }
    let fx = Float(sx - Double(ix))
    let fy = Float(sy - Double(iy))
    let value: SIMD4<Float>
    if method == .bilinear {
      value =
        (pm(pixel(ix, iy)) * (1 - fx) + pm(pixel(ix + 1, iy)) * fx) * (1 - fy)
        + (pm(pixel(ix, iy + 1)) * (1 - fx) + pm(pixel(ix + 1, iy + 1)) * fx) * fy
    } else {
      func weight(_ n: Float) -> Float {
        let v = abs(n)
        if v <= 1 { return 1.5 * v * v * v - 2.5 * v * v + 1 }
        if v < 2 { return -0.5 * v * v * v + 2.5 * v * v - 4 * v + 2 }
        return 0
      }
      var sum = SIMD4<Float>.zero
      for j in -1...2 {
        for i in -1...2 {
          sum += pm(pixel(ix + i, iy + j)) * weight(Float(i) - fx) * weight(Float(j) - fy)
        }
      }
      value = sum
    }
    guard value.w > 1e-8 else { return .clear }
    return Pixel(value.x / value.w, value.y / value.w, value.z / value.w, unit(value.w))
  }
}
