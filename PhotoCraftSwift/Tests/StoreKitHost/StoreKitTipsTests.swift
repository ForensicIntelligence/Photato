import StoreKit
import StoreKitTest
import XCTest

@testable import PhotoCraftTipsHost

final class StoreKitTipsTests: XCTestCase {
  @MainActor private func localSession() async throws -> SKTestSession {
    let config = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "DevelopmentTips", withExtension: "storekit"))
    let session = try SKTestSession(contentsOf: config)
    session.resetToDefaultState()
    session.disableDialogs = true
    session.clearTransactions()
    try await session.setSimulatedError(nil, forAPI: .purchase)
    // Refuse to call Product.purchase outside Apple's local Xcode simulator.
    guard case .verified(let app) = try await AppTransaction.shared, app.environment == .xcode
    else {
      XCTFail("StoreKit test environment is not Xcode")
      throw TipError.unavailable
    }
    return session
  }

  @MainActor func testLocalStoreKitConsumablePurchasesAndUnfinishedRecovery() async throws {
    let session = try await localSession()
    defer {
      session.clearTransactions()
      session.resetToDefaultState()
    }
    // Observe updates without consuming them, so the test can simulate an interrupted app.
    let observer = Task { for await _ in Transaction.updates { if Task.isCancelled { break } } }
    defer { observer.cancel() }
    let ids = ["small", "medium", "large"].map { "local.photocraft.swift.tip." + $0 }
    let client = StoreKitTipClient()
    let products = try await client.products(for: ids)
    XCTAssertEqual(Set(products.map(\.id)), Set(ids))
    XCTAssertTrue(products.allSatisfy { $0.isConsumable && !$0.displayPrice.isEmpty })
    // Real StoreKit APIs, backed only by Xcode's local .storekit simulator; no account or charge.
    for _ in 0..<2 {
      let result = try await client.purchase(ids[0])
      guard case .success(.verified(let transaction)) = result else {
        return XCTFail("Local StoreKit did not verify the consumable")
      }
      XCTAssertEqual(transaction.productID, ids[0])
      XCTAssertTrue(transaction.isConsumable)
      await transaction.finish()
    }
    XCTAssertEqual(session.allTransactions().count, 2)
    let result = try await client.purchase(ids[1])
    guard case .success(.verified(let unfinished)) = result else {
      return XCTFail("Missing unfinished local tip")
    }
    var found = false
    for await verification in Transaction.unfinished {
      if case .verified(let transaction) = verification, transaction.id == unfinished.id {
        found = true
      }
    }
    XCTAssertTrue(found)
    // Exercise the app's launch listener and recovery path, not just the purchase return value.
    let store = DevelopmentTips(productIDs: ids, client: StoreKitTipClient())
    defer { store.stopListening() }
    store.startListening()
    for _ in 0..<100 where store.purchaseState != .thanked {
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertEqual(store.purchaseState, .thanked)
    for await verification in Transaction.unfinished {
      if case .verified(let transaction) = verification {
        XCTAssertNotEqual(transaction.id, unfinished.id)
      }
    }
  }

  @MainActor func testLocalStoreKitPendingApprovalRecoveryOnRefresh() async throws {
    let session = try await localSession()
    defer {
      session.clearTransactions()
      session.resetToDefaultState()
    }
    session.askToBuyEnabled = true
    let id = "local.photocraft.swift.tip.small"
    let tips = DevelopmentTips(productIDs: [id], client: StoreKitTipClient())
    defer { tips.stopListening() }
    await tips.load()
    await tips.purchase(id)
    XCTAssertEqual(tips.purchaseState, .pending)
    let transaction = try XCTUnwrap(session.allTransactions().first)
    try session.approveAskToBuyTransaction(identifier: transaction.identifier)
    XCTAssertFalse(try XCTUnwrap(session.allTransactions().first).pendingAskToBuyConfirmation)
    // A foreground/Reload Tips refresh also recovers approvals when push delivery is delayed.
    await tips.recoverUnfinished()
    for _ in 0..<1500 where tips.purchaseState != .thanked {
      try await Task.sleep(for: .milliseconds(20))
      await tips.recoverUnfinished()
    }
    XCTAssertEqual(tips.purchaseState, .thanked)
    XCTAssertFalse(tips.isPurchasing)
  }

  @MainActor func testLocalStoreKitFailureAndRetry() async throws {
    let session = try await localSession()
    defer {
      session.clearTransactions()
      session.resetToDefaultState()
    }
    let id = "local.photocraft.swift.tip.medium"
    let tips = DevelopmentTips(productIDs: [id], client: StoreKitTipClient())
    defer { tips.stopListening() }
    await tips.load()
    try await session.setSimulatedError(.purchase(.purchaseNotAllowed), forAPI: .purchase)
    await tips.purchase(id)
    XCTAssertEqual(tips.purchaseState, .failed)
    XCTAssertFalse(tips.isPurchasing)
    try await session.setSimulatedError(nil, forAPI: .purchase)
    await tips.purchase(id)
    XCTAssertEqual(tips.purchaseState, .thanked)
    XCTAssertEqual(session.allTransactions().count, 1)
  }
}
