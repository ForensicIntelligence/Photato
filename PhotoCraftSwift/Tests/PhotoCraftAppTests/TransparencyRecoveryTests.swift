import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TransparencyRecoveryTests: XCTestCase {
  private func fixture(depth: PixelDepth = .u8, textured: Bool) throws -> CraftDocument {
    var doc = try CraftDocument(width:72,height:56,depth:depth)
    var image = try Surface(width:72,height:56,depth:depth), backing = image
    let foreground = SIMD3<Float>(0.82, 0.51, 0.16)
    let object = IntRect(x:17,y:12,width:38,height:32)
    for y in 0..<doc.height {
      for x in 0..<doc.width {
        let texture: Float = textured && (x/3+y/4) % 2 == 0 ? 0.23 : 0
        let background = SIMD3<Float>(0.13 + Float(x)/500 + texture,0.31 + Float(y)/550,0.61 - texture)
        let alpha: Float = object.contains(x, y) ? (x >= 37 ? 1 : 0.35) : 0
        let composite = foreground * alpha + background * (1 - alpha)
        if depth == .f32 {
          backing.setLinearPixel(x:x,y:y,Pixel(background.x,background.y,background.z))
          image.setLinearPixel(x:x,y:y,Pixel(composite.x,composite.y,composite.z))
        } else {
          backing.setPixel(x:x,y:y,Pixel(background.x,background.y,background.z))
          image.setPixel(x:x,y:y,Pixel(composite.x,composite.y,composite.z))
        }
      }
    }
    doc.layers[0].content = .raster(image)
    var plate = doc.layers[0]
    plate.id = UUID(); plate.name = "Background Photo"; plate.content = .raster(backing); plate.visible = false
    doc.layers.insert(plate,at:0)
    doc.selection = .init(x:15,y:10,width:42,height:36)
    return doc
  }

  func testSmoothRecoveryRetainsOpaqueCoverageAndCorrectsColorAtAllDepths() throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      let document = try fixture(depth: depth, textured: false)
      let input = try SelectionRefinementInput.prepare(document, layerID: document.layers[1].id)
      var settings = SelectionRefinement()
      XCTAssertNil(try SelectionRefinement.decodeJSON(Data("{}".utf8)).transparency)
      settings.transparency = .init(); settings.decontaminate = true
      let prepare = try input.edit(settings:settings,output:.newLayer)
      XCTAssertEqual(prepare.mask.byte(at: 22*72+4), 0)
      XCTAssertEqual(Float(prepare.mask.byte(at:22*72+28))/255,0.35,accuracy:0.014)
      XCTAssertEqual(prepare.mask.byte(at:22*72+43),255)
      let corrected = try XCTUnwrap(prepare.corrected)
      let sample = depth == .f32 ? corrected.linearPixel(x:28,y:22) : corrected.pixel(x:28,y:22)
      XCTAssertEqual(sample.r,0.82,accuracy:0.023)
      XCTAssertEqual(sample.g,0.51,accuracy:0.023)
      XCTAssertEqual(sample.b,0.16,accuracy:0.023)
      let erased = SelectionRefinementStroke(tool:.eraseRefinement,size:6,hardness:1,points:[[28.5,22.5]])
      let protected = try input.edit(settings:settings,output:.newLayer,strokes:[erased])
      XCTAssertEqual(protected.mask.byte(at:22*72+28),255)
      let opaque = try XCTUnwrap(protected.corrected)
      XCTAssertEqual(opaque.pixel(x:28,y:22),input.guide.pixel(x:28,y:22))
    }
  }

  @MainActor func testTexturedBackgroundRequiresAlignedLayerAndNativeAndHTTPExportEqual() async throws {
    let source = try fixture(textured:true)
    let subject = source.layers[1].id, background = source.layers[0].id
    let input = try SelectionRefinementInput.prepare(source,layerID:subject)
    var settings = SelectionRefinement()
    settings.transparency = .init(); settings.decontaminate = true
    XCTAssertThrowsError(try input.refined(settings:settings))
    settings.transparency = .init(backgroundLayerID:background)
    let test = SelectMaskWorkflowTests(), helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service, shared in
      let store = shared.store
      store.session = EditorSession(document:source)
      store.beginSelectMask()
      let workspace = try XCTUnwrap(store.selectMaskDraft)
      await test.ready(workspace)
      var state = workspace.state
      state.settings = settings
      state.output = .newLayerWithMask
      workspace.change(state)
      await test.ready(workspace)
      XCTAssertNil(workspace.error)
      let preview = try XCTUnwrap(workspace.refinedMask)
      XCTAssertEqual(Float(preview.byte(at:22*72+28))/255,0.35,accuracy:0.014)
      store.commitSelectMask()
      await workspace.commitTask?.value
      XCTAssertNil(workspace.error)
      XCTAssertEqual(store.document.layers[0],source.layers[0])
      XCTAssertFalse(store.document.layers[1].visible)
      let pixels = try RasterIO.encoded(store.document)
      XCTAssertEqual(store.session.undoStack.count,1)
      await store.undo()
      XCTAssertEqual(store.document,source)
      try service.share(shared)
      let invalid = try await helper.edit(service,shared,"selection.refine",["layerID":subject.uuidString,
        "settings":["transparency":["misspelled":background.uuidString]]])
      XCTAssertEqual(invalid,400)
      let status = try await helper.edit(service,shared,"selection.refine",["layerID":subject.uuidString,
        "output":"newLayerWithMask","settings":["decontaminate":true,
          "transparency":["backgroundLayerID":background.uuidString]]])
      XCTAssertEqual(status,200)
      XCTAssertEqual(try RasterIO.encoded(store.document),pixels)
      XCTAssertEqual(store.session.undoStack.count,1)
      let restored = try NativeArchive.decode(NativeArchive.encodeChunked(store.document))
      XCTAssertEqual(try RasterIO.encoded(restored),pixels)
      await store.undo()
      XCTAssertEqual(store.document,source)
    }
  }
}
