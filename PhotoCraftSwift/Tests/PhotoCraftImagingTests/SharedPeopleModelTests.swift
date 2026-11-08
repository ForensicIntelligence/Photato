import Foundation
import XCTest
@testable import PhotoCraftImaging

final class SharedPeopleModelTests: XCTestCase {
  func testConcurrentOwnersShareOneProvider() async {
    let pool = BundledPeopleFeaturePool()
    let url = URL(fileURLWithPath: "/owned-fixture/PeopleParts.mlmodelc")
    let providers = await withTaskGroup(of: CoreMLPeopleFeaturesDetector.self) { group in
      for _ in 0..<128 { group.addTask { pool.provider(for: url) } }
      var values: [CoreMLPeopleFeaturesDetector] = []
      for await value in group { values.append(value) }
      return values
    }
    XCTAssertEqual(providers.count, 128)
    XCTAssertEqual(Set(providers.map { ObjectIdentifier($0) }).count, 1)
    XCTAssertTrue(pool.provider(for: url) === providers[0])
  }

  func testPoolDoesNotRetainProviderAfterLastOwnerLeaves() {
    let pool = BundledPeopleFeaturePool()
    let url = URL(fileURLWithPath: "/owned-fixture/PeopleParts.mlmodelc")
    weak var released: CoreMLPeopleFeaturesDetector?
    func retainThenRelease() {
      let first = pool.provider(for: url)
      let second = pool.provider(for: url)
      released = first
      XCTAssertTrue(first === second)
      XCTAssertNotNil(released)
    }
    retainThenRelease()
    XCTAssertNil(released)
    let replacement = pool.provider(for: url)
    XCTAssertTrue(pool.provider(for: url) === replacement)
  }

  func testDifferentModelResourcesNeverShareProvider() {
    let pool = BundledPeopleFeaturePool()
    let first = pool.provider(for: URL(fileURLWithPath: "/owned-fixture/PeopleParts.mlmodelc"))
    let secondURL = URL(fileURLWithPath: "/other-fixture/PeopleParts.mlmodelc")
    let second = pool.provider(for: secondURL)
    XCTAssertFalse(first === second)
    XCTAssertTrue(pool.provider(for: secondURL) === second)
  }
}
