import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ClassicFusedGradientWorkflowTests:XCTestCase {
  struct Ref:Decodable {var name:String;var positions:[Int];var midpoints:[Int];var colors:[[Int]];var smoothness:Int;var expected:[[Int]]}
  func reference()throws->Ref {
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try JSONDecoder().decode([Ref].self,from:Data(contentsOf:root.appendingPathComponent("PhotoCraftCoreTests/Fixtures/classic-fused486.json")))[0]
  }
  @MainActor func testNativeAndHTTPUseIndependentClassicSamplesWithUndoAndStaleGuard()async throws {
    let ref=try reference();var original=try CraftDocument(width:4097,height:1,depth:.u16)
    var pixels=try Surface(width:4097,height:1,depth:.u16)
    for x in 0...4096{let v=Float(x)/4096;pixels.setPixel(x:x,y:0,Pixel(v,v,v))}
    original.layers[0].content = .raster(pixels)
    var layer=Layer(name:"Gradient Map",content:.adjustment(.gradientMap(.init())))
    layer.mask=try Surface(width:4097,height:1,depth:.u16,fill:.white);original.layers.append(layer);original.activeLayerID=layer.id
    let gradient=GradientDefinition(name:ref.name,colors:ref.positions.indices.map{i in
      let c=ref.colors[i];return .init(Float(ref.positions[i])/4096,.rgb(Pixel(Float(c[0])/32768,Float(c[1])/32768,Float(c[2])/32768)),midpoint:Float(ref.midpoints[i])/100)
    },smoothness:Float(ref.smoothness)/4096,method:.classic)
    let settings=GradientMapAdjustment(gradient:gradient),native=EditorStore(document:original,actions:ActionLibrary())
    defer{native.renderTask?.cancel();native.geometryTask?.cancel()}
    native.setGradientMap(layer.id,settings)
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      document.store.session=EditorSession(document:original);try service.share(document)
      let p:[String:Any]=["operation":"replace","layerID":layer.id.uuidString,"kind":"gradientMap","settings":AdjustmentBrushAPI.settings(.gradientMap(settings))]
      let status=try await helper.edit(service,document,"adjustmentBrush.edit",p)
      XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,native.document);XCTAssertEqual(document.store.session.undoStack.count,1)
      let surface=try Renderer.composite(document.store.document);var differences=0
      for x in 0...4096 {
        let v=surface.pixel(x:x,y:0)
        for(c,f)in[v.r,v.g,v.b].enumerated(){if Int((f*32768).rounded()) != ref.expected[x][c]{differences+=1}}
      }
      XCTAssertEqual(differences,0)
      let edited=document.store.document
      let stale=try await helper.edit(service,document,"adjustmentBrush.edit",p,revision:"stale")
      XCTAssertEqual(stale,409);XCTAssertEqual(document.store.document,edited)
      await document.store.undo();XCTAssertEqual(document.store.document,original)
      await document.store.redo();XCTAssertEqual(document.store.document,edited)
    }
  }
}
