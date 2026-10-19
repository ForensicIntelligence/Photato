import SwiftUI

struct DevelopmentTipsView: View {
  @Bindable var tips: DevelopmentTips
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Support Development", systemImage: "heart").font(.title2).fontWeight(.semibold)
      Text(
        "Photato is open source. If it’s useful to you, an optional tip helps support its development."
      )
      Text(
        "Tips are one-time purchases through the App Store. All editing features remain available to everyone."
      )
      .foregroundStyle(.secondary)
      switch tips.catalogState {
      case .idle, .loading:
        ProgressView("Loading tips from the App Store…")
      case .ready:
        ForEach(tips.products) { product in
          HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
              Text(product.name).fontWeight(.medium)
              Text(product.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Tip \(product.displayPrice)") { Task { await tips.purchase(product.id) } }
              .disabled(tips.isPurchasing)
              .accessibilityLabel("\(product.name), \(product.displayPrice), one-time tip")
          }
        }
        if tips.isPurchasing { ProgressView("Waiting for the App Store…") }
      case .restricted:
        Text("In-app purchases aren’t allowed on this Mac.").foregroundStyle(.secondary)
      case .unavailable:
        Text(
          "Tips are currently unavailable in the App Store. You can keep using Photato normally."
        )
        .foregroundStyle(.secondary)
      case .failed:
        Text("Couldn’t load tips from the App Store. Check your connection and try again.")
          .foregroundStyle(.secondary)
      }
      if let message = tips.message {
        Text(message).foregroundStyle(tips.purchaseState == .failed ? Color.red : Color.primary)
          .accessibilityLabel(message)
      }
      HStack {
        Text("Code, testing and documentation contributions are also welcome.")
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        if tips.catalogState != .loading {
          Button("Reload Tips") { Task { await tips.load() } }.disabled(tips.isPurchasing)
        }
      }
    }.padding(24).frame(width: 490).fixedSize(horizontal: false, vertical: true)
      .task {
        await tips.recoverUnfinished()
        if tips.catalogState != .ready { await tips.load() }
      }
  }
}
