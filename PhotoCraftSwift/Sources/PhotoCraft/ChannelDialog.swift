import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class ChannelDialog: Identifiable {
  enum Kind:Sendable { case save, load, options, quickOptions, newSpot }
  let id = UUID()
  let source: CraftDocument
  let documents:[CraftDocument]
  let documentNames:[UUID:String]
  let colorSettings:ColorSettings
  func displayName(for document:CraftDocument)->String {documentNames[document.id] ?? document.name}
  var documentID:UUID
  let newDocumentID=UUID()
  var createsDocument:Bool {kind == .save && documentID==newDocumentID}
  var canSaveDestination:Bool {createsDocument || channelID != nil || (selectedDocument.alphaChannels?.count ?? 0)<CraftDocument.maximumAlphaChannels}
  func resetDestination() {
    customLoadSource=nil
    let masks=(selectedDocument.alphaChannels ?? []).filter{$0.spot == nil}
    channelID = kind == .load ? masks.first?.id : (!createsDocument && (selectedDocument.alphaChannels?.count ?? 0)>=CraftDocument.maximumAlphaChannels ? masks.first?.id:nil)
    mode = .replace
  }
  var committing=false
  @ObservationIgnored var task:Task<Void,Never>?
  var selectedDocument:CraftDocument {documents.first {$0.id==documentID} ?? source}
  var canCombine:Bool {kind == .save ? !createsDocument && channelID != nil : source.selection != nil || source.selectionMask != nil}
  var spotEnabled = false
  var spotColor = Pixel.black
  var solidity: Float = 0
  let kind: Kind
  let target: ChannelPlaneTarget?
  var name = ""
  var channelID: UUID?
  var customLoadSource:SelectionChannelSource?
  var selectionSource:SelectionChannelSource? {customLoadSource ?? channelID.map{.alpha($0)} ?? SelectionChannelSource.choices(in:selectedDocument).first}
  var mode = SelectionMode.replace
  var invert = false
  var options = ChannelDisplayOptions()
  var error: String?
  var title: String { switch kind { case .save:"Save Selection"; case .load:"Load Selection"; case .options:spotEnabled ? "Spot Channel Options":"Channel Options"; case .quickOptions:"Quick Mask Options";case .newSpot:"New Spot Channel" } }
  init(kind: Kind,document: CraftDocument,target: ChannelPlaneTarget?,defaults: ChannelDisplayOptions,sources:[CraftDocument] = [],documentNames:[UUID:String] = [:],colorSettings:ColorSettings = .init()) {
    self.colorSettings=colorSettings
    self.documentNames=documentNames
    self.source=document; self.documents=[document]+sources.filter {$0.id != document.id && $0.width==document.width && $0.height==document.height}
    self.documentID=document.id; self.kind = kind; self.target = kind == .quickOptions ? .quickMask:(kind == .newSpot ? nil:target)
    name = document.suggestedChannelName
    if kind == .load,let saved=documents.first(where:{!SelectionChannelSource.choices(in:$0).isEmpty}) {documentID=saved.id;channelID=saved.alphaChannels?.first?.id}
    if kind != .newSpot,let channel = try? document.channel(self.target ?? .quickMask) { name = channel.name; options = channel.options;spotEnabled=channel.spot != nil;spotColor=channel.spot?.color ?? .black;solidity=channel.spot?.solidity ?? 0 }
    else if kind == .quickOptions { options = defaults }
    if kind == .newSpot {spotEnabled=true;name="Spot Color"}
    if kind == .save {(channelID)=((document.alphaChannels?.count ?? 0)>=CraftDocument.maximumAlphaChannels ? document.alphaChannels?.first(where:{$0.spot == nil})?.id:nil)}
  }
  func command(document: CraftDocument) throws -> Command? {
    switch kind {
    case .newSpot:return .channel(.create(try document.newSpotChannel(name:name,ink:SpotInk(color:spotColor,solidity:solidity))))
    case .save:
      let plane=try AlphaChannel.coverage(source.coverageSelection(),width:source.width,height:source.height,depth:document.depth)
      return .channel(.storeSelection(plane,channelID,channelID == nil ? name:nil,channelID == nil ? .replace:mode))
    case .load:
      guard let selectionSource else {throw CraftError.invalid("Choose a selection source.")}
      return .channel(.loadCoverage(try selectionSource.selection(in:selectedDocument,invert:invert,colorSettings:colorSettings),mode))
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
        Picker("Document",selection:$draft.documentID) {
          ForEach(draft.documents,id:\.id) {Text(draft.displayName(for:$0)).tag($0.id)}
          if draft.kind == .save {Text("New").tag(draft.newDocumentID)}
        }.onChange(of:draft.documentID) {_,_ in
          draft.resetDestination()
        }
        if draft.kind == .load {
          Picker("Channel",selection:Binding(get:{draft.selectionSource},set:{value in
            if case .alpha(let id)=value {draft.channelID=id;draft.customLoadSource=nil}
            else {draft.channelID=nil;draft.customLoadSource=value}
          })) {ForEach(SelectionChannelSource.choices(in:draft.selectedDocument),id:\.self) {source in Text(source.title(in:draft.selectedDocument)).tag(Optional(source))}}
        } else {
          Picker("Channel",selection:$draft.channelID) {
            Text("New").tag(UUID?.none).disabled(!draft.createsDocument && (draft.selectedDocument.alphaChannels?.count ?? 0)>=CraftDocument.maximumAlphaChannels)
            ForEach(draft.createsDocument ? []:(draft.selectedDocument.alphaChannels ?? []).filter {$0.spot == nil}) {Text($0.name).tag(Optional($0.id))}
          }
        }
        if draft.kind == .save && draft.channelID == nil { TextField("Name",text:$draft.name).textFieldStyle(.roundedBorder) }
        Picker("Operation",selection:$draft.mode) {
          Text(draft.kind == .save ? (draft.channelID == nil ? "New Channel":"Replace Channel") : "New Selection").tag(SelectionMode.replace)
          Text(draft.kind == .save ? "Add to Channel":"Add to Selection").tag(SelectionMode.add).disabled(!draft.canCombine)
          Text(draft.kind == .save ? "Subtract from Channel":"Subtract from Selection").tag(SelectionMode.subtract).disabled(!draft.canCombine)
          Text(draft.kind == .save ? "Intersect with Channel":"Intersect with Selection").tag(SelectionMode.intersect).disabled(!draft.canCombine)
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
      if draft.committing {ProgressView("Applying selection…").controlSize(.small)}
      if let error = draft.error { Text(error).foregroundStyle(.red) }
      HStack { Spacer(); Button("Cancel") { store.cancelChannelDialog() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitChannelDialog(draft) }.keyboardShortcut(.defaultAction).disabled(draft.committing || (draft.kind == .load && draft.selectionSource == nil) || (draft.kind == .save && !draft.canSaveDestination)) }
    }.padding(20).frame(width:380)
  }
}
