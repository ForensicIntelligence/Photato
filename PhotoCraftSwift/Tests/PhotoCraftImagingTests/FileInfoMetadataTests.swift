import Foundation
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers
import XCTest
@testable import PhotoCraftImaging

final class FileInfoMetadataTests: XCTestCase {
  func folder() throws -> URL { try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("FileInfo") }
  func data(_ name: String) throws -> Data { try Data(contentsOf: folder().appendingPathComponent(name)) }
  func foreign() throws -> CraftDocument {
    var doc = try CraftDocument(width: 5, height: 3)
    let xml = """
      <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:probe="https://photato.example/metadata/"><dc:title><rdf:Alt><rdf:li xml:lang="x-default">Original</rdf:li><rdf:li xml:lang="fr">Titre français</rdf:li></rdf:Alt></dc:title><dc:creator><rdf:Seq><rdf:li>Smith, Jane</rdf:li><rdf:li>Second Author</rdf:li></rdf:Seq></dc:creator><probe:retained>OWNED &amp; ORIGINAL</probe:retained></rdf:Description></rdf:RDF></x:xmpmeta>
      """
    doc.sourceMetadata = ["imageIOXMP": Data(xml.utf8), "owned.private": Data([3, 1, 4])]
    return doc
  }
  func testOriginalRustFileInfoValuesAndEveryMetadataPayloadAcrossDepths() throws {
    let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: data("cases.json")) as? [[String: Any]])
    for item in cases {
      let depth = try XCTUnwrap(item["depth"] as? String), name = try XCTUnwrap(item["project"] as? String)
      let expected = try JSONDecoder().decode(FileInformation.self, from: JSONSerialization.data(withJSONObject: item["expected"]!))
      let document = try PcraftImport.read(data(name))
      XCTAssertEqual(try FileInfoMetadata.read(document), expected)
      XCTAssertEqual(document.sourceMetadata?["imageIOXMP"], try data("info-\(depth).xmp"))
      XCTAssertEqual(document.sourceMetadata?["pcraft.exif"], Data([0x49, 0x49, 42, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
      let resources = try PSDImageResources.blocks(XCTUnwrap(document.sourceMetadata?["psdResources"]))
      XCTAssertEqual(resources.first { $0.id == 4000 }?.data, Data([1, 2, 3, 4, 5]))
      XCTAssertEqual(resources.first { $0.id == 1058 }?.data, document.sourceMetadata?["pcraft.exif"])
      let globals = document.sourceMetadata?.filter { $0.key.hasPrefix("pcraft.psdGlobal.") }
      XCTAssertEqual(globals?.count, 1); XCTAssertEqual(globals?.values.first, Data([9, 7, 5]))
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(document)), document)
      XCTAssertEqual(try PcraftImport.read(data(name)), document)
    }
  }
  func testPatchPreservesUneditedAuthorsLocalizedAlternativesUnknownValuesAndPixels() throws {
    let before = try foreign(); var info = try FileInfoMetadata.read(before)
    XCTAssertEqual(info.author, "Smith, Jane; Second Author")
    info.description = "Oil & canvas <owned>"; info.keywords = ["with, comma", "café"]
    let after = try FileInfoMetadata.applying(info, fields: ["description", "keywords"], to: before)
    XCTAssertEqual(after.layers, before.layers); XCTAssertEqual(after.sourceMetadata?["owned.private"], before.sourceMetadata?["owned.private"])
    XCTAssertEqual(try FileInfoMetadata.read(after).author, info.author)
    let packet = try XCTUnwrap(FileInfoMetadata.packet(after)), text = String(decoding: packet, as: UTF8.self)
    XCTAssertTrue(text.contains("Titre français")); XCTAssertTrue(text.contains("OWNED &amp; ORIGINAL"))
    XCTAssertEqual(try FileInfoMetadata.read(after).keywords, info.keywords)
    XCTAssertEqual(try FileInfoMetadata.applying(info, fields: Set(FileInformation.fields), to: after), after)
  }
  func testAllEightFieldsThroughNativePSDPSBAndRasterFormatsAtEveryDepth() throws {
    for label in ["u8", "u16", "f32"] {
      let before = try PcraftImport.read(data("info-\(label).pcraft")); var info = try FileInfoMetadata.read(before)
      info.title = "Changed <title>"; info.author = "Edited Author; Second Author"; info.authorTitle = "Photographer"
      info.description = "Updated & preserved"; info.keywords = ["one", "two"]
      info.copyright = "Owned © 2026"; info.copyrightStatus = .copyrighted; info.copyrightUrl = "https://example.invalid/license"
      let edited = try FileInfoMetadata.applying(info, fields: Set(FileInformation.fields), to: before)
      XCTAssertEqual(edited.layers, before.layers)
      let native = try NativeArchive.decode(NativeArchive.encodeChunked(edited)); XCTAssertEqual(native, edited)
      for format in [PSDFileFormat.psd, .psb] {
        let bytes = try PSDCodec.writeRasterLayers(edited, format: format), restored = try PSDCodec.read(bytes)
        XCTAssertEqual(try FileInfoMetadata.read(restored), info)
        XCTAssertEqual(try PSDImageResources.blocks(restored.sourceMetadata!["psdResources"]!).first { $0.id == 4000 }?.data, Data([1, 2, 3, 4, 5]))
        if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
          let folder = URL(fileURLWithPath: path).appendingPathComponent("file-info"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          try bytes.write(to: folder.appendingPathComponent("\(label).\(format == .psb ? "psb" : "psd")"))
        }
      }
      for type in [UTType.png, .jpeg, .tiff] {
        let read = try RasterIO.read(RasterIO.encoded(edited, type: type))
        XCTAssertEqual(try FileInfoMetadata.read(read), info, "\(label) \(type.identifier)")
      }
    }
  }
  func testClearingDefaultLanguageKeepsOtherLanguagesAndCopyrightResourcesDoNotStayStale() throws {
    var before = try foreign(); before.sourceMetadata?["psdResources"] = PSDImageResources.block(1034, data: Data([1])) + PSDImageResources.block(1035, data: Data("old-url".utf8))
    var info = try FileInfoMetadata.read(before); info.title = ""; info.copyrightStatus = .publicDomain; info.copyrightUrl = "https://example.invalid/new"
    let edited = try FileInfoMetadata.applying(info, fields: ["title", "copyrightStatus", "copyrightUrl"], to: before)
    XCTAssertEqual(try FileInfoMetadata.read(edited).title, "")
    XCTAssertTrue(String(decoding: try XCTUnwrap(FileInfoMetadata.packet(edited)), as: UTF8.self).contains("Titre français"))
    let resources = try PSDImageResources.blocks(edited.sourceMetadata!["psdResources"]!)
    XCTAssertEqual(resources.first { $0.id == 1034 }?.data, Data([0])); XCTAssertFalse(resources.contains { $0.id == 1035 })
    info.copyrightStatus = .unknown
    let unknown = try FileInfoMetadata.applying(info, fields: ["copyrightStatus"], to: edited)
    XCTAssertEqual(try FileInfoMetadata.read(unknown).copyrightStatus, .unknown)
    XCTAssertFalse(try PSDImageResources.blocks(unknown.sourceMetadata!["psdResources"]!).contains { $0.id == 1034 })
  }
  func testInvalidFieldsPacketsAndTextRejectWithoutChangingOriginal() throws {
    let before = try foreign(), originalPacket = try FileInfoMetadata.packet(foreign()); var info = try FileInfoMetadata.read(before)
    XCTAssertThrowsError(try FileInfoMetadata.applying(info, fields: ["unknown"], to: before))
    info.title = "bad\0title"; XCTAssertThrowsError(try FileInfoMetadata.applying(info, fields: ["title"], to: before))
    info.title = String(repeating: "é", count: 40_000); XCTAssertThrowsError(try info.validate())
    info.title = ""; info.keywords = Array(repeating: "x", count: 257); XCTAssertThrowsError(try info.validate())
    var invalid = before; invalid.sourceMetadata?["imageIOXMP"] = Data("not xml".utf8)
    XCTAssertThrowsError(try FileInfoMetadata.read(invalid))
    XCTAssertEqual(try FileInfoMetadata.packet(before), originalPacket)
  }
  func testRepeatedIndependentEditsProduceIdenticalNativeMetadataBytes() throws {
    let original = try CraftDocument(width: 5, height: 3)
    var info = FileInformation(); info.title = "New document"; info.author = "Smith, Jane; Second Author"
    info.authorTitle = "Artist"; info.description = "Owned <work> & metadata"; info.keywords = ["one", "two"]
    info.copyright = "Owned © 2026"; info.copyrightStatus = .copyrighted; info.copyrightUrl = "https://example.invalid/rights"
    let fields = Set(FileInformation.fields), first = try FileInfoMetadata.applying(info, fields: fields, to: original)
    XCTAssertEqual(try FileInfoMetadata.read(first), info)
    for _ in 0..<30 {
      let edited = try FileInfoMetadata.applying(info, fields: fields, to: original)
      XCTAssertEqual(edited, first)
      XCTAssertEqual(try NativeArchive.encodeChunked(edited), try NativeArchive.encodeChunked(first))
    }
  }
  func testMalformedSourceMetadataRejectsWholeImport() throws {
    let input = try data("info-u8.pcraft"), helper = PcraftImportTests()
    for variant in 0..<5 {
      let project = try helper.source(input) { document in
        var metadata = document["metadata"] as! [String: Any]
        switch variant {
        case 0: metadata["unknown"] = true
        case 1: metadata["xmp"] = 42
        case 2: var rows = metadata["psd_resources"] as! [[Any]]; rows[0][0] = 65536; metadata["psd_resources"] = rows
        case 3: var rows = metadata["psd_global_blocks"] as! [[Any]]; rows[0][0] = "bad"; metadata["psd_global_blocks"] = rows
        default: var rows = metadata["psd_resources"] as! [[Any]]; rows[0][1] = String(repeating: "x", count: 256); metadata["psd_resources"] = rows
        }
        document["metadata"] = metadata
      }
      XCTAssertThrowsError(try helper.convert(project))
    }
    XCTAssertEqual(input, try data("info-u8.pcraft"))
  }
}
