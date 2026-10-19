import Foundation
import Observation
import StoreKit

struct TipProduct: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let detail: String
  let displayPrice: String
  let isConsumable: Bool
}

struct TipTransaction: Sendable {
  let id: UInt64
  let productID: String
  let isConsumable: Bool
  let revoked: Bool
  let finish: @Sendable () async -> Void
}

enum TipDelivery: Sendable {
  case verified(TipTransaction)
  case unverified
}

enum TipPurchaseResult: Sendable {
  case success(TipDelivery)
  case pending, cancelled
}

/// StoreKit is isolated here so transaction policy can be tested without charging an account.
@MainActor protocol TipClient {
  var canMakePayments: Bool { get }
  func products(for ids: [String]) async throws -> [TipProduct]
  func purchase(_ id: String) async throws -> TipPurchaseResult
  func deliveries() -> AsyncStream<TipDelivery>
  func unfinished() async -> [TipDelivery]
}

@MainActor final class StoreKitTipClient: TipClient {
  private var productsByID: [String: Product] = [:]
  var canMakePayments: Bool { AppStore.canMakePayments }

  func products(for ids: [String]) async throws -> [TipProduct] {
    let products = try await Product.products(for: ids)
    productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
    return products.map {
      TipProduct(
        id: $0.id, name: $0.displayName, detail: $0.description,
        displayPrice: $0.displayPrice, isConsumable: $0.type == .consumable)
    }
  }

  func purchase(_ id: String) async throws -> TipPurchaseResult {
    guard let product = productsByID[id], product.type == .consumable else {
      throw TipError.unavailable
    }
    switch try await product.purchase() {
    case .success(let result): return .success(Self.delivery(result))
    case .pending: return .pending
    case .userCancelled: return .cancelled
    @unknown default: throw TipError.unavailable
    }
  }

  func deliveries() -> AsyncStream<TipDelivery> {
    let (stream, continuation) = AsyncStream<TipDelivery>.makeStream()
    // Start updates before draining unfinished transactions: approvals can arrive at any time.
    let updates = Task {
      for await result in Transaction.updates {
        guard !Task.isCancelled else { break }
        continuation.yield(Self.delivery(result))
      }
    }
    let unfinished = Task {
      for await result in Transaction.unfinished {
        guard !Task.isCancelled else { break }
        continuation.yield(Self.delivery(result))
      }
    }
    continuation.onTermination = { _ in
      updates.cancel()
      unfinished.cancel()
    }
    return stream
  }

  func unfinished() async -> [TipDelivery] {
    var deliveries: [TipDelivery] = []
    for await result in Transaction.unfinished {
      guard !Task.isCancelled else { break }
      deliveries.append(Self.delivery(result))
    }
    return deliveries
  }

  private static func delivery(_ result: VerificationResult<Transaction>) -> TipDelivery {
    switch result {
    case .verified(let transaction):
      return .verified(
        TipTransaction(
          id: transaction.id, productID: transaction.productID,
          isConsumable: transaction.productType == .consumable,
          revoked: transaction.revocationDate != nil,
          finish: { await transaction.finish() }))
    case .unverified: return .unverified
    }
  }
}

enum TipError: LocalizedError {
  case unavailable
  var errorDescription: String? { "This tip is unavailable. Please reload the available tips." }
}

@MainActor @Observable final class DevelopmentTips {
  enum CatalogState: Equatable {
    case idle, loading, ready, unavailable, restricted, failed
  }
  enum PurchaseState: Equatable {
    case idle, purchasing, pending, thanked, failed
  }
  let productIDs: [String]
  private(set) var products: [TipProduct] = []
  private(set) var catalogState = CatalogState.idle
  private(set) var purchaseState = PurchaseState.idle
  private(set) var isPurchasing = false
  private(set) var message: String?
  @ObservationIgnored private let client: any TipClient
  @ObservationIgnored private var listener: Task<Void, Never>?
  @ObservationIgnored private var finishedIDs = Set<UInt64>()
  @ObservationIgnored private var finishing: [UInt64: Task<Void, Never>] = [:]
  @ObservationIgnored private var completedCounts: [String: Int] = [:]

  init(productIDs: [String], client: any TipClient) {
    self.productIDs = productIDs
    self.client = client
  }

  func startListening() {
    guard listener == nil, !productIDs.isEmpty else { return }
    let deliveries = client.deliveries()
    listener = Task { [weak self] in
      for await delivery in deliveries {
        guard !Task.isCancelled, let self else { break }
        await self.receive(delivery)
      }
    }
  }

  func stopListening() {
    listener?.cancel()
    listener = nil
  }

  func recoverUnfinished() async {
    guard !productIDs.isEmpty else { return }
    for delivery in await client.unfinished() {
      guard !Task.isCancelled else { return }
      await receive(delivery)
    }
  }

  func load() async {
    guard catalogState != .loading, !isPurchasing else { return }
    guard client.canMakePayments else {
      catalogState = .restricted
      products = []
      return
    }
    guard !productIDs.isEmpty else {
      catalogState = .unavailable
      return
    }
    startListening()
    catalogState = .loading
    await recoverUnfinished()
    do {
      let fetched = try await client.products(for: productIDs)
      guard !Task.isCancelled else {
        catalogState = .idle
        return
      }
      // Only allow the configured consumables, in the maintainer's tier order.
      products = productIDs.compactMap { id in fetched.first { $0.id == id && $0.isConsumable } }
      catalogState = products.isEmpty ? .unavailable : .ready
    } catch {
      products = []
      catalogState = Task.isCancelled ? .idle : .failed
    }
  }

  func purchase(_ id: String) async {
    guard !isPurchasing, catalogState == .ready,
      products.contains(where: { $0.id == id && $0.isConsumable })
    else { return }
    guard client.canMakePayments else {
      catalogState = .restricted
      return
    }
    isPurchasing = true
    purchaseState = .purchasing
    message = nil
    let completionsBeforePurchase = completedCounts[id, default: 0]
    defer { isPurchasing = false }
    do {
      switch try await client.purchase(id) {
      case .success(let delivery):
        await receive(delivery, expectedProduct: id)
      case .pending:
        // An approval update may finish while purchase() is still returning pending.
        guard completedCounts[id, default: 0] == completionsBeforePurchase else { return }
        purchaseState = .pending
        message = "Your tip is awaiting approval. We’ll confirm it when the App Store completes it."
      case .cancelled:
        guard completedCounts[id, default: 0] == completionsBeforePurchase else { return }
        purchaseState = .idle
        message = nil
      }
    } catch StoreKitError.userCancelled {
      guard completedCounts[id, default: 0] == completionsBeforePurchase else { return }
      purchaseState = .idle
      message = nil
    } catch {
      guard completedCounts[id, default: 0] == completionsBeforePurchase else { return }
      purchaseState = .failed
      message = "The App Store couldn’t complete your tip. Please try again."
    }
  }

  @discardableResult func receive(_ delivery: TipDelivery, expectedProduct: String? = nil) async
    -> Bool
  {
    guard case .verified(let transaction) = delivery else {
      purchaseState = .failed
      message = "The App Store purchase couldn’t be verified. Please try again later."
      return false
    }
    guard productIDs.contains(transaction.productID), transaction.isConsumable,
      expectedProduct == nil || expectedProduct == transaction.productID
    else {
      // Never consume a product owned by another feature or a mismatched purchase response.
      if expectedProduct != nil {
        purchaseState = .failed
        message = "The App Store returned an unexpected product. Your tip wasn’t confirmed."
      }
      return false
    }
    if !finishedIDs.contains(transaction.id) {
      if let task = finishing[transaction.id] {
        await task.value
      } else {
        let task = Task { await transaction.finish() }
        finishing[transaction.id] = task
        await task.value
        finishing[transaction.id] = nil
      }
    }
    let firstDelivery = finishedIDs.insert(transaction.id).inserted
    guard !transaction.revoked else {
      purchaseState = .idle
      message = nil
      return false
    }
    guard firstDelivery else { return true }
    completedCounts[transaction.productID, default: 0] += 1
    // A voluntary tip is fulfilled immediately. It grants no persistent entitlement.
    purchaseState = .thanked
    message = "Thank you for supporting Photato’s development."
    return true
  }
}
