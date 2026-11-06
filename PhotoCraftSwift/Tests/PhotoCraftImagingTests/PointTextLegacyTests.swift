import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PointTextLegacyTests:XCTestCase {
  static let kinds=["point-left","box-center","box-right","point-vertical-left","box-vertical-right"]
  static func text(_ kind:String)->TextContent {
    var text=TextContent(text:"Alpha\nBeta"),type=TextTypography()
    type.defaultStyle.font="HelveticaNeue";type.defaultStyle.size=16
    if kind.hasPrefix("box") {type.kind = .paragraph;text.layoutWidth=120;text.layoutHeight=110}
    if kind.contains("vertical"){type.orientation = .vertical}
    if kind.hasSuffix("center"){type.defaultParagraph.alignment = .center}
    if kind.hasSuffix("right"){type.defaultParagraph.alignment = .right}
    var first=type.defaultStyle;first.color=Pixel(0.7,0.1,0.2,0.8);first.underline=true;first.tracking=45
    var second=type.defaultStyle;second.color=Pixel(0.1,0.2,0.8,1);second.size=20;second.leading=24
    type.runs=[.init(length:6,style:first,paragraph:type.defaultParagraph),.init(length:4,style:second,paragraph:type.defaultParagraph)]
    text.typography=type;return text
  }
  static func words(_ surface:Surface)->Data {
    var result=Data();result.reserveCapacity(surface.width*surface.height*16)
    for y in 0..<surface.height {for x in 0..<surface.width {
      let pixel=surface.pixel(x:x,y:y)
      for value in [pixel.r,pixel.g,pixel.b,pixel.a] {var word=value.bitPattern.littleEndian;withUnsafeBytes(of:&word){result.append(contentsOf:$0)}}
    }}
    return result
  }
  func testCaptureOwnedLegacyOutputs()throws {
    let root=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"].map{URL(fileURLWithPath:$0)}
    var cases:[[String:Any]]=[]
    for (index,depth)in PixelDepth.allCases.enumerated(){for kind in Self.kinds {
      let text=Self.text(kind),document=try CraftDocument(width:180,height:140,depth:depth)
      let metrics=try NativeTextLayout.metrics(text,dpi:72),surface=try NativeTextLayout.render(text,document:document)
      XCTAssertEqual(surface.width,metrics.width);XCTAssertEqual(surface.height,metrics.height)
      XCTAssertLessThan(surface.width*surface.height,1_000_000)
      let file="legacy-\(index)-\(kind).rgba-f32le"
      if let root {try Self.words(surface).write(to:root.appendingPathComponent(file))}
      cases.append(["kind":kind,"depthIndex":index,"width":surface.width,"height":surface.height,"origin":[metrics.origin.x,metrics.origin.y],"firstBaseline":metrics.firstBaseline,"file":file])
    }}
    XCTAssertEqual(cases.count,15)
    if let root {try JSONSerialization.data(withJSONObject:["cases":cases,"dpi":72,"samples":"Surface.pixel RGBA Float32 little-endian words; output regression only, not Photoshop proof"],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("legacy-manifest.json"))}
  }
}
