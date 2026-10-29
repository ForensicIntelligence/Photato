import AppKit
import PhotoCraftImaging

@MainActor final class JPEGSaveControls: NSObject {
  let view = NSStackView()
  let quality = NSPopUpButton(frame: .zero, pullsDown: false)
  let format = NSPopUpButton(frame: .zero, pullsDown: false)
  let profile = NSPopUpButton(frame: .zero, pullsDown: false)
  let matteChoice = NSPopUpButton(frame: .zero, pullsDown: false)
  let matte = NSColorWell()
  override init() {
    super.init()
    view.orientation = .vertical; view.alignment = .leading; view.spacing = 8
    quality.addItems(withTitles: ["Default (95%)"] + (0...12).map(String.init))
    format.addItems(withTitles: ["Default", "Baseline (Standard)", "Baseline Optimized", "Progressive"])
    profile.addItems(withTitles: ["Default (Working Profile)", "Embed Color Profile", "Do Not Embed"])
    matteChoice.addItems(withTitles: ["White", "Custom"])
    matte.color = .white; matte.supportsAlpha = false
    matteChoice.target = self; matteChoice.action = #selector(updateMatte)
    matte.setAccessibilityLabel("JPEG custom matte color")
    for (label, control) in [("Quality", quality), ("Format Options", format), ("Color Profile", profile)] {
      control.setAccessibilityLabel("JPEG " + label.lowercased())
      view.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: label + ":"), control]))
    }
    matteChoice.setAccessibilityLabel("JPEG matte")
    view.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: "Matte:"), matteChoice, matte]))
    updateMatte()
  }
  func configure(_ options: RasterEncodingOptions) {
    quality.selectItem(at: options.jpegQuality.map { $0 + 1 } ?? 0)
    format.selectItem(at: options.jpegFormat.flatMap {
      RasterEncodingOptions.JPEGFormat.allCases.firstIndex(of: $0)
    }.map { $0 + 1 } ?? 0)
    profile.selectItem(at: options.jpegEmbedProfile.map { $0 ? 1 : 2 } ?? 0)
    if let rgb = options.jpegMatte, rgb.count == 3 {
      matte.color = NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
      matteChoice.selectItem(at: 1)
    }
    updateMatte()
  }
  @objc func updateMatte() { matte.isEnabled = matteChoice.indexOfSelectedItem == 1 }
  var options: RasterEncodingOptions {
    let color = matte.color.usingColorSpace(.sRGB) ?? .white
    return .init(
      jpegQuality: quality.indexOfSelectedItem <= 0 ? nil : quality.indexOfSelectedItem - 1,
      jpegFormat: format.indexOfSelectedItem <= 0 ? nil : RasterEncodingOptions.JPEGFormat.allCases[format.indexOfSelectedItem - 1],
      jpegMatte: matteChoice.indexOfSelectedItem == 1 ? [color.redComponent, color.greenComponent, color.blueComponent] : nil,
      jpegEmbedProfile: profile.indexOfSelectedItem == 0 ? nil : profile.indexOfSelectedItem == 1)
  }
}
