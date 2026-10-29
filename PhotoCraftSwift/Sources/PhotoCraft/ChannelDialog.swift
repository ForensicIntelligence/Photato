import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

@MainActor @Observable final class ChannelDialog: Identifiable {
  enum Kind { case save, load, options, quickOptions }
  let id = UUID()
  let kind: Kind
  let target: ChannelPlaneTarget?
  var name = ""
  var channelID: UUID?
  var mode = SelectionMode.replace
  var invert = false
  var options = ChannelDisplayOptions()
  var error: String?
  var title: String { switch kind { case .save:"Save Selection"; case .load:"Load Selection"; case .options:"Channel Options"; case .quickOptions:"Quick Mask Options" } }
  init(kind: Kind,document: CraftDocument,target: ChannelPlaneTarget?,defaults: ChannelDisplayOptions) {
    self.kind = kind; self.target = kind == .quickOptions ? .quickMask:target
    name = document.suggestedChannelName
    if kind == .load { channelID = document.alphaChannels?.first?.id }
    if let channel = try? document.channel(self.target ?? .quickMask) { name = channel.name; options = channel.options }
    else if kind == .quickOptions { options = defaults }
  }
  func command(document: CraftDocument) throws -> Command? {
    switch kind {
    case .save: return .channel(.saveSelection(channelID,channelID == nil ? name:nil,mode))
    case .load:
      guard let channelID else { throw CraftError.invalid("Choose a saved channel.") }
      return .channel(.load(.alpha(channelID),mode,invert))
    case .options:
      guard let target else { throw CraftError.invalid("Select an alpha channel.") }
      return .channel(.options(target,options))
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
        Picker("Color Indicates",selection:$draft.options.indicates) {
          Text("Masked Areas").tag(ChannelDisplayOptions.Indicates.maskedAreas)
          Text("Selected Areas").tag(ChannelDisplayOptions.Indicates.selectedAreas)
        }.pickerStyle(.radioGroup)
        ColorPicker("Color",selection:Binding(get:{ Color(red:Double(draft.options.color.r),green:Double(draft.options.color.g),blue:Double(draft.options.color.b)) },set:{ color in
          if let c = NSColor(color).usingColorSpace(.sRGB) { draft.options.color = Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent)) }
        }),supportsOpacity:false)
        HStack { Text("Opacity"); Slider(value:$draft.options.opacity,in:0...1); Text("\(Int(draft.options.opacity*100))%") }
      }
      if let error = draft.error { Text(error).foregroundStyle(.red) }
      HStack { Spacer(); Button("Cancel") { store.channelDialog = nil }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitChannelDialog(draft) }.keyboardShortcut(.defaultAction) }
    }.padding(20).frame(width:380)
  }
}
