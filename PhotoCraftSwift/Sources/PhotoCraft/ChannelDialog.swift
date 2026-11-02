import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

@MainActor @Observable final class ChannelDialog: Identifiable {
  enum Kind { case save, load, options, quickOptions, newSpot }
  let id = UUID()
  let source: CraftDocument
  var spotEnabled = false
  var spotColor = Pixel.black
  var solidity: Float = 0
  let kind: Kind
  let target: ChannelPlaneTarget?
  var name = ""
  var channelID: UUID?
  var mode = SelectionMode.replace
  var invert = false
  var options = ChannelDisplayOptions()
  var error: String?
  var title: String { switch kind { case .save:"Save Selection"; case .load:"Load Selection"; case .options:spotEnabled ? "Spot Channel Options":"Channel Options"; case .quickOptions:"Quick Mask Options";case .newSpot:"New Spot Channel" } }
  init(kind: Kind,document: CraftDocument,target: ChannelPlaneTarget?,defaults: ChannelDisplayOptions) {
    self.source=document; self.kind = kind; self.target = kind == .quickOptions ? .quickMask:(kind == .newSpot ? nil:target)
    name = document.suggestedChannelName
    if kind == .load { channelID = document.alphaChannels?.first?.id }
    if kind != .newSpot,let channel = try? document.channel(self.target ?? .quickMask) { name = channel.name; options = channel.options;spotEnabled=channel.spot != nil;spotColor=channel.spot?.color ?? .black;solidity=channel.spot?.solidity ?? 0 }
    else if kind == .quickOptions { options = defaults }
    if kind == .newSpot {spotEnabled=true;name="Spot Color"}
  }
  func command(document: CraftDocument) throws -> Command? {
    switch kind {
    case .newSpot:return .channel(.create(try document.newSpotChannel(name:name,ink:SpotInk(color:spotColor,solidity:solidity))))
    case .save: return .channel(.saveSelection(channelID,channelID == nil ? name:nil,mode))
    case .load:
      guard let channelID else { throw CraftError.invalid("Choose a saved channel.") }
      return .channel(.load(.alpha(channelID),mode,invert))
    case .options:
      guard case .alpha(let id)=target else { throw CraftError.invalid("Select an auxiliary channel.") }
      return .channel(.configure(id,name,options,spotEnabled ? SpotInk(color:spotColor,solidity:solidity):nil))
    case .quickOptions:
      try options.validate(); return document.quickMask == nil ? nil:.channel(.options(.quickMask,options))
    }
  }
}
struct ChannelDialogSheet: View {
  @Bindable var store: EditorStore
  @Bindable var draft: ChannelDialog
  var body: some View {
    VStack(alignment:.leading,spacing:16) {
      Text(draft.title).font(.headline)
      if draft.kind == .save || draft.kind == .load {
        Picker("Channel",selection:$draft.channelID) {
          if draft.kind == .save { Text("New").tag(UUID?.none) }
          ForEach(store.document.alphaChannels ?? []) { Text($0.name).tag(Optional($0.id)) }
        }
        if draft.kind == .save && draft.channelID == nil { TextField("Name",text:$draft.name).textFieldStyle(.roundedBorder) }
        Picker("Operation",selection:$draft.mode) {
          Text("New Selection").tag(SelectionMode.replace); Text("Add to Selection").tag(SelectionMode.add)
          Text("Subtract from Selection").tag(SelectionMode.subtract); Text("Intersect with Selection").tag(SelectionMode.intersect)
        }.pickerStyle(.radioGroup)
        if draft.kind == .load { Toggle("Invert",isOn:$draft.invert) }
      } else {
        if draft.kind != .quickOptions {TextField("Name",text:$draft.name).textFieldStyle(.roundedBorder)}
        if draft.kind != .newSpot {
          Picker("Color Indicates",selection:Binding(get:{draft.spotEnabled ? "spot":draft.options.indicates.rawValue},set:{value in
            draft.spotEnabled=value == "spot";if let indicates=ChannelDisplayOptions.Indicates(rawValue:value){draft.options.indicates=indicates}
          })) {
            Text("Masked Areas").tag("maskedAreas");Text("Selected Areas").tag("selectedAreas")
            if draft.kind == .options {Text("Spot Color").tag("spot")}
          }.pickerStyle(.radioGroup)
        }
        ColorPicker("Color",selection:Binding(get:{ let p=draft.spotEnabled ? draft.spotColor:draft.options.color;return Color(red:Double(p.r),green:Double(p.g),blue:Double(p.b)) },set:{color in
          if let c=NSColor(color).usingColorSpace(.sRGB){let p=Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent));if draft.spotEnabled {draft.spotColor=p}else{draft.options.color=p}}
        }),supportsOpacity:false)
        if draft.spotEnabled {
          HStack {Text("Solidity");Slider(value:$draft.solidity,in:0...1);Text("\(Int(draft.solidity*100))%")}
          Text("Solidity changes the preview; it does not change ink separation values.").font(.caption).foregroundStyle(.secondary)
        } else {HStack {Text("Opacity");Slider(value:$draft.options.opacity,in:0...1);Text("\(Int(draft.options.opacity*100))%")}}
      }
      if let error = draft.error { Text(error).foregroundStyle(.red) }
      HStack { Spacer(); Button("Cancel") { store.channelDialog = nil }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitChannelDialog(draft) }.keyboardShortcut(.defaultAction) }
    }.padding(20).frame(width:380)
  }
}
