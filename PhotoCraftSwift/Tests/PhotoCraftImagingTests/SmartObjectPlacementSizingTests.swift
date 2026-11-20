import CoreFoundation
import CoreGraphics
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class SmartObjectPlacementSizingTests: XCTestCase {
  func testPhysicalRasterSizingAndPostSizingFit() throws {
    let source = try CraftDocument(width: 40, height: 20)
    let bytes = try NativeArchive.encodeChunked(source)
    var parent = try CraftDocument(width: 120, height: 90)
    parent.resolution = 288
    let legacy = try SmartObjectIO.placed(data: bytes, fileName: "Source.photato", in: parent)
    XCTAssertEqual(legacy.coordinateTransform, Transform2D(tx: 40, ty: 35))

    let unbounded = try SmartObjectIO.placed(data: bytes, fileName: "Source.photato", in: parent,
      fit: false, sizing: .physical)
    XCTAssertEqual(unbounded.coordinateTransform, Transform2D(a: 4, d: 4, tx: -20, ty: 5))
    let fitted = try SmartObjectIO.placed(data: bytes, fileName: "Source.photato", in: parent, sizing: .physical)
    XCTAssertEqual(fitted.coordinateTransform, Transform2D(a: 3, d: 3, tx: 0, ty: 15))
    XCTAssertEqual(fitted.smartObject?.data, bytes)
    XCTAssertEqual(fitted.smartObject?.resolution, 72)
    XCTAssertEqual(fitted.smartObject?.width, 40)

    var higherDensity = source
    higherDensity.resolution = 300
    parent.resolution = 72
    let scaled = try SmartObjectIO.placed(document: higherDensity, data: NativeArchive.encodeChunked(higherDensity),
      fileName: "Source.photato", in: parent, sizing: .physical)
    XCTAssertEqual(scaled.coordinateTransform, Transform2D(a: 0.24, d: 0.24, tx: 55, ty: 42))
    XCTAssertEqual(scaled.smartObject?.resolution, 300)

    parent.resolution = .nan
    XCTAssertThrowsError(try SmartObjectIO.placed(data: bytes, fileName: "Source.photato",
      in: parent, sizing: .physical))
  }

  func testPhysicalPDFPageGeometryUsesExactPointsAcrossTwoCacheDensities() throws {
    let output = NSMutableData()
    let consumer = try XCTUnwrap(CGDataConsumer(data: output as CFMutableData))
    var box = CGRect(x: 0, y: 0, width: 45.25, height: 33.75)
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    context.setFillColor(red: 0.3, green: 0.6, blue: 0.2, alpha: 1)
    context.fill(box)
    context.endPDFPage()
    context.closePDF()
    let bytes = output as Data

    var parent = try CraftDocument(width: 96, height: 72)
    parent.resolution = 144
    for density in [72.0, 144.0] {
      var options = PDFImportSettings()
      options.crop = .media
      options.resolution = density
      let layer = try PDFSmartObjectIO.placed(bytes, fileName: "Page.pdf", in: parent,
        settings: options, sizing: .physical)
      let object = try XCTUnwrap(layer.smartObject)
      let farEdge = layer.coordinateTransform.point(Double(object.width), Double(object.height))
      XCTAssertEqual(farEdge.x - Double(layer.x), 90.5, accuracy: 1e-10)
      XCTAssertEqual(farEdge.y - Double(layer.y), 67.5, accuracy: 1e-10)
      XCTAssertEqual(layer.x, 2)
      XCTAssertEqual(layer.y, 2)
      XCTAssertEqual(object.resolution, density)
      XCTAssertEqual(object.data, bytes)
    }
  }
}
