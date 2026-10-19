import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

/// Deterministic, offscreen rendering of our own native controls. This does not
/// capture the desktop or establish live Photoshop interaction equivalence.
extension AppDelegate {
  func adjustmentSnapshot() {
    var histogram = RGBHistogram()
    for i in 0..<256 { histogram.add(Pixel(Float(i) / 255, 0.25, 0.75)) }
    var hue = HueSaturationAdjustment()
    hue.ranges[0].values = .init(hue: 30, saturation: -40, lightness: 10)
    hue.ranges[0].bounds = [-30, 5, 25, 70]
    let view = HStack(alignment: .top, spacing: 24) {
      VStack(alignment: .leading, spacing: 16) {
        Text("Levels").font(.title3.bold())
        LevelsControls(levels: .constant(.init(rgb: .init(gamma: 1.3))), histogram: histogram)
        Divider()
        Text("Color Balance").font(.title3.bold())
        ColorBalanceControls(
          adjustment: .constant(.init(midtones: .init(cyanRed: 35, yellowBlue: -20))))
      }.frame(width: 298)
      VStack(alignment: .leading, spacing: 16) {
        Text("Curves").font(.title3.bold())
        CurvesControls(curves: .constant(BuiltInCurvesPreset.strong.curves), histogram: histogram)
        Divider()
        Text("Threshold").font(.title3.bold())
        TonalStepsControls(adjustment: .constant(.init(kind: .threshold)), histogram: histogram)
        Divider()
        Text("Posterize").font(.title3.bold())
        TonalStepsControls(adjustment: .constant(.init(kind: .posterize, level: 7)))
      }.frame(width: 298)
      VStack(alignment: .leading, spacing: 16) {
        Text("Hue/Saturation").font(.title3.bold())
        HueSaturationControls(adjustment: .constant(hue), channel: .reds)
      }.frame(width: 298)
    }.padding(24).frame(width: 990, height: 820, alignment: .topLeading)
      .font(.system(size: 11)).foregroundStyle(Color(white: 0.88))
      .background(StudioTheme.panel).tint(StudioTheme.accent).preferredColorScheme(.dark)
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 990, height: 820)
    let window = NSWindow(
      contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.appearance = NSAppearance(named: .darkAqua)
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [window, host] in
      do {
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
          throw CraftError.invalid("Adjustment snapshot allocation failed.")
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
          throw CraftError.invalid("Adjustment snapshot encoding failed.")
        }
        let path = CommandLine.arguments.last ?? "/private/tmp/photato-adjustments.png"
        try data.write(to: URL(fileURLWithPath: path))
        print("Offscreen adjustment snapshot: \(path)")
      } catch { print("Adjustment snapshot failed: \(error)") }
      NSApp.terminate(nil)
    }
  }
}
