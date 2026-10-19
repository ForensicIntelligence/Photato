import Foundation
import XCTest

@testable import PhotoCraft

final class ProjectLinksTests: XCTestCase {
  func testBundledConfigurationMatchesLocalConsumableFixture() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let links = try JSONDecoder().decode(
      ProjectLinks.self,
      from: Data(contentsOf: root.appendingPathComponent("scripts/ProjectLinks.json")))
    struct Fixture: Decodable {
      struct Product: Decodable {
        let productID: String
        let type: String
      }
      let products: [Product]
    }
    let fixture = try JSONDecoder().decode(
      Fixture.self,
      from: Data(
        contentsOf: root.appendingPathComponent("Tests/StoreKitHost/DevelopmentTips.storekit")))
    XCTAssertFalse(links.tipProductIDs.isEmpty)
    XCTAssertEqual(links.tipProductIDs, fixture.products.map(\.productID))
    XCTAssertTrue(fixture.products.allSatisfy { $0.type == "Consumable" })
  }

  func testLegacyDonationDestinationIsIgnored() throws {
    let links = try JSONDecoder().decode(
      ProjectLinks.self,
      from: Data(#"{"repositoryURL":null,"donationURL":"https://example.org/donate"}"#.utf8))
    XCTAssertNil(links.repositoryURL)
    XCTAssertEqual(links.tipProductIDs, [])
    XCTAssertEqual(
      try JSONDecoder().decode(ProjectLinks.self, from: Data("{}".utf8)).tipProductIDs, [])
  }
  func testConfiguredRepositoryAndConsumableIDs() throws {
    let links = try ProjectLinks(
      repositoryURL: "https://example.org/source",
      tipProductIDs: ["org.example.tip.small", "org.example.tip.large"])
    XCTAssertEqual(links.repositoryURL?.path, "/source")
    XCTAssertEqual(links.tipProductIDs.count, 2)
    for value in [
      "javascript:alert(1)", "file:///tmp/payment", "http://example.org", "https:///",
      "https://name:secret@example.org", "not a URL",
    ] {
      XCTAssertThrowsError(try ProjectLinks(repositoryURL: value), value)
      XCTAssertThrowsError(try ProjectLinks(tipProductIDs: [value]), value)
    }
    for ids in [[""], ["tip", "tip"], [String(repeating: "x", count: 256)], ["tip😀"]] {
      XCTAssertThrowsError(try ProjectLinks(tipProductIDs: ids))
    }
  }
}
