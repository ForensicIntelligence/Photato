import Foundation
import CryptoKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PcraftLinkedCaptureTests:XCTestCase {
  struct Source:Decodable {let id:String,original_blob:String,file_name:String,source_sha256:String,bytes:Int}
  struct Entry:Decodable {let file:String,original:String,depth:String,tag:String,signature:String,block_blob:String,sources:[Source],layers:Int}
  var folder:URL {Bundle.module.url(forResource:"Fixtures",withExtension:nil)!.appendingPathComponent("PcraftLinkedOriginals")}
  func entries()throws->[Entry]{try JSONDecoder().decode([Entry].self,from:Data(contentsOf:folder.appendingPathComponent("cases.json")))}
  func file(_ name:String)throws->Data {try Data(contentsOf:folder.appendingPathComponent(name))}
  func testNativeDecoderRecoversExactOriginalsAndInheritedCacheWords()throws {
    var words=Data(),cases=[[String:Any]]();let old=PcraftSmartImportTests(),originalCases=try old.entries()
    for entry in try entries(){
      let input=try file(entry.file),project=try PcraftProject.read(input)
      var wrapper=try CraftDocument(width:1,height:1);wrapper.sourceMetadata=["psdGlobal_"+entry.tag:try XCTUnwrap(project.blobs[entry.block_blob])]
      let files=try PSDSmartObjects.files(wrapper),originalInput=try old.file(entry.original),original=try PcraftProject.read(originalInput)
      for source in entry.sources{
        let file=try XCTUnwrap(files[source.id]);XCTAssertNil(file.link);XCTAssertEqual(file.name,source.file_name)
        XCTAssertEqual(file.data,original.blobs[source.original_blob]);XCTAssertEqual(file.data.count,source.bytes)
        XCTAssertEqual(SHA256.hash(data:file.data).map{String(format:"%02x",$0)}.joined(),source.source_sha256)
        XCTAssertNoThrow(try SmartObjectIO.decode(file.data,fileName:file.name))
      }
      let doc=try PcraftImport.read(originalInput),layer=try XCTUnwrap(doc.layers.first),spec=try XCTUnwrap(originalCases.first{$0.file==entry.original})
      let projected=try layer.originalSmartAppearanceLayer() ?? SmartFilterEngine.renderedLayer(layer,in:doc)
      let samples=try old.samples(projected,entry:spec);XCTAssertEqual(samples,try old.expected(spec))
      let offset=words.count
      for value in samples{var word=value.littleEndian;withUnsafeBytes(of:&word){words.append(contentsOf:$0)}}
      cases.append(["file":entry.file,"offset":offset,"bytes":words.count-offset]);XCTAssertEqual(try file(entry.file),input)
    }
    XCTAssertEqual(cases.count,9)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{
      let folder=URL(fileURLWithPath:path)
      try words.write(to:folder.appendingPathComponent("pcraft-linked-original-caches.f32le"))
      try JSONSerialization.data(withJSONObject:cases,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("pcraft-linked-original-cases.json"))
    }
  }
}
