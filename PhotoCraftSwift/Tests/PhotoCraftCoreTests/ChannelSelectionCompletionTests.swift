import XCTest
@testable import PhotoCraftCore

final class ChannelSelectionCompletionTests:XCTestCase {
  let a:[UInt8]=[0,32,64,96,128,160,192,224,255,255,128,64,0,192,255,128]
  let b:[UInt8]=[255,224,192,160,128,96,64,32,0,255,64,128,0,192,128,255]
  let expected:[[UInt8]]=[
    [255,228,208,196,192,196,208,228,255,255,160,160,0,239,255,255],
    [0,4,16,36,64,100,144,196,255,0,96,32,0,47,127,0],
    [0,28,48,60,64,60,48,28,0,255,32,32,0,145,128,128]]
  func mask(_ row:[UInt8])throws->SelectionMask {try .init(width:16,height:4,bytes:Array(repeating:row,count:4).flatMap{$0})}
  func testEveryEightBitPairUsesCoverageAlgebra() {
    for x in 0...255 {for y in 0...255 {
      let p=Int((Double(x)*Double(y)/255).rounded())
      XCTAssertEqual(ChannelSelectionMath.byte(UInt8(x),UInt8(y),mode:.add),UInt8(x+y-p))
      XCTAssertEqual(ChannelSelectionMath.byte(UInt8(x),UInt8(y),mode:.subtract),UInt8(x-p))
      XCTAssertEqual(ChannelSelectionMath.byte(UInt8(x),UInt8(y),mode:.intersect),UInt8(p))
    }}
  }
  func testAllLoadCombinationsMatchFixedPhotoshopSamplesAtEachDocumentDepth()throws {
    for depth in PixelDepth.allCases {for (i,mode) in [SelectionMode.add,.subtract,.intersect].enumerated() {
      var d=try CraftDocument(width:16,height:4,depth:depth);d.setCoverageSelection(try mask(a))
      let channel=AlphaChannel(name:"B",pixels:try AlphaChannel.coverage(mask(b),width:16,height:4,depth:depth));d.alphaChannels=[channel]
      let layers=d.layers
      try Command.channel(.load(.alpha(channel.id),mode,false)).apply(to:&d)
      XCTAssertEqual(try d.coverageSelection()?.denseBytes(),try mask(expected[i]).denseBytes())
      XCTAssertEqual(d.layers,layers);XCTAssertEqual(d.alphaChannels,[channel])
    }}
  }
  func testAllSaveCombinationsMatchFixedPhotoshopSamples()throws {
    for (i,mode) in [SelectionMode.add,.subtract,.intersect].enumerated() {
      var d=try CraftDocument(width:16,height:4);d.setCoverageSelection(try mask(b))
      let channel=AlphaChannel(name:"A",pixels:try AlphaChannel.coverage(mask(a),width:16,height:4,depth:.u8));d.alphaChannels=[channel]
      try Command.channel(.saveSelection(channel.id,nil,mode)).apply(to:&d)
      XCTAssertEqual(try d.channel(.alpha(channel.id)).selection().denseBytes(),try mask(expected[i]).denseBytes())
      XCTAssertEqual(try d.coverageSelection()?.denseBytes(),try mask(b).denseBytes())
    }
  }
  func testPagedMaximumCanvasUsesSameSamplesWithoutDenseAllocation()throws {
    let w=300000,h=300000
    let a=try SelectionMask(coverage:Surface(width:w,height:h,depth:.u8,fill:Pixel(64.0/255,64.0/255,64.0/255)))
    let b=try SelectionMask(coverage:Surface(width:w,height:h,depth:.u8,fill:Pixel(128.0/255,128.0/255,128.0/255)))
    for mode in [SelectionMode.add,.subtract,.intersect] {
      let result=try ChannelSelectionMath.selection(b,combining:a,mode:mode)
      XCTAssertTrue(result.isPaged);XCTAssertLessThan(result.allocatedBytes,100000)
      XCTAssertEqual(result.byte(at:w*h-1),ChannelSelectionMath.byte(64,128,mode:mode))
    }
  }
  func testInvertedLoadHistoryAndTemporaryMaskHaveNoPixelSideEffects()throws {
    for depth in PixelDepth.allCases {
      var d=try CraftDocument(width:16,height:4,depth:depth);d.setCoverageSelection(try mask(a))
      let channel=AlphaChannel(name:"A",pixels:try AlphaChannel.coverage(mask(a),width:16,height:4,depth:depth));d.alphaChannels=[channel]
      var session=EditorSession(document:d)
      try session.execute(.channel(.load(.alpha(channel.id),.replace,true)))
      XCTAssertEqual(try session.document.coverageSelection()?.denseBytes(),a.map{255-$0}+a.map{255-$0}+a.map{255-$0}+a.map{255-$0})
      try session.undo();XCTAssertEqual(session.document,d)
      var options=ChannelDisplayOptions();options.indicates = .selectedAreas;options.opacity=0.37
      try session.execute(.channel(.quickMask(true,options)))
      let before=session.document
      options.color=Pixel(0,1,0);options.opacity=0;options.indicates = .maskedAreas
      try session.execute(.channel(.options(.quickMask,options)))
      XCTAssertEqual(session.document.quickMask?.pixels,before.quickMask?.pixels)
      try session.execute(.channel(.quickMask(false,options)))
      XCTAssertEqual(try session.document.coverageSelection()?.denseBytes(),try mask(a).denseBytes());XCTAssertEqual(session.document.layers,d.layers)
    }
  }
}
