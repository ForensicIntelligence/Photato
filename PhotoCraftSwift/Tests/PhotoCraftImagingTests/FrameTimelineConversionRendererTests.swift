import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class FrameTimelineConversionRendererTests:XCTestCase {
  func fixture(depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3,depth:depth)
    d.layers[0].content = .raster(try Surface(width:2,height:2,depth:depth,fill:Pixel(1,0,0)))
    var animation=FrameAnimation(layers:d.layers)
    animation.frames[0].delay=0.25
    var moved=AnimationFrame(layers:d.layers,delay:0.5);moved.layers[0].x=2;moved.layers[0].y=1;moved.layers[0].opacity=0.5
    var hidden=AnimationFrame(layers:d.layers,delay:0.25);hidden.layers[0].visible=false
    animation.frames += [moved,hidden];d.animation=animation;return d
  }
  func testEveryFrameMatchesOriginalCompositionAtAllDepths()throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      let original=try fixture(depth:depth),converted=try original.convertingFrameAnimation(frameRate:8)
      for frame in 0..<8 {
        let index=frame<2 ? 0:frame<6 ? 1:2
        XCTAssertEqual(try Renderer.composite(converted.videoDocument(at:frame)),try Renderer.composite(original.animationDocument(at:original.animation!.frames[index].id)))
      }
      XCTAssertEqual(converted.layers[0].content,original.layers[0].content)
    }
  }
  func testMasksGroupPlacementAffineAndStyleStayEquivalent()throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      var d=try CraftDocument(width:8,height:6,depth:depth)
      d.layers[0].content = .raster(try Surface(width:2,height:2,depth:depth,fill:Pixel(1,0,0)))
      d.layers[0].mask=try Surface(width:8,height:6,depth:depth,fill:Pixel(0.5,0.5,0.5))
      try Command.newGroup(.init(name:"Group"),children:[d.layers[0].id]).apply(to:&d)
      var a=FrameAnimation(layers:d.layers);a.frames[0].delay=0.25
      var next=AnimationFrame(layers:d.layers,delay:0.25)
      next.layers[0].affine=Transform2D(a:0,b:1,c:-1,d:0,tx:2,ty:0)
      next.layers[0].x=2;next.layers[next.layers.count-1].x=1
      var effect=LayerEffect(.colorOverlay);effect.color=Pixel(0,0,1)
      next.layers[0].style=LayerStyle(effects:[effect]);a.frames.append(next);d.animation=a
      let converted=try d.convertingFrameAnimation(frameRate:8)
      for frame in 0..<4 {
        let expected=try Renderer.composite(d.animationDocument(at:a.frames[frame/2].id))
        XCTAssertEqual(try Renderer.composite(converted.videoDocument(at:frame)),expected)
      }
      XCTAssertEqual(converted.layers.map(\.content),d.layers.map(\.content))
      XCTAssertEqual(converted.layers.map(\.mask),d.layers.map(\.mask))
    }
  }
  func testIndependentPNGFixtures()throws {
    let converted=try fixture().convertingFrameAnimation(frameRate:8)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_CONVERSION_OUTPUT_DIR"] {
      for frame in 0..<8 {
        let surface=try Renderer.composite(converted.videoDocument(at:frame))
        try ClipboardRenderer.imageData(surface,type:.png).write(to:URL(fileURLWithPath:root).appendingPathComponent("converted-\(frame).png"))
      }
    }
  }
}
