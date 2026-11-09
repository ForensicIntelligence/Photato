import Foundation
import CryptoKit
import CoreGraphics
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class EditablePhotoBlendTests:XCTestCase {
  func testIndependentOpaquePSDHasIdenticalMemoryAndFileSamplesBeforeBlending() throws {
    let folder = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/PhotoBlend")
    let file = folder.appendingPathComponent("owned-focus-rgb8.psd")
    let record = try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("owned-focus-rgb8.json"))) as! [String:Any]
    let references = record["layers"] as! [[String:Any]]
    for (label,document) in [("memory",try PSDCodec.read(Data(contentsOf:file))),
      ("file",try PSDCodec.read(file)),("opening",try PreparedLocalDocument.read(file,format:.automatic).model)] {
      XCTAssertEqual(document.layers.count,2)
      for reference in references {
        let layer = try XCTUnwrap(document.layers.first { $0.name == reference["name"] as? String })
        guard case .raster(let pixels) = layer.content else { return XCTFail() }
        let planes = reference["planes"] as! [String:[String:Any]]
        for component in [-1,0,1,2] {
          var bytes = Data()
          for y in 0..<64 { for x in 0..<96 {
            let p = pixels.pixel(x:x,y:y),value = component == -1 ? p.a:component == 0 ? p.r:component == 1 ? p.g:p.b
            bytes.append(UInt8((unit(value)*255).rounded()))
          } }
          XCTAssertEqual(SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined(),
            planes[String(component)]?["sha256"] as? String,"\(label) / \(layer.name) / \(component)")
        }
      }
      var settings = PhotoBlendSettings();settings.method = .stack;settings.fillTransparentAreas = false
      let blended = try PhotoBlend.prepare(document,layerIDs:Set(document.layers.map(\.id)),settings:settings).result
      let composite = try Renderer.composite(blended)
      XCTAssertTrue(try composite.isOpaque(),label)
      let image = try ColorManagement.displayImage(composite,in:document)
      let display = try XCTUnwrap(image.dataProvider?.data) as Data
      XCTAssertEqual(image.alphaInfo,.last);XCTAssertEqual(display.count,96*64*4)
      // The fixture intentionally contains coloured checker pixels. Prove
      // those are opaque image content rather than the transparency backdrop.
      XCTAssertTrue(stride(from:3,to:display.count,by:4).allSatisfy { display[$0] == 255 },label)
    }
  }
  func testOpaqueResultStructureAtAllDepthsMethodsAndOptions() throws {
    // Photoshop2026 saved owned RGB8 Stack references: seamless/noFill has
    // two visible masked sources; Fill adds one visible "Owned Far (merged)".
    // Other depths/methods below are native contract regressions, not PS pixels.
    for (_,source,settings) in try PhotoBlendLegacyCaptureTests().programs() {
      let original = source,ids = Set(source.layers.map(\.id))
      let edit = try PhotoBlend.prepare(source,layerIDs:ids,settings:settings),result = edit.result
      XCTAssertEqual(result.layers.count,settings.fillTransparentAreas ? 3:2)
      XCTAssertTrue(result.layers.allSatisfy(\.visible))
      for i in source.layers.indices {
        XCTAssertEqual(result.layers[i].id,source.layers[i].id)
        XCTAssertEqual(result.layers[i].name,source.layers[i].name)
        XCTAssertEqual(result.layers[i].coordinateTransform,source.layers[i].coordinateTransform)
        XCTAssertNotNil(result.layers[i].mask)
        if !settings.seamlessTones { XCTAssertEqual(result.layers[i].content,source.layers[i].content) }
      }
      if settings.fillTransparentAreas {
        XCTAssertEqual(result.layers.last?.name,"Photo 2 (merged)")
        XCTAssertEqual(edit.selectedLayerIDs,Set(result.activeLayerID.map { [$0] } ?? []))
      } else { XCTAssertEqual(edit.selectedLayerIDs,ids);XCTAssertEqual(result.activeLayerID,source.activeLayerID) }
      XCTAssertEqual(source,original)
    }
  }
  func testSourceGeometryAlphaOutsideCanvasAndUnselectedLayersSurvive() throws {
    for transformed in [false,true] {
      var source = try PhotoBlendWorkflowTests().fixture(.f32)
      let group = Layer(name:"Photos",content:.group(.init()))
      source.layers[0].x = -8
      if transformed { source.layers[0].affine = Transform2D(a:1,b:0.05,c:0.15,d:1) }
      for i in source.layers.indices { source.layers[i].parentID = group.id }
      let ids = Set(source.layers.map(\.id))
      let unrelated = Layer(name:"Untouched",content:.raster(try Surface(width:1,height:1,fill:.clear)))
      source.layers.append(group);source.layers.append(unrelated)
      source.selection = IntRect(x:5,y:6,width:10,height:12)
      var settings = PhotoBlendSettings();settings.fillTransparentAreas = false
      let result = try PhotoBlend.prepare(source,layerIDs:ids,settings:settings).result
      XCTAssertEqual(result.layers[2],group);XCTAssertEqual(result.layers.last,unrelated)
      XCTAssertEqual(result.selection,source.selection)
      for id in ids {
        let a = try XCTUnwrap(source.layers.first { $0.id == id }),b = try XCTUnwrap(result.layers.first { $0.id == id })
        XCTAssertEqual(b.coordinateTransform,a.coordinateTransform);XCTAssertEqual(b.parentID,a.parentID)
        guard case .raster(let old) = a.content,case .raster(let changed) = b.content else { return XCTFail() }
        XCTAssertEqual(changed.width,old.width);XCTAssertEqual(changed.height,old.height)
        for y in 0..<old.height { for x in 0..<old.width {
          let p = old.linearPixel(x:x,y:y),q = changed.linearPixel(x:x,y:y)
          XCTAssertEqual(q.a.bitPattern,p.a.bitPattern)
          let point = a.coordinateTransform.point(Double(x)+0.5,Double(y)+0.5)
          if point.x < 0 || point.y < 0 || point.x >= Double(source.width) || point.y >= Double(source.height) {
            XCTAssertTrue(q.hasSameBits(as:p),"Off-canvas source pixels changed")
          }
        } }
      }
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
    }
  }
  func testRGBAndGrayNativePlanesRemainAuthoritative() throws {
    for mode:DocumentColorMode in [.rgb,.grayscale] { for depth in PixelDepth.allCases {
      let source = try PhotoBlendWorkflowTests().fixture(depth).convertingMode(.init(mode:mode,depth:depth))
      for fill in [false,true] {
        var settings = PhotoBlendSettings();settings.fillTransparentAreas = fill
        let edit = try PhotoBlend.prepare(source,layerIDs:Set(source.layers.map(\.id)),settings:settings)
        try edit.result.validate()
        for layer in edit.result.layers {
          let native = try XCTUnwrap(layer.nativeMode)
          guard case .raster(let surface) = layer.content else { return XCTFail() }
          XCTAssertEqual(surface,try native.surface());XCTAssertEqual(native.mode,mode)
        }
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(edit.result)),edit.result)
      }
    } }
  }
  func testEditableResultAtLayerCapacityDoesNotNeedAnExtraLayer() throws {
    var source = try PhotoBlendWorkflowTests().fixture()
    let ids = Set(source.layers.map(\.id)),pixel = try Surface(width:1,height:1)
    for i in source.layers.count..<LayerLimits.maximumLayers {
      source.layers.append(Layer(name:"Unchanged \(i)",content:.raster(pixel)))
    }
    var settings = PhotoBlendSettings();settings.fillTransparentAreas = false
    let edit = try PhotoBlend.prepare(source,layerIDs:ids,settings:settings)
    XCTAssertEqual(edit.result.layers.count,LayerLimits.maximumLayers)
    XCTAssertEqual(Array(edit.result.layers.dropFirst(2)),Array(source.layers.dropFirst(2)))
    settings.fillTransparentAreas = true
    XCTAssertThrowsError(try PhotoBlend.prepare(source,layerIDs:ids,settings:settings))
    XCTAssertEqual(source.layers.count,LayerLimits.maximumLayers)
  }
  func testPartialAlphaFillRetainsIsolationWithoutDoublingAlpha() throws {
    var source = try PhotoBlendWorkflowTests().fixture(.f32,focus:true)
    for i in source.layers.indices {
      source.layers[i].content = .raster(try Surface(width:64,height:40,depth:.f32,
        fill:Pixel(1.4,-0.1,0.8,0.5),colorEncoding:.linearRGB))
    }
    let edit = try PhotoBlend.prepare(source,layerIDs:Set(source.layers.map(\.id)),settings:.init())
    XCTAssertEqual(edit.result.layers.count,3);XCTAssertFalse(edit.result.layers[0].visible);XCTAssertFalse(edit.result.layers[1].visible)
    XCTAssertEqual(try Renderer.composite(edit.result).linearPixel(x:20,y:20).a,0.5)
  }
  func testCorrectedSourcesMasksPersistenceAndUndoRedo() throws {
    let source = try PhotoBlendWorkflowTests().fixture(.u16)
    var settings = PhotoBlendSettings();settings.fillTransparentAreas = false
    let edit = try PhotoBlend.prepare(source,layerIDs:Set(source.layers.map(\.id)),settings:settings)
    var session = EditorSession(document:source);try session.execute(.photoBlend(edit))
    XCTAssertNotEqual(session.document.layers[0].content,source.layers[0].content)
    let opened = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document))
    XCTAssertEqual(opened.layers.map(\.name),source.layers.map(\.name));XCTAssertTrue(opened.layers.allSatisfy { $0.visible && $0.mask != nil })
    XCTAssertEqual(try Renderer.composite(opened),try Renderer.composite(edit.result))
    try session.undo();XCTAssertEqual(session.document,source);try session.redo();XCTAssertEqual(session.document,edit.result)
  }
  @MainActor func testPhotomergeHTTPPublishesEditableNamedSourceLayers() async throws {
    let helper = AutomationTests(),merge = PhotomergeWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,original in
      let (second,base) = try merge.setup(service,original)
      defer { merge.cleanup(service.controller,except:original) }
      service.setDocumentTransfersEnabled(true)
      var parameters = base;parameters["settings"] = ["projection":"reposition","blendImages":true,"fillTransparentAreas":false]
      let sources = [original.store.document,second.store.document]
      let response = try await helper.request(service,path:"/v1/documents/\(service.shares[0].id)/commands",
        body:["command":"document.photomerge","revision":service.revision(original.store),"parameters":parameters])
      XCTAssertEqual(response.0.statusCode,201,String(decoding:response.1,as:UTF8.self))
      let created = try XCTUnwrap(service.shares.last?.document)
      XCTAssertFalse(created === original);XCTAssertFalse(created === second)
      XCTAssertEqual(created.store.document.layers.map(\.name),sources.map(\.name))
      XCTAssertTrue(created.store.document.layers.allSatisfy { $0.visible && $0.mask != nil })
      let expected = try Photomerge.prepare(sources,settings:merge.settings(blend:true),name:"API Panorama").document
      XCTAssertEqual(try Renderer.composite(created.store.document),try Renderer.composite(expected))
      XCTAssertEqual(original.store.document,sources[0]);XCTAssertEqual(second.store.document,sources[1])
    }
  }
}
