import Foundation
import StoreKit
import XCTest

@testable import PhotoCraft

private actor FinishCounter {
  var count = 0
  func finish() { count += 1 }
  func finishSlowly() async {
    count += 1
    try? await Task.sleep(for: .milliseconds(20))
  }
}

@MainActor private final class FakeTipClient: TipClient {
  var canMakePayments = true
  var fetched: [TipProduct] = []
  var result = TipPurchaseResult.cancelled
  var shouldFail = false
  var cancelWithError = false
  var recovered: [TipDelivery] = []
  var purchaseCount = 0
  var catalogCount = 0
  var waitForPurchase: CheckedContinuation<TipPurchaseResult, Never>?
  var suspendPurchase = false
  let stream = AsyncStream<TipDelivery>.makeStream()
  func products(for ids: [String]) async throws -> [TipProduct] {
    catalogCount += 1
    if shouldFail { throw TipError.unavailable }
    return fetched
  }
  func purchase(_ id: String) async throws -> TipPurchaseResult {
    purchaseCount += 1
    if cancelWithError { throw StoreKitError.userCancelled }
    if shouldFail { throw TipError.unavailable }
    if suspendPurchase { return await withCheckedContinuation { waitForPurchase = $0 } }
    return result
  }
  func deliveries() -> AsyncStream<TipDelivery> { stream.stream }
  func unfinished() async -> [TipDelivery] { recovered }
}

final class DevelopmentTipsTests: XCTestCase {
  @MainActor private func fixture() -> (DevelopmentTips, FakeTipClient) {
    let client = FakeTipClient()
    client.fetched = [
      TipProduct(
        id: "tip.small", name: "Small Tip", detail: "Support development",
        displayPrice: "CA$2.79", isConsumable: true)
    ]
    return (DevelopmentTips(productIDs: ["tip.small", "tip.large"], client: client), client)
  }
  private func delivery(
    _ counter: FinishCounter, id: UInt64 = 1, product: String = "tip.small",
    consumable: Bool = true, revoked: Bool = false
  ) -> TipDelivery {
    .verified(
      TipTransaction(
        id: id, productID: product, isConsumable: consumable, revoked: revoked,
        finish: { await counter.finish() }))
  }
  @MainActor func testCatalogUsesOnlyConfiguredConsumablesAndStorefrontPrice() async {
    let (tips, client) = fixture()
    defer { tips.stopListening() }
    client.fetched += [
      TipProduct(
        id: "tip.large", name: "Wrong type", detail: "", displayPrice: "$9", isConsumable: false),
      TipProduct(
        id: "unrelated", name: "Other", detail: "", displayPrice: "$1", isConsumable: true),
    ]
    await tips.load()
    XCTAssertEqual(tips.catalogState, .ready)
    XCTAssertEqual(tips.products.map(\.id), ["tip.small"])
    XCTAssertEqual(tips.products.first?.displayPrice, "CA$2.79")
    await tips.purchase("unrelated")
    XCTAssertEqual(client.purchaseCount, 0)
  }
  @MainActor func testUnavailableRestrictedAndNetworkFailureCanRetry() async {
    let (tips, client) = fixture()
    defer { tips.stopListening() }
    client.canMakePayments = false
    await tips.load()
    XCTAssertEqual(tips.catalogState, .restricted)
    XCTAssertEqual(client.catalogCount, 0)
    client.canMakePayments = true
    client.shouldFail = true
    await tips.load()
    XCTAssertEqual(tips.catalogState, .failed)
    client.shouldFail = false
    let products = client.fetched
    client.fetched = []
    await tips.load()
    XCTAssertEqual(tips.catalogState, .unavailable)
    client.fetched = products
    await tips.load()
    XCTAssertEqual(tips.catalogState, .ready)
  }
  @MainActor func testVerifiedTipFinishesExactlyOnceAndCanBeBoughtAgain() async {
    let (tips, client) = fixture()
    defer { tips.stopListening() }
    let counter = FinishCounter()
    await tips.load()
    client.result = .success(delivery(counter))
    await tips.purchase("tip.small")
    XCTAssertEqual(tips.purchaseState, .thanked)
    // StoreKit can also deliver the same transaction in updates.
    await tips.receive(delivery(counter))
    var count = await counter.count
    XCTAssertEqual(count, 1)
    client.result = .success(delivery(counter, id: 2))
    await tips.purchase("tip.small")
    count = await counter.count
    XCTAssertEqual(count, 2)
    XCTAssertFalse(tips.isPurchasing)
  }
  @MainActor func testUnverifiedUnexpectedAndNonConsumableTransactionsNeverFinish() async {
    let (tips, client) = fixture()
    defer { tips.stopListening() }
    let counter = FinishCounter()
    await tips.load()
    client.result = .success(.unverified)
    await tips.purchase("tip.small")
    XCTAssertEqual(tips.purchaseState, .failed)
    client.result = .success(delivery(counter, product: "tip.large"))
    await tips.purchase("tip.small")
    XCTAssertEqual(tips.purchaseState, .failed)
    await tips.receive(delivery(counter, product: "unrelated"))
    await tips.receive(delivery(counter, consumable: false))
    let count = await counter.count
    XCTAssertEqual(count, 0)
  }
  @MainActor func testCancellationPendingApprovalAndTransactionRecovery() async {
    let (tips, client) = fixture()
    defer { tips.stopListening() }
    await tips.load()
    await tips.purchase("tip.small")
    XCTAssertEqual(tips.purchaseState, .idle)
    XCTAssertNil(tips.message)
    client.result = .pending
    await tips.purchase("tip.small")
    XCTAssertEqual(tips.purchaseState, .pending)
    let counter = FinishCounter()
    client.stream.continuation.yield(delivery(counter))
    for _ in 0..<100 where tips.purchaseState != .thanked { await Task.yield() }
    XCTAssertEqual(tips.purchaseState, .thanked)
    let count = await counter.count
    XCTAssertEqual(count, 1)
  }
  @MainActor func testPurchaseLockAndFailedPurchaseRelease() async {
    let (tips, client) = fixture()
    defer { tips.stopListening() }
    await tips.load()
    client.suspendPurchase = true
    let first = Task { await tips.purchase("tip.small") }
    for _ in 0..<100 where client.waitForPurchase == nil { await Task.yield() }
    XCTAssertTrue(tips.isPurchasing)
    await tips.purchase("tip.small")
    XCTAssertEqual(client.purchaseCount, 1)
    client.waitForPurchase?.resume(returning: .cancelled)
    await first.value
    XCTAssertFalse(tips.isPurchasing)
    client.shouldFail = true
    await tips.purchase("tip.small")
    XCTAssertEqual(tips.purchaseState, .failed)
    XCTAssertFalse(tips.isPurchasing)
  }
  @MainActor func testRevokedVerifiedTipIsAcknowledgedWithoutThankingOrEntitlements() async {
    let (tips, _) = fixture()
    let counter = FinishCounter()
    let accepted = await tips.receive(delivery(counter, revoked: true))
    XCTAssertFalse(accepted)
    XCTAssertEqual(tips.purchaseState, .idle)
    XCTAssertNil(tips.message)
    let count = await counter.count
    XCTAssertEqual(count, 1)
  }

  @MainActor func testApprovalArrivingBeforePendingReturnKeepsThankYou() async {
    let (tips, client) = fixture()
    defer { tips.stopListening() }
    await tips.load()
    client.suspendPurchase = true
    let purchase = Task { await tips.purchase("tip.small") }
    for _ in 0..<100 where client.waitForPurchase == nil {
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertNotNil(client.waitForPurchase)
    await tips.receive(delivery(FinishCounter()))
    client.waitForPurchase?.resume(returning: .pending)
    await purchase.value
    XCTAssertEqual(tips.purchaseState, .thanked)
    XCTAssertFalse(tips.isPurchasing)
    // A repeated update from the previous purchase must not acknowledge a new pending tip.
    client.suspendPurchase = false
    client.result = .pending
    await tips.purchase("tip.small")
    await tips.receive(delivery(FinishCounter()))
    XCTAssertEqual(tips.purchaseState, .pending)
  }

  @MainActor func testConcurrentDeliveryFinishesOnlyOnce() async {
    let (tips, _) = fixture()
    let counter = FinishCounter()
    let same = TipDelivery.verified(
      TipTransaction(
        id: 42, productID: "tip.small",
        isConsumable: true, revoked: false, finish: { await counter.finishSlowly() }))
    let first = Task { await tips.receive(same) }
    let second = Task { await tips.receive(same) }
    let results = await (first.value, second.value)
    XCTAssertTrue(results.0 && results.1)
    let count = await counter.count
    XCTAssertEqual(count, 1)
    XCTAssertEqual(tips.purchaseState, .thanked)
  }

  @MainActor func testRefreshRecoversApprovalAndThrownCancellationIsQuiet() async {
    let (tips, client) = fixture()
    defer { tips.stopListening() }
    await tips.load()
    client.cancelWithError = true
    await tips.purchase("tip.small")
    XCTAssertEqual(tips.purchaseState, .idle)
    XCTAssertNil(tips.message)
    client.cancelWithError = false
    client.result = .pending
    await tips.purchase("tip.small")
    let counter = FinishCounter()
    client.recovered = [delivery(counter)]
    await tips.recoverUnfinished()
    XCTAssertEqual(tips.purchaseState, .thanked)
    await tips.load()
    let count = await counter.count
    XCTAssertEqual(count, 1)
  }
}
