import AppKit
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class ShapedTextTests:XCTestCase {
  func sample(_ mode:TextGeometry.Mode)->TextContent {
    var t=TextContent(text:"Native curved type");t.typography=TextTypography();t.typography?.defaultStyle.size=24
    var g=TextGeometry();g.mode=mode;g.width=200;g.height=120;g.fit=true
    if mode == .warp{g.warp.style = .arc;g.warp.bend=45}
    if mode == .path{g.path=VectorPath(components:[.init(knots:[.init(.init(10,100),outgoing:.init(70,0)),.init(.init(250,100),incoming:.init(180,0))])])}
    if mode == .inside{g.path=VectorPath(components:[.init(knots:[.init(.init(0,0)),.init(.init(200,0)),.init(.init(160,120)),.init(.init(40,120))],closed:true)])}
    t.typography?.geometry=g;return t
  }
  func doc(_ text:TextContent,depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:400,height:300,depth:depth);d.layers=[Layer(name:"Type",content:.text(text))];d.activeLayerID=d.layers[0].id;return d
  }
  func testAllMajorLayoutsRenderAndPreserveNativeSource()throws {
    for mode in TextGeometry.Mode.allCases {
      let text=sample(mode),d=try doc(text),m=try NativeTextLayout.metrics(text,dpi:72),surface=try NativeTextLayout.render(text,document:d)
      XCTAssertEqual(surface.width,m.width);XCTAssertEqual(surface.height,m.height)
      let ink=(0..<surface.height).reduce(0){a,y in a+(0..<surface.width).filter{surface.pixel(x:$0,y:y).a>0.1}.count}
      XCTAssertGreaterThan(ink,30,mode.rawValue)
      if let directory=ProcessInfo.processInfo.environment["PHOTATO_SHAPED_OUTPUT"]{let image=try RasterIO.displayImage(surface),context=try XCTUnwrap(CGContext(data:nil,width:surface.width,height:surface.height,bitsPerComponent:8,bytesPerRow:surface.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue));context.setFillColor(NSColor.white.cgColor);context.fill(CGRect(x:0,y:0,width:surface.width,height:surface.height));context.draw(image,in:CGRect(x:0,y:0,width:surface.width,height:surface.height));let bitmap=NSBitmapImageRep(cgImage:try XCTUnwrap(context.makeImage()));try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:directory).appendingPathComponent("layout-\(mode.rawValue).png"))}
      XCTAssertEqual(d.minimumArchiveVersion,35);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))
    }
  }
  func testWarpIdentityAndHighDepthRendering()throws {
    var text=sample(.warp);text.typography?.geometry?.warp.bend=0
    var plain=text;plain.typography?.geometry=nil
    let d=try doc(text)
    XCTAssertEqual(try NativeTextLayout.render(text,document:d),try NativeTextLayout.render(plain,document:d))
    text.typography?.geometry?.warp.bend=60
    for style in WarpStyle.allCases where style != .none && style != .custom{text.typography?.geometry?.warp.style=style;XCTAssertGreaterThan(try NativeTextLayout.outline(text,dpi:72).boundingBoxOfPath.width,1)}
    for depth in [PixelDepth.u8,.u16,.f32]{let d=try doc(text,depth:depth);XCTAssertEqual(try NativeTextLayout.render(text,document:d).depth,depth)}
  }
  func testIntervalsFittingAndActualCurveGeometry()throws {
    var text=sample(.circle);text.typography?.geometry?.fit=false;text.typography?.defaultStyle.size=100
    XCTAssertTrue(try NativeTextLayout.metrics(text,dpi:72).overset)
    text.typography?.geometry?.fit=true
    XCTAssertFalse(try NativeTextLayout.metrics(text,dpi:72).overset)
    let initial=try NativeTextLayout.outline(text,dpi:72).boundingBoxOfPath
    text.typography?.geometry?.end=0.5
    let half=try NativeTextLayout.outline(text,dpi:72).boundingBoxOfPath
    XCTAssertLessThan(half.width,initial.width)
    text.typography?.geometry?.end=0;XCTAssertThrowsError(try text.validate())
    text=sample(.block);text.text=String(repeating:"Words ",count:80);text.typography?.geometry?.fit=false
    XCTAssertTrue(try NativeTextLayout.metrics(text,dpi:72).overset)
    text.typography?.geometry?.fit=true;XCTAssertFalse(try NativeTextLayout.metrics(text,dpi:72).overset)
  }
  func testChangingTypeKeepsLogicalAnchorAndMaskWithUndo()throws {
    var old=sample(.warp);old.typography?.geometry=nil
    var d=try doc(old);d.layers[0].affine = .translation(80,90) * .rotation(12)
    d.layers[0].mask=try Surface(width:100,height:100,fill:.white)
    let before=d.layers[0],next=sample(.warp),a=try NativeTextLayout.metrics(old,dpi:72).origin,b=try NativeTextLayout.metrics(next,dpi:72).origin
    var session=EditorSession(document:d);try session.execute(ShapedTextLayout.replacement(before,content:next,document:d))
    let after=session.document.layers[0],p=before.coordinateTransform.point(-a.x,-a.y),q=after.coordinateTransform.point(-b.x,-b.y)
    XCTAssertEqual(p.x,q.x,accuracy:1e-8);XCTAssertEqual(p.y,q.y,accuracy:1e-8)
    XCTAssertEqual(after.maskCoordinateTransform.tx,before.maskCoordinateTransform.tx,accuracy:1e-8)
    try session.undo();XCTAssertEqual(session.document,d)
  }
}
