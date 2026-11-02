import XCTest
@testable import PhotoCraftCore

final class ExtendedShapeModelTests:XCTestCase {
  func exactPath()->VectorPath {.init(components:[.init(knots:[.init(.init(-3.125,7.25),outgoing:.init(5.123456789012345,22)),.init(.init(30.75,9.5),incoming:.init(17,-4.5))],closed:false)])}
  func testLegacyDefaultsRemainAbsentAndRequireOnlyArchive33()throws {
    let definition=ShapeDefinition(geometry:.init(width:20,height:10));let data=try JSONEncoder().encode(definition),text=String(decoding:data,as:UTF8.self)
    for key in ["pathOverride","pathReferenceTransform","opacity","pathContours","widthRelativeDashes","inversionBounds","paintFrame"]{XCTAssertFalse(text.contains("\"\(key)\""),key)}
    XCTAssertEqual(try JSONDecoder().decode(ShapeDefinition.self,from:data),definition);XCTAssertFalse(definition.requiresExtendedShapeArchive)
    var doc=try CraftDocument(width:64,height:64);try Command.shape(.create("Legacy",definition,.identity)).apply(to:&doc);XCTAssertEqual(doc.minimumArchiveVersion,33)
  }
  func testExactPathBitsOpenContoursReferenceTransformAndStrokeBounds()throws {
    let path=exactPath();var component=try ShapeDefinition.regularPathComponent(path)
    XCTAssertEqual(try component.path(),path);XCTAssertTrue(component.requiresExtendedShapeArchive)
    component.transform = .translation(7.25,-2.5);XCTAssertEqual(try component.path(),path.transformed(component.transform))
    var definition=ShapeDefinition(geometry:.init());definition.components=[component];definition.stroke.paint = .init();definition.stroke.pathContours=true;definition.stroke.widthRelativeDashes=true;definition.stroke.width=5;definition.stroke.miterLimit=100;definition.stroke.dash=[0,2];definition.stroke.opacity=0.35
    try definition.validate();XCTAssertLessThan(try definition.renderBounds().width,100)
    definition.stroke.dash=[0,0];XCTAssertThrowsError(try definition.validate());definition.stroke.dash=[];definition.stroke.opacity=1.01;XCTAssertThrowsError(try definition.validate())
    var line=ShapeGeometry(kind:.line,width:0,height:0);line.lineWeight=0;XCTAssertNoThrow(try line.path())
  }
  func testCacheNative68HistoryGeometryAndMaskPlacementPreserveSource()throws {
    var doc=try CraftDocument(width:64,height:64);var definition=ShapeDefinition(geometry:.init(width:20,height:12));definition.stroke.pathContours=true
    let pixels=try Surface(width:4,height:5,fill:Pixel(0.2,0.4,0.6,0.5));var shape=try ShapeContent(definition:definition)
    shape.importedAppearance = .init(definition:definition,pixels:pixels,x:9,y:7,vectorRecord:Data([1,2,3]));shape.width=4;shape.height=5
    var layer=Layer(name:"Cached",content:.shape(shape));layer.x=9;layer.y=7;doc.layers=[layer];doc.activeLayerID=layer.id;try doc.validate()
    XCTAssertEqual(doc.minimumArchiveVersion,68);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(doc)),doc)
    var session=EditorSession(document:doc);try session.execute(.shape(.configure(layer.id,definition)));XCTAssertTrue(session.document==doc);XCTAssertTrue(session.undoStack.isEmpty);try session.execute(.mask(layer.id,Surface(width:4,height:5,fill:.white)));let before=session.document,origin=try before.layers[0].shapeTransform(),mask=before.layers[0].maskCoordinateTransform
    definition.components[0].geometry.width=25;try session.execute(.shape(.configure(layer.id,definition)))
    XCTAssertNil(session.document.layers[0].shape?.importedAppearance);XCTAssertEqual(try session.document.layers[0].shapeTransform(),origin);XCTAssertEqual(session.document.layers[0].maskCoordinateTransform,mask)
    try session.undo();XCTAssertEqual(session.document,before);try session.redo();XCTAssertNil(session.document.layers[0].shape?.importedAppearance)
    let replacement=try before.layers[0].replacingShapePath(exactPath(),canvas:.init(x:0,y:0,width:64,height:64));XCTAssertEqual(try replacement.path(),exactPath());XCTAssertEqual(replacement.components[0].geometry.kind,.custom)
  }
  func testInvertedEmptyPathsAndInvalidFramesAreBounded()throws {
    var definition=ShapeDefinition(geometry:.init());definition.components=[try ShapeDefinition.regularPathComponent(VectorPath())];definition.inverted=true;definition.inversionBounds = .init(x:0,y:0,width:64,height:32)
    try definition.validate();XCTAssertEqual(try definition.renderBounds(),definition.inversionBounds)
    XCTAssertThrowsError(try ShapeDefinition.inversionFrame(canvas:.init(x:Int.max,y:0,width:10,height:10),transform:.identity))
    definition.inversionBounds = .init(x:0,y:0,width:32768,height:32768);XCTAssertThrowsError(try definition.validate())
  }
  func testRetainedShapeContentRequires68AndCountsAppearanceMemory()throws {
    var doc=try CraftDocument(width:64,height:64);var definition=ShapeDefinition(geometry:.init(width:20,height:12));definition.stroke.opacity=0.5
    var shape=try ShapeContent(definition:definition);let bounds=try definition.renderBounds();var cache=try Surface(width:bounds.width,height:bounds.height,fill:.white);cache.setPixel(x:0,y:0,Pixel(1,0,0));shape.importedAppearance = .init(definition:definition,pixels:cache,x:bounds.x,y:bounds.y)
    var layer=Layer(name:"Retained",content:.shape(shape));let payload=AnimationLayerPayload(layer);XCTAssertGreaterThan(payload.rasterBytes,0);XCTAssertGreaterThan(payload.metadataBytes,256)
    let key=VideoKeyframe(property:.content,time:0,layer:layer);layer.content = .raster(try Surface(width:64,height:64));layer.videoKeyframes=[key];doc.layers=[layer];doc.activeLayerID=layer.id
    XCTAssertEqual(doc.minimumArchiveVersion,68)
  }
}
