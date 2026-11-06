import AppKit
import PhotoCraftCore
import UniformTypeIdentifiers

@MainActor final class CustomKernelPresetSaveAccessory:NSObject {
  static let acfType=UTType(filenameExtension:"acf",conformingTo:.data) ?? .data
  let view=NSView(frame:NSRect(x:0,y:0,width:390,height:34))
  let picker=NSPopUpButton(frame:NSRect(x:65,y:5,width:310,height:25),pullsDown:false)
  private weak var panel:NSSavePanel?
  var format:CustomKernelPreset.Format {picker.indexOfSelectedItem==1 ? .json:.acf}
  init(panel:NSSavePanel,canExportACF:Bool=true) {
    self.panel=panel;super.init()
    let label=NSTextField(labelWithString:"Format:");label.frame=NSRect(x:0,y:8,width:60,height:20);view.addSubview(label)
    picker.menu?.autoenablesItems=false
    picker.addItems(withTitles:["Custom Filter (.acf)","Photato JSON (.json)"])
    picker.item(at:0)?.isEnabled=canExportACF
    if !canExportACF {
      picker.selectItem(at:1)
      picker.toolTip="ACF requires whole-number Scale and Offset. Photato JSON preserves fractional values."
    }
    picker.setAccessibilityLabel("Custom filter preset format")
    picker.target=self;picker.action=#selector(updateFormat);view.addSubview(picker)
    panel.accessoryView=view;panel.canSelectHiddenExtension=false;panel.isExtensionHidden=false
    panel.nameFieldStringValue="Custom Filter";updateFormat()
  }
  @objc func updateFormat() {
    guard let panel else{return}
    let name=panel.nameFieldStringValue as NSString
    let known=CustomKernelPreset.Format(rawValue:name.pathExtension.lowercased()) != nil
    // AppKit appends the preferred allowed extension when it presents the panel.
    // Supplying another suffix here duplicates it in the live filename field.
    panel.nameFieldStringValue=known ? name.deletingPathExtension:(name as String)
    panel.allowedContentTypes=[format == .acf ? Self.acfType:.json]
  }
}
