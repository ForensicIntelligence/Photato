import Foundation
import XCTest
@testable import PhotoCraftCore

final class LayerProtectionTests: XCTestCase {
  func testIndependentPermissionsAndFullFlag() throws {
    let alpha: LayerProtection = .transparency
    XCTAssertTrue(alpha.locksTransparency)
    XCTAssertFalse(alpha.locksImage)
    XCTAssertFalse(alpha.locksPosition)
    XCTAssertFalse(alpha.fullyLocks)
    XCTAssertTrue(LayerProtection.image.locksTransparency)
    XCTAssertTrue(LayerProtection.image.locksImage)
    XCTAssertFalse(LayerProtection.image.locksPosition)
    XCTAssertTrue(LayerProtection.position.locksPosition)
    XCTAssertFalse(LayerProtection.position.locksImage)
    XCTAssertTrue(LayerProtection.autoNest.preventsAutoNesting)
    XCTAssertFalse(LayerProtection.autoNest.locksPosition)
    for flags: LayerProtection in [.all, .fullyLocked] {
      XCTAssertTrue(flags.fullyLocks)
      XCTAssertTrue(flags.locksImage)
      XCTAssertTrue(flags.locksTransparency)
      XCTAssertTrue(flags.locksPosition)
      XCTAssertTrue(flags.preventsAutoNesting)
    }
    // Legacy Photato writes 7. It means three partial flags, not Photoshop All.
    XCTAssertFalse(LayerProtection(rawValue: 7).fullyLocks)
    XCTAssertFalse(LayerProtection.partial.fullyLocks)
  }

  func testObservedDialogTransitionsDifferFromShortcut() throws {
    let empty = LayerProtection()
    let image = try empty.setting(.image, enabled: true)
    XCTAssertEqual(image.rawValue, 3)
    XCTAssertEqual(try image.setting(.transparency, enabled: false), image)
    XCTAssertEqual(try image.setting(.image, enabled: false), .transparency)
    XCTAssertEqual(try LayerProtection.image.setting(.image, enabled: false), .transparency)
    XCTAssertEqual(try LayerProtection.all.setting(.all, enabled: false), .partial)
    let full = try LayerProtection.autoNest.togglingAll()
    XCTAssertEqual(full.rawValue, 0x8000_000f)
    XCTAssertEqual(try full.togglingAll(), [])
    XCTAssertEqual(try full.setting(.all, enabled: false), .partial)
    for option: LayerProtection in [.transparency, .image, .position, .autoNest] {
      XCTAssertEqual(try full.setting(option, enabled: false), full)
    }
    XCTAssertEqual(try empty.setting(.all, enabled: true), full)
  }

  func testAllKnownCombinationsPreserveRawArchiveBits() throws {
    for value in UInt32(0)...15 {
      for high: UInt32 in [0, 0x8000_0000] {
        let state = LayerProtection(rawValue: value | high)
        try state.validate()
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(LayerProtection.self, from: data), state)
      }
    }
  }

  func testUnknownAndInvalidRequestsFailExplicitly() throws {
    for bit in 4..<31 {
      let state = LayerProtection(rawValue: 1 << bit)
      XCTAssertThrowsError(try state.validate())
      XCTAssertThrowsError(try state.togglingAll())
      XCTAssertThrowsError(try state.setting(.all, enabled: false))
      // Opaque storage can survive without claiming executable support.
      XCTAssertEqual(try JSONDecoder().decode(LayerProtection.self,
        from: JSONEncoder().encode(state)), state)
    }
    XCTAssertThrowsError(try LayerProtection().setting([], enabled: true))
    XCTAssertThrowsError(try LayerProtection().setting([.image, .position], enabled: true))
    for raw in ["-1", "4294967296", "1.5", "true", "\"1\"", "null"] {
      XCTAssertThrowsError(try JSONDecoder().decode(LayerProtection.self, from: Data(raw.utf8)))
    }
  }
}
