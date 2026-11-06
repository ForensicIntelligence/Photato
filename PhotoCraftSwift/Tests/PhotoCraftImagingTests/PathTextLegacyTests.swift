import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PathTextLegacyTests:XCTestCase {
  static let modes:[TextGeometry.Mode] = [.path,.circle,.arch,.bow]
  static func text(_ mode:TextGeometry.Mode,_ variant:Int)->TextContent {
    var text=TextContent(text:"Office A\u{301} native"),type=TextTypography(),g=TextGeometry()
    type.defaultStyle.font="HelveticaNeue";type.defaultStyle.size=24
    g.mode=mode;g.width=220;g.height=120;g.fit=variant != 0
    if mode == .path {g.path=VectorPath(components:[.init(knots:[.init(.init(10,100),outgoing:.init(70,0)),.init(.init(280,100),incoming:.init(200,0))])])}
    if variant == 2 {g.start=0.1;g.end=0.8;g.reverse=true;g.offset=7;type.defaultParagraph.alignment = .center}
    type.geometry=g;text.typography=type;return text
  }
  static func words(_ s:Surface)->Data {PointTextLegacyTests.words(s)}
  func testCaptureOwnedPathRenderOutputs()throws {
    let root=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"].map{URL(fileURLWithPath:$0)}
    var cases:[[String:Any]]=[]
    for (index,depth)in PixelDepth.allCases.enumerated(){for mode in Self.modes{for variant in 0..<3 {
      let text=Self.text(mode,variant),doc=try CraftDocument(width:400,height:300,depth:depth)
      let m=try NativeTextLayout.metrics(text,dpi:72),surface=try NativeTextLayout.render(text,document:doc)
      XCTAssertEqual(surface.width,m.width);XCTAssertEqual(surface.height,m.height)
      let file="path-\(index)-\(mode.rawValue)-\(variant).rgba-f32le"
      if let root{try Self.words(surface).write(to:root.appendingPathComponent(file))}
      cases.append(["mode":mode.rawValue,"variant":variant,"depthIndex":index,"width":surface.width,"height":surface.height,"origin":[m.origin.x,m.origin.y],"baseline":m.firstBaseline,"overset":m.overset,"file":file])
    }}}
    XCTAssertEqual(cases.count,36)
    if let root{try JSONSerialization.data(withJSONObject:["cases":cases,"dpi":72,"provenance":"Owned generated text; unchanged438production renderer captured before439path preparation changes; regression baseline, not Adobe output. No font redistributed."],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("path-legacy-manifest.json"))}
  }
}
