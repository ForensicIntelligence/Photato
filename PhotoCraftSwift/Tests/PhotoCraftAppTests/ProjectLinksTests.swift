import Foundation
import XCTest

@testable import PhotoCraft

final class ProjectLinksTests: XCTestCase {
  func testBundledConfigurationPointsToPhotatoSource() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("scripts/ProjectLinks.json"))
    let links = try JSONDecoder().decode(ProjectLinks.self, from: data)
    XCTAssertEqual(links.repositoryURL?.absoluteString, "https://github.com/ForensicIntelligence/Photato")
    let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(Set(metadata.keys), ["repositoryURL"])
  }

  func testLegacyFundingMetadataIsIgnored() throws {
    let links = try JSONDecoder().decode(
      ProjectLinks.self,
      from: Data(#"{"repositoryURL":null,"donationURL":"https://example.org/donate","tipProductIDs":["legacy.tip"]}"#.utf8))
    XCTAssertNil(links.repositoryURL)
    XCTAssertEqual(links, try JSONDecoder().decode(ProjectLinks.self, from: Data("{}".utf8)))
  }

  func testConfiguredRepositoryRequiresSafeHTTPSURL() throws {
    let links = try ProjectLinks(repositoryURL: "https://example.org/source")
    XCTAssertEqual(links.repositoryURL?.path, "/source")
    for value in [
      "javascript:alert(1)", "file:///tmp/source", "http://example.org", "https:///",
      "https://name:secret@example.org", "not a URL",
    ] {
      XCTAssertThrowsError(try ProjectLinks(repositoryURL: value), value)
    }
  }
}
