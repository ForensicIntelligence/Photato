import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class GroupDisclosureImagingTests: XCTestCase {
  func testAllDepthPixelsStayExactAndPSDStoresMixedGroupOpenFlags() throws {
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width: 4, height: 3, depth: depth)
      let base = Layer(
        name: "Base", content: .raster(try Surface(width: 4, height: 3, depth: depth, fill: .white))
      )
      var inner = Layer(name: "Inner", content: .group(.init()))
      let outer = Layer(name: "Outer", content: .group(.init()))
      inner.parentID = outer.id
      var child = Layer(
        name: "Child",
        content: .raster(
          try Surface(width: 4, height: 3, depth: depth, fill: Pixel(0.2, 0.4, 0.6, 0.5))))
      child.parentID = inner.id
      doc.layers = [base, child, inner, outer]
      doc.activeLayerID = child.id
      let original = try Renderer.composite(doc)
      var session = EditorSession(document: doc)
      try session.setGroupExpansion([inner.id], expanded: false)
      XCTAssertEqual(try Renderer.composite(session.document), original)
      let back = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document))
      XCTAssertEqual(back.layers.filter(\.isGroup).map(\.name), ["Inner", "Outer"])
      XCTAssertEqual(back.layers.compactMap { $0.group?.expanded }, [false, true])
      // This checks PSD divider metadata, not a Photoshop-rendered oracle.
      try session.setGroupExpansion([inner.id, outer.id], expanded: false)
      XCTAssertEqual(try Renderer.composite(session.document), original)
      try session.setGroupExpansion([inner.id, outer.id], expanded: true)
      XCTAssertEqual(try Renderer.composite(session.document), original)
    }
  }
}
