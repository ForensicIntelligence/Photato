import AppKit
import PhotoCraftImaging

/// Native Save As/Copy controls over the same options used by document transfers.
@MainActor final class OpenEXRSaveControls {
  let view = NSStackView()
  let compression = NSPopUpButton(frame:.zero,pullsDown:false)
  let sample = NSPopUpButton(frame:.zero,pullsDown:false)
  let transparency = NSButton(checkboxWithTitle:"Save Transparency",target:nil,action:nil)
  var options:RasterEncodingOptions {
    .init(exrCompression:OpenEXR.Compression.allCases[compression.indexOfSelectedItem],
      exrSample:OpenEXR.Sample.allCases[sample.indexOfSelectedItem],exrTransparency:transparency.state == .on)
  }
  init() {
    view.orientation = .vertical;view.alignment = .leading;view.spacing = 8
    compression.addItems(withTitles:["None","ZIP (one scan line)","ZIP (16 scan lines)"])
    sample.addItems(withTitles:["Half (16-bit float)","Float (32-bit float)"])
    compression.setAccessibilityLabel("OpenEXR compression")
    sample.setAccessibilityLabel("OpenEXR sample precision")
    transparency.setAccessibilityLabel("OpenEXR transparency")
    for (label,control) in [("Compression:",compression),("Precision:",sample)] {
      let row = NSStackView(views:[NSTextField(labelWithString:label),control]);row.spacing = 12;view.addArrangedSubview(row)
    }
    view.addArrangedSubview(transparency)
    sample.toolTip = "Half reduces sample precision. Float retains 32-bit HDR samples."
    configure(.init())
  }
  func configure(_ options:RasterEncodingOptions) {
    compression.selectItem(at:OpenEXR.Compression.allCases.firstIndex(of:options.exrCompression ?? .zip)!)
    sample.selectItem(at:OpenEXR.Sample.allCases.firstIndex(of:options.exrSample ?? .float)!)
    transparency.state = options.exrTransparency == false ? .off:.on
  }
}
