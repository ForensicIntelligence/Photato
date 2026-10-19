import PhotoCraftCore
import SwiftUI

struct HistogramChart: View {
  let histogram: RGBHistogram
  let channel: LevelsAdjustment.Channel
  var body: some View {
    let bins = histogram.bins(channel)
    let peak = max(1, bins.max() ?? 1)
    Canvas { context, size in
      var bars = Path()
      for (i, count) in bins.enumerated() {
        let x = CGFloat(i) * size.width / 256
        let height = CGFloat(count) / CGFloat(peak) * size.height
        bars.addRect(
          CGRect(x: x, y: size.height - height, width: max(1, size.width / 256), height: height))
      }
      let color: Color =
        switch channel {
        case .rgb: .primary
        case .red: .red
        case .green: .green
        case .blue: .blue
        }
      context.fill(bars, with: .color(color.opacity(0.8)))
    }
    .background(.black.opacity(0.15))
    .overlay {
      if histogram.samples == 0 {
        Text("No visible pixels").font(.caption).foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(channel.rawValue) histogram, \(histogram.samples) visible pixels")
  }
}
