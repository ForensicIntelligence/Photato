import Foundation
import XCTest
@testable import PhotoCraftCore

final class ChannelSeparationTests:XCTestCase {
  func fixture(_ mode:DocumentColorMode = .rgb,_ depth:PixelDepth = .u8,width:Int=4,height:Int=1)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:depth,name:"Owned source")
    var n=try NativeModeRaster(width:width,height:height,mode:mode,depth:depth)
    n=try n.replacingOpacity(with:Surface(width:width,height:height,depth:depth,fill:.white))
    for c in 0..<mode.componentCount {for x in 0..<min(width,4) {
      try n.set(Float((x+c)%4)/3,component:c,index:x)
    }}
    d.modeDescriptor=try .init(mode:mode,depth:depth,profile:n.profile)
    d.layers[0].nativeMode=n;d.layers[0].content = .raster(try n.surface())
    return d
  }
  func testLiteralComponentWordsAreSeparatedWithoutAColorRoundtrip()throws {
    var captures=Data(),expected=Data()
    for mode in DocumentColorMode.componentModes {for depth in mode.depths {
      var d=try fixture(mode,depth),n=try XCTUnwrap(d.layers[0].nativeMode)
      let words:[UInt32] = depth == .u8 ? [0,64,128,255]:depth == .u16 ? [0,16384,32768,65535]:[0x80000000,1,0x3f800001,0xc0500000]
      for c in 0..<mode.componentCount {for x in 0..<4 {
        let word=words[(x+c)%4],v=depth == .f32 ? Float(bitPattern:word):Float(word)/(depth == .u8 ? 255:65535)
        try n.set(v,component:c,index:x)
      }}
      d.layers[0].nativeMode=n;d.layers[0].content = .raster(try n.surface())
      if mode == .grayscale {d.alphaChannels=[.init(name:"Separation companion",pixels:try Surface(width:4,height:1,depth:depth,fill:.white))]}
      let source=d
      XCTAssertNil(ChannelSeparation.unavailableReason(d))
      let plan=try ChannelSeparation.prepare(d);XCTAssertEqual(plan.source,source);XCTAssertEqual(d,source)
      XCTAssertEqual(plan.outputs.count,mode.componentCount+(mode == .grayscale ? 1:0))
      for (c,output) in plan.outputs.prefix(mode.componentCount).enumerated() {
        let result=output.document,gray=try XCTUnwrap(result.layers[0].nativeMode)
        XCTAssertEqual(result.colorMode,.grayscale);XCTAssertEqual(result.depth,depth);XCTAssertTrue(result.layers[0].isBackground)
        for x in 0..<4 {
          var word=words[(x+c)%4];if mode == .cmyk {word=(depth == .u8 ? 255:65535)-word}
          XCTAssertEqual(gray.rawWord(component:0,index:x),word,"\(mode) \(depth) channel\(c) x\(x)")
          var actual=gray.rawWord(component:0,index:x).littleEndian,wanted=word.littleEndian
          withUnsafeBytes(of:&actual){captures.append(contentsOf:$0)};withUnsafeBytes(of:&wanted){expected.append(contentsOf:$0)}
          XCTAssertEqual(gray.value(component:1,index:x),1)
        }
      }
    }}
    XCTAssertEqual(captures,expected)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try captures.write(to:URL(fileURLWithPath:path).appendingPathComponent("split-component-words.u32le"))
      try expected.write(to:URL(fileURLWithPath:path).appendingPathComponent("split-component-reference.u32le"))
    }
  }
  func testRGBWithoutNativeStorageAndRawAlphaIgnoreDisplayInversion()throws {
    for depth in PixelDepth.allCases {
      var d=try CraftDocument(width:2,height:1,depth:depth)
      var p=try Surface(width:2,height:1,depth:depth,fill:.white,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      if depth == .f32 {p.setLinearPixel(x:0,y:0,Pixel(0.125,0.25,0.5))}else{p.setPixel(x:0,y:0,Pixel(0.125,0.25,0.5))}
      d.layers[0].content = .raster(p)
      var options=ChannelDisplayOptions();options.indicates = .selectedAreas
      d.alphaChannels=[.init(name:"Mask 日本語",pixels:try Surface(width:2,height:1,depth:depth,fill:Pixel(0.25,0.25,0.25)),options:options)]
      let plan=try ChannelSeparation.prepare(d)
      XCTAssertEqual(plan.outputs.count,4)
      for (c,v) in [Float(0.125),0.25,0.5,0.25].enumerated() {
        XCTAssertEqual(plan.outputs[c].document.layers[0].nativeMode?.value(component:0,index:0),depth.quantize(v))
      }
      XCTAssertEqual(plan.outputs[3].document.name,d.name+"_Mask 日本語")
    }
  }
  func testRetainedFloatSpotGrayOnlyWinsForAnUnchangedDensity()throws {
    var d=try fixture(.rgb,.f32)
    let original:Float=0.1
    var gray=try Surface(width:4,height:1,depth:.f32,fill:Pixel(original,original,original))
    gray.setPixel(x:1,y:0,Pixel(0.7,0.7,0.7))
    var density=try gray.mappedStoredSamples{p in let v=1-p.r;return Pixel(v,v,v)}
    density.setPixel(x:1,y:0,Pixel(0.5,0.5,0.5))
    var spot=AlphaChannel(name:"Owned spot",pixels:density,spot:.init(color:Pixel(0,1,1),solidity:0.5));spot.psdSpotGray=gray;d.alphaChannels=[spot]
    let plane=try XCTUnwrap(ChannelSeparation.prepare(d).outputs.last?.document.layers[0].nativeMode)
    XCTAssertEqual(plane.rawWord(component:0,index:0),original.bitPattern)
    XCTAssertEqual(plane.rawWord(component:0,index:1),Float(0.5).bitPattern)
    XCTAssertEqual(d.alphaChannels?.first,spot)
  }
  func testDuotonePrintingPlatesAndStandaloneAlphaHaveNumericGrayOutputs()throws {
    let ink=try InkPlane(width:3,height:1,bytes:Data([0,128,255]))
    var duo=try CraftDocument(width:3,height:1).replacingInkMode(.duotone(.init(gray:ink,settings:.init())))
    duo.alphaChannels=[.init(name:"Mask",pixels:try Surface(width:3,height:1,fill:.white))]
    let gray=try ChannelSeparation.prepare(duo);XCTAssertEqual(gray.outputs.count,2)
    XCTAssertEqual(try gray.outputs[0].document.layers[0].nativeMode?.planes[0],Data([0,128,255]))
    let multi=try CraftDocument(width:3,height:1).replacingInkMode(.multichannel(.init(plates:[.init(name:"Cyan",color:Pixel(0,1,1),samples:ink),.init(name:"Magenta",color:Pixel(1,0,1),samples:ink)])))
    let plates=try ChannelSeparation.prepare(multi);XCTAssertEqual(plates.outputs.map(\.channel.kind),[.plate,.plate])
    for result in plates.outputs{XCTAssertEqual(try result.document.layers[0].nativeMode?.planes[0],Data([255,127,0]))}
    var standalone=try CraftDocument(width:3,height:1);standalone.layers=[];standalone.activeLayerID=nil;standalone.channelOnly=true
    standalone.alphaChannels=[.init(name:"One",pixels:try Surface(width:3,height:1,fill:.white)),.init(name:"Two",pixels:try Surface(width:3,height:1,fill:.black))]
    let result=try ChannelSeparation.prepare(standalone);XCTAssertEqual(result.outputs.count,2)
    XCTAssertEqual(result.outputs.map(\.channel.kind),[.alpha,.alpha]);XCTAssertEqual(result.outputs[0].document.layers[0].nativeMode?.value(component:0,index:0),1)
  }
  func testMaximumSparseGeometryAtEveryDepthAndCMYKHasNoNewPixelCap()throws {
    for mode in [DocumentColorMode.rgb,.grayscale,.cmyk] {for depth in mode.depths {
      var d=try fixture(mode,depth,width:300_000,height:300_000)
      d.alphaChannels=[.init(name:"Mask",pixels:try Surface(width:d.width,height:d.height,depth:depth,fill:Pixel(0.25,0.25,0.25)))]
      let source=d,plan=try ChannelSeparation.prepare(d)
      XCTAssertEqual(plan.outputs.count,mode.componentCount+1);XCTAssertEqual(d,source)
      for result in plan.outputs {
        let output=result.document,n=try XCTUnwrap(output.layers[0].nativeMode)
        XCTAssertTrue(n.requiresPagedArchive);XCTAssertTrue(n.isOpaque);XCTAssertLessThan(n.estimatedBytes,2_000_000)
        XCTAssertEqual(output.width,300_000);XCTAssertEqual(output.height,300_000)
        XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(output)),output)
      }
    }}
  }
  func testIdentityResolutionSelectionAndProfilesSurviveNativePersistence()throws {
    var d=try fixture(.grayscale,.u16);d.resolution=144
    d.selection = .init(x:1,y:0,width:2,height:1)
    d.alphaChannels=[.init(name:"Saved",pixels:try Surface(width:4,height:1,depth:.u16,fill:.white))]
    let profile=try XCTUnwrap(d.layers[0].nativeMode?.profile),plan=try ChannelSeparation.prepare(d)
    XCTAssertEqual(Set(plan.outputs.map{$0.document.id}).count,2)
    for result in plan.outputs {
      let output=result.document
      XCTAssertNotEqual(output.id,d.id);XCTAssertNotEqual(output.layers[0].id,d.layers[0].id)
      XCTAssertEqual(output.resolution,144);XCTAssertEqual(output.selection,d.selection)
      XCTAssertEqual(output.modeDescriptor?.profile,profile)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(output)),output)
      var session=EditorSession(document:output)
      try session.execute(.modeComponents(.init(layerID:output.layers[0].id,components:[0],operation:.fill(0.25,1))))
      XCTAssertEqual(session.undoStack.count,1);try session.undo();XCTAssertEqual(session.document,output)
    }
  }
  func testUnflattenedTransparentQuickMaskAndSingleChannelReject()throws {
    let good=try fixture();var variants=[CraftDocument]()
    var d=good;d.layers.append(.init(name:"Extra",content:.raster(try Surface(width:4,height:1))));variants.append(d)
    d=good;d.layers[0].opacity=0.5;variants.append(d)
    d=good;d.layers[0].nativeMode=try d.layers[0].nativeMode?.replacingOpacity(with:Surface(width:4,height:1,fill:Pixel(0.5,0.5,0.5)));variants.append(d)
    d=good;d.quickMask = .init(name:"Quick Mask",pixels:try Surface(width:4,height:1,fill:.white));variants.append(d)
    variants.append(try fixture(.grayscale))
    for d in variants{XCTAssertNotNil(ChannelSeparation.unavailableReason(d));XCTAssertThrowsError(try ChannelSeparation.prepare(d))}
    XCTAssertNil(ChannelSeparation.unavailableReason(good))
  }
  func testCancelledPreparationHasNoPublishableResult()async throws {
    let d=try fixture();let work=Task.detached{withUnsafeCurrentTask{$0?.cancel()};return try ChannelSeparation.prepare(d)}
    do{_ = try await work.value;XCTFail("Cancelled split returned outputs")}catch is CancellationError{}
  }
}
