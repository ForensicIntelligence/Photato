import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class VideoTransitionRendererTests:XCTestCase {
  func fixture(depth:PixelDepth = .u8,alpha:Bool=false)throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3,depth:depth)
    var a=Layer(name:"Red",content:.fill(Pixel(1,0,0,alpha ? 0.25:1))),b=Layer(name:"Blue",content:.fill(Pixel(0,0,1,alpha ? 0.75:1)))
    a.videoTiming = .init(startTime:0,duration:1);b.videoTiming = .init(startTime:1,duration:1)
    d.layers=[a,b];d.activeLayerID=b.id;d.videoTimeline = .init(frameRate:4,durationFrames:8)
    try Command.video(.transition(.set(.init(layerID:b.id,previousLayerID:a.id,kind:.crossFade,duration:1)))).apply(to:&d)
    return d
  }
  func sample(_ surface:Surface,depth:PixelDepth,x:Int=1,y:Int=1)->Pixel{depth == .f32 ? surface.linearPixel(x:x,y:y):surface.pixel(x:x,y:y)}
  func testCrossFadeUsesPremultipliedCoverageWithoutAlphaDipInEveryDepth()throws {
    for depth in [PixelDepth.u8,.u16,.f32] {for alpha in [false,true] {
      let d=try fixture(depth:depth,alpha:alpha)
      for frame in 2...6 {
        // Solid-fill source alpha is stored at the document depth before mixing.
        let scale:Float = depth == .u8 ? 255:depth == .u16 ? 65535:1
        let first:Float = !alpha ? 1:depth == .f32 ? 0.25:(0.25*scale).rounded()/scale
        let last:Float = !alpha ? 1:depth == .f32 ? 0.75:(0.75*scale).rounded()/scale
        let t=Float(frame-2)/4,a=first*(1-t),b=last*t
        let p=sample(try Renderer.composite(d.videoDocument(at:frame)),depth:depth)
        XCTAssertEqual(p.a,a+b,accuracy:0.00001);XCTAssertEqual(p.r,a/(a+b),accuracy:0.00001);XCTAssertEqual(p.b,b/(a+b),accuracy:0.00001);XCTAssertEqual(p.g,0,accuracy:0.00001)
      }
    }}
  }
  func testMasksBackdropAndLaterLayersSurviveCrossfade()throws {
    var d=try fixture()
    var mask=try Surface(width:4,height:3,fill:.white);for y in 0..<3{mask.setPixel(x:1,y:y,.black)};d.layers[0].mask=mask
    d.layers.insert(Layer(name:"Background",content:.fill(Pixel(0.2,0.2,0.2))),at:0)
    try d.selectVideoFrame(4)
    let p=try Renderer.composite(d)
    XCTAssertEqual(p.pixel(x:0,y:1).r,0.5,accuracy:0.00001);XCTAssertEqual(p.pixel(x:0,y:1).b,0.5,accuracy:0.00001)
    XCTAssertEqual(p.pixel(x:1,y:1).r,0.1,accuracy:0.001);XCTAssertEqual(p.pixel(x:1,y:1).b,0.6,accuracy:0.001);XCTAssertEqual(p.pixel(x:1,y:1).a,1)
    var overlay=Layer(name:"Overlay",content:.fill(Pixel(0,1,0)));overlay.opacity=0.5;d.layers.append(overlay)
    let q=try Renderer.composite(d).pixel(x:0,y:1);XCTAssertEqual(q.r,0.25,accuracy:0.00001);XCTAssertEqual(q.g,0.5,accuracy:0.00001);XCTAssertEqual(q.b,0.25,accuracy:0.00001)
  }
  func testFadesKeepSourceEditableAndColorCoverage()throws {
    for depth in [PixelDepth.u8,.u16,.f32] {for kind in [VideoTransitionKind.fade,.black,.white,.color] {
      var d=try fixture(depth:depth);d.videoTimeline!.transitions=nil;d.layers.removeLast();let id=d.layers[0].id,content=d.layers[0].content;d.activeLayerID=id
      let color=kind == .color ? Pixel(0,1,0):nil
      try Command.video(.transition(.set(.init(layerID:id,kind:kind,duration:1,color:color)))).apply(to:&d)
      let frame=try d.videoDocument(at:2),p=sample(try Renderer.composite(frame),depth:depth)
      XCTAssertEqual(p.a,kind == .fade ? 0.5:1,accuracy:0.00001)
      XCTAssertEqual(p.r,kind == .fade || kind == .white ? 1:0.5,accuracy:0.00001)
      XCTAssertEqual(p.g,kind == .white || kind == .color ? 0.5:0,accuracy:0.00001)
      XCTAssertEqual(p.b,kind == .white ? 0.5:0,accuracy:0.00001)
      XCTAssertEqual(d.layers[0].content,content)
    }}
  }
  func testSequentialGroupsAndSimultaneousTrackTransitions()throws {
    var d=try fixture();let ids=d.layers.map(\.id)
    try Command.video(.arrange(.group("Video Group",ids))).apply(to:&d)
    var overlay=Layer(name:"Title",content:.fill(Pixel(0,1,0)));overlay.videoTiming = .init(startTime:0,duration:2)
    d.layers.append(overlay)
    try Command.video(.transition(.set(.init(layerID:overlay.id,kind:.fade,duration:2)))).apply(to:&d)
    let frame=try d.videoDocument(at:4),p=try Renderer.composite(frame).pixel(x:0,y:0)
    XCTAssertEqual(p.r,0.25,accuracy:0.00001);XCTAssertEqual(p.g,0.5,accuracy:0.00001);XCTAssertEqual(p.b,0.25,accuracy:0.00001);XCTAssertEqual(p.a,1)
    let region=try Renderer.composite(frame,region:.init(x:0,y:0,width:2,height:1));XCTAssertEqual(region.pixel(x:0,y:0),p);XCTAssertEqual(region.pixel(x:3,y:2),.clear)
  }
  func testRetainedVideoHandlesAndEdgeHoldAreRendered()throws {
    var d=try fixture();let frames=try [Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1),Pixel(1,1,1)].map{try Surface(width:4,height:3,fill:$0)}
    var clip=VideoClip(frames:frames,frameRate:2);clip.sourceIn=1;clip.sourceOut=3;clip.startTime=0
    d.layers[0].videoTiming=nil;d.layers[0].video=clip
    try d.selectVideoFrame(5)
    let p=try Renderer.composite(d).pixel(x:0,y:0)
    XCTAssertEqual(p.r,0.25,accuracy:0.00001);XCTAssertEqual(p.g,0.25,accuracy:0.00001);XCTAssertEqual(p.b,1,accuracy:0.00001)
  }
  func testStyledParentRetainsTransitionsInsideItsGroup()throws {
    var d=try fixture();let clips=d.layers.map(\.id)
    try Command.video(.arrange(.group("Track",clips))).apply(to:&d)
    var effect=LayerEffect(.colorOverlay);effect.color=Pixel(0,1,0);effect.opacity=0.5
    d.layers[d.layers.count-1].style=LayerStyle(effects:[effect])
    try d.selectVideoFrame(4)
    let p=try Renderer.composite(d).pixel(x:0,y:0)
    XCTAssertEqual(p.r,0.25,accuracy:0.00001);XCTAssertEqual(p.g,0.5,accuracy:0.00001);XCTAssertEqual(p.b,0.25,accuracy:0.00001)
  }

}
