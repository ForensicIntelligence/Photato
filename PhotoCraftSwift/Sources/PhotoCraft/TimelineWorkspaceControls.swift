import AppKit
import SwiftUI
import PhotoCraftCore

extension EditorStore {
  var canTrimTimelineToWorkArea:Bool {
    guard canUseTimeline,let t=document.videoTimeline else{return false}
    return t.effectiveWorkArea.startFrame != 0 || t.effectiveWorkArea.endFrame != t.durationFrames
  }
  func trimTimelineToWorkArea(){guard canTrimTimelineToWorkArea else{return};editVideo(.workspace(.trimToWorkArea))}
  func setWorkAreaStartAtPlayhead(){guard let t=document.videoTimeline else{return};let old=t.effectiveWorkArea;editVideo(.workspace(.workArea(.init(startFrame:t.currentFrame,endFrame:max(old.endFrame,t.currentFrame+1)))))}
  func setWorkAreaEndAtPlayhead(){guard let t=document.videoTimeline else{return};let old=t.effectiveWorkArea;editVideo(.workspace(.workArea(.init(startFrame:min(old.startFrame,t.currentFrame),endFrame:t.currentFrame+1))))}
  func toggleOnionSkins(){guard let t=document.videoTimeline else{return};var value=t.onionSkin ?? .init();value.enabled.toggle();editVideo(.workspace(.onionSkin(value)))}
  func presentOnionSkinSettings() {
    guard canUseTimeline,let timeline=document.videoTimeline else{return}
    let snapshot=document,generation=layerPanelGeneration,settings=timeline.onionSkin ?? .init()
    let before=NSTextField(string:String(settings.framesBefore)),after=NSTextField(string:String(settings.framesAfter)),spacing=NSTextField(string:String(settings.spacing))
    let minimum=NSTextField(string:String(settings.minimumOpacity*100)),maximum=NSTextField(string:String(settings.maximumOpacity*100))
    let blend=NSPopUpButton(frame:.zero,pullsDown:false);blend.addItems(withTitles:BlendMode.allCases.map(\.rawValue));blend.selectItem(withTitle:settings.blendMode.rawValue)
    let enabled=NSButton(checkboxWithTitle:"Enable Onion Skins",target:nil,action:nil);enabled.state=settings.enabled ? .on:.off
    let controls:[NSView]=[before,after,spacing,maximum,minimum,blend,enabled]
    let labels=["Frames Before:","Frames After:","Frame Spacing:","Max Opacity (%):","Min Opacity (%):","Blend Mode:",""]
    let grid=NSGridView(views:zip(labels,controls).map{[NSTextField(labelWithString:$0),$1]});grid.rowSpacing=8;grid.columnSpacing=12
    controls.forEach{$0.widthAnchor.constraint(equalToConstant:180).isActive=true};grid.setFrameSize(grid.fittingSize)
    let alert=NSAlert();alert.messageText="Onion Skin Settings";alert.informativeText="Show nearby frames while editing. Onion skins are preview-only and are excluded from image and movie exports."
    alert.accessoryView=grid;alert.addButton(withTitle:"OK");alert.addButton(withTitle:"Cancel")
    let finish:(NSApplication.ModalResponse)->Void = { [weak self] response in
      guard response == .alertFirstButtonReturn,let self else{return}
      do {
        guard self.document==snapshot,self.layerPanelGeneration==generation,self.canUseTimeline else{throw CraftError.invalid("The document changed. Reopen Onion Skin Settings.")}
        guard let a=Int(before.stringValue),let b=Int(after.stringValue),let step=Int(spacing.stringValue),let lo=Float(minimum.stringValue),let hi=Float(maximum.stringValue),let mode=BlendMode(rawValue:blend.titleOfSelectedItem ?? "") else{throw CraftError.invalid("Enter valid onion-skin settings.")}
        let value=OnionSkinSettings(enabled:enabled.state == .on,framesBefore:a,framesAfter:b,spacing:step,minimumOpacity:lo/100,maximumOpacity:hi/100,blendMode:mode)
        try value.validate();self.editVideo(.workspace(.onionSkin(value)))
      }catch{self.error=error.localizedDescription}
    }
    if let window=NSApp.keyWindow{alert.beginSheetModal(for:window,completionHandler:finish)}else{finish(alert.runModal())}
  }
}
struct TimelineWorkspaceMenu:View {
  @Bindable var store:EditorStore
  var body:some View {
    Menu("Work Area") {
      Button("Set Start At Playhead"){store.setWorkAreaStartAtPlayhead()}
      Button("Set End At Playhead"){store.setWorkAreaEndAtPlayhead()}
      Button("Trim Document Duration To Work Area"){store.trimTimelineToWorkArea()}.disabled(!store.canTrimTimelineToWorkArea)
      Divider()
      Button("Reset Work Area"){store.editVideo(.workspace(.workArea(nil)))}
    }
    Toggle("Enable Onion Skins",isOn:Binding(get:{store.document.videoTimeline?.onionSkin?.enabled == true},set:{_ in store.toggleOnionSkins()}))
    Button("Onion Skin Settings…"){store.presentOnionSkinSettings()}
  }
}
