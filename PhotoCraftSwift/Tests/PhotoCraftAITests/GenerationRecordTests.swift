import Foundation
import XCTest
@testable import PhotoCraftAI

final class GenerationRecordTests:XCTestCase {
  func fixture()throws->GenerationRecord {
    try GenerationRecord(requestID:UUID(uuidString:"00000000-0000-0000-0000-000000000001")!,
      sourceDocumentID:UUID(uuidString:"00000000-0000-0000-0000-000000000002")!,
      sourceRevision:UUID(uuidString:"00000000-0000-0000-0000-000000000003")!,
      initialPrompt:"Owned blue mountains",startedAt:Date(timeIntervalSince1970:1_800_000_000),
      acceptedAt:Date(timeIntervalSince1970:1_800_000_002),processing:.onDevice,
      resultStyle:"illustration",originalMediaType:"image/png",originalSHA256:String(repeating:"a",count:64),originalByteCount:4096)
  }
  func testBoundedRecordRoundTripDoesNotInventProviderFields()throws {
    let record=try fixture(),data=try record.encoded()
    XCTAssertEqual(try GenerationRecord.decode(data),record)
    XCTAssertEqual(try GenerationRecord.decode(data).encoded(),data)
    XCTAssertNil(record.modelIdentifier);XCTAssertNil(record.seed);XCTAssertNil(record.finalPrompt)
    XCTAssertFalse(record.isProviderAttestation)
    let object=try XCTUnwrap(JSONSerialization.jsonObject(with:data)as?[String:Any]);XCTAssertNil(object["seed"]);XCTAssertNil(object["finalPrompt"])
    XCTAssertEqual(object["initialPrompt"]as?String,"Owned blue mountains")
  }
  func testMalformedVersionPromptHashTypeAndBudgetsReject()throws {
    let data=try fixture().encoded(),object=try XCTUnwrap(JSONSerialization.jsonObject(with:data)as?[String:Any])
    for (key,value) in [("version",2 as Any),("initialPrompt","  changed  "as Any),("initialPrompt",String(repeating:"x",count:1001)as Any),("originalSHA256","not a hash"as Any),("originalMediaType","text/html"as Any),("originalByteCount",0 as Any),("originalByteCount",GenerationRecord.maximumOriginalBytes+1 as Any)] {
      var bad=object;bad[key]=value;XCTAssertThrowsError(try GenerationRecord.decode(JSONSerialization.data(withJSONObject:bad)))
    }
    XCTAssertThrowsError(try GenerationRecord.decode(Data(repeating:32,count:GenerationRecord.maximumRecordBytes+1)))
  }
}
