import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

@MainActor @Observable final class GuideDraft:Identifiable {
  enum Kind {case create,edit,layout}
  let id=UUID(),original:CraftDocument
  let kind:Kind
  let targets:[DocumentGuide]
  var axis=DocumentGuide.Axis.vertical
  var position="0 px"
  var color=Pixel(0,1,1,1)
  var layout=GuideLayout()
  var preview=true
  var error:String?
  init(document:CraftDocument,kind:Kind,targets:[DocumentGuide]=[]) {
    original=document;self.kind=kind;self.targets=targets
    if let first=targets.first {axis=first.axis;position="\(first.position) px";color=first.color}
    layout.columns=2;layout.rows=2
  }
  func lines()throws->[DocumentGuide] {
    if kind == .layout {var layout=layout;layout.color=color;return try layout.guides(width:original.width,height:original.height)}
    let p=try GuidePosition.parse(position,extent:Double(axis == .vertical ? original.width:original.height),resolution:original.pixelsPerInch)
    if kind == .create {return [.init(axis:axis,position:p,color:color)]}
    guard let first=targets.first else{throw CraftError.invalid("Select a guide first.")}
    return targets.map {var line=$0;line.position+=p-first.position;line.color=color;if targets.count==1 {line.axis=axis};return line}
  }
  func command()throws->Command {
    let lines=try lines();try CraftDocument.validateGuides(lines)
    return .guides(kind == .edit ? .update(lines):kind == .layout && layout.clearExisting ? .replace(lines):.add(lines))
  }
  var previewLines:[DocumentGuide]? {
    guard preview,let lines=try? lines()else{return nil}
    if kind == .edit {let changed=Dictionary(uniqueKeysWithValues:lines.map{($0.id,$0)});return (original.guides ?? []).map{changed[$0.id] ?? $0}}
    return (kind == .layout && layout.clearExisting ? []:original.guides ?? [])+lines
  }
}

struct GuideGesture {
  let original:CraftDocument
  let lines:[DocumentGuide]
  let start:PathPoint
  let newGuide:Bool
  var current:[DocumentGuide]
  mutating func update(_ point:PathPoint,option:Bool,shift:Bool,tick:Double) {
    current=lines.map {line in
      var result=line
      if option {result.axis = line.axis == .vertical ? .horizontal:.vertical}
      let p=result.axis == .vertical ? point.x:point.y
      let delta=result.axis == .vertical ? point.x-start.x:point.y-start.y
      result.position=newGuide || option ? p:line.position+delta
      if shift,tick>0 {result.position=(result.position/tick).rounded()*tick}
      return result
    }
  }
}

extension EditorStore {
  var canEditGuides:Bool {canSelectComponentTarget && guideDraft==nil && guideGesture==nil && !guidesLocked}
  var selectedGuides:[DocumentGuide] {(document.guides ?? []).filter{selectedGuideIDs.contains($0.id)}}
  var displayedGuides:[DocumentGuide] {
    if let preview=guideDraft?.previewLines{return preview}
    guard let gesture=guideGesture else{return document.guides ?? []}
    if gesture.newGuide{return (document.guides ?? [])+gesture.current}
    let changed=Dictionary(uniqueKeysWithValues:gesture.current.map{($0.id,$0)})
    return (document.guides ?? []).map{changed[$0.id] ?? $0}
  }
  func beginGuides(_ kind:GuideDraft.Kind) {
    guard canEditGuides,kind != .edit || !selectedGuides.isEmpty else{return}
    finishNumericField();finishLayerName();guideDraft=GuideDraft(document:document,kind:kind,targets:selectedGuides);showCanvasGuides=true
  }
  func commitGuides(_ draft:GuideDraft) {
    guard guideDraft === draft,document==draft.original,!guidesLocked,!geometryBusy else{draft.error="The document changed. Reopen the guide dialog.";return}
    do {
      let command=try draft.command();guideDraft=nil;error=nil;perform(command)
      if let failure=error {draft.error=failure;error=nil;guideDraft=draft}
    }catch{draft.error=error.localizedDescription}
  }
  func clearCanvasGuides(selected:Bool=false) {
    guard canEditGuides else{return}
    perform(.guides(.delete(selected ? Set(selectedGuides.map(\.id)):Set((document.guides ?? []).map(\.id)))))
    selectedGuideIDs=[]
  }
  func guidesFromShape() {
    guard canEditGuides,let bounds=activeLayerBounds else{return}
    let lines=[DocumentGuide(axis:.vertical,position:Double(bounds.x)),.init(axis:.vertical,position:Double(bounds.x+bounds.width)),.init(axis:.horizontal,position:Double(bounds.y)),.init(axis:.horizontal,position:Double(bounds.y+bounds.height))]
    perform(.guides(.add(lines)));showCanvasGuides=true
  }
  func guideMoveOffset(_ bounds:IntRect,dx:Double,dy:Double,zoom:Double,modifiers:NSEvent.ModifierFlags)->(Double,Double) {
    guard snappingEnabled,snapToGuides,!modifiers.contains(.command)else{return(dx,dy)}
    return document.snappedToGuides(bounds,dx:dx,dy:dy,tolerance:8/max(zoom,0.000001))
  }
  func configureGuideView(visible:Bool?=nil,locked:Bool?=nil,snap:Bool?=nil,enabled:Bool?=nil) {
    if let visible {showCanvasGuides=visible};if let locked {guidesLocked=locked}
    if let snap {snapToGuides=snap};if let enabled {snappingEnabled=enabled}
  }
}

struct GuideSheet:View {
  @Bindable var store:EditorStore
  @Bindable var draft:GuideDraft
  private var color:Binding<Color> {.init(get:{Color(.sRGB,red:Double(draft.color.r),green:Double(draft.color.g),blue:Double(draft.color.b),opacity:1)},set:{value in if let c=NSColor(value).usingColorSpace(.sRGB){draft.color=Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent),1)}})}
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Text(draft.kind == .layout ? "New Guide Layout":draft.kind == .edit ? "Edit Selected Guides":"New Guide").font(.title2)
      if draft.kind == .layout {
        Grid(alignment:.leading) {
          GridRow {Text("Columns");TextField("Number",value:$draft.layout.columns,format:.number);Text("Gutter");TextField("Column gutter",value:$draft.layout.columnGutter,format:.number)}
          GridRow {Text("Rows");TextField("Number",value:$draft.layout.rows,format:.number);Text("Gutter");TextField("Row gutter",value:$draft.layout.rowGutter,format:.number)}
          GridRow {Text("Top margin");TextField("Top",value:$draft.layout.top,format:.number);Text("Bottom");TextField("Bottom",value:$draft.layout.bottom,format:.number)}
          GridRow {Text("Left margin");TextField("Left",value:$draft.layout.left,format:.number);Text("Right");TextField("Right",value:$draft.layout.right,format:.number)}
        }
        Text("Layout distances are in pixels.").font(.caption).foregroundStyle(.secondary)
        Toggle("Clear Existing Guides",isOn:$draft.layout.clearExisting)
      }else {
        Picker("Orientation",selection:$draft.axis){Text("Horizontal").tag(DocumentGuide.Axis.horizontal);Text("Vertical").tag(DocumentGuide.Axis.vertical)}.disabled(draft.targets.count>1)
        TextField(draft.targets.count>1 ? "First guide position":"Position",text:$draft.position)
        Text("px, %, in, cm, mm, pt or pc").font(.caption).foregroundStyle(.secondary)
      }
      ColorPicker("Color",selection:color,supportsOpacity:false)
      Toggle("Preview",isOn:$draft.preview)
      if let error=draft.error {Text(error).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
      HStack {Spacer();Button("Cancel"){store.guideDraft=nil}.keyboardShortcut(.cancelAction);Button("OK"){store.commitGuides(draft)}.keyboardShortcut(.defaultAction)}
    }.padding(22).frame(width:draft.kind == .layout ? 480:340)
  }
}

@MainActor extension AppDelegate {
  @objc func newCanvasGuide(){store?.beginGuides(.create)}
  @objc func newCanvasGuideLayout(){store?.beginGuides(.layout)}
  @objc func editCanvasGuides(){store?.beginGuides(.edit)}
  @objc func clearAllGuides(){if let store,store.canEditGuides{store.perform(.guides(.clearAll));store.selectedGuideIDs=[]}}
  @objc func clearCanvasGuides(){store?.clearCanvasGuides()}
  @objc func clearSelectedCanvasGuides(){store?.clearCanvasGuides(selected:true)}
  @objc func newGuidesFromShape(){store?.guidesFromShape()}
  @objc func toggleCanvasGuides(){if let store{store.configureGuideView(visible:!store.showCanvasGuides)}}
  @objc func lockCanvasGuides(){if let store{store.configureGuideView(locked:!store.guidesLocked)}}
  @objc func toggleGuideSnap(){if let store{store.configureGuideView(snap:!store.snapToGuides)}}
  @objc func toggleSnapping(){if let store{store.configureGuideView(enabled:!store.snappingEnabled)}}
  func validateGuidesMenu(_ item:NSMenuItem)->Bool? {
    switch item.action {
    case #selector(newCanvasGuide),#selector(newCanvasGuideLayout):return store?.canEditGuides==true
    case #selector(newGuidesFromShape):return store?.canEditGuides==true && store?.activeLayerBounds != nil
    case #selector(editCanvasGuides),#selector(clearSelectedCanvasGuides):return store?.canEditGuides==true && store?.selectedGuides.isEmpty==false
    case #selector(clearAllGuides):return store?.canEditGuides==true && ((store?.document.guides?.isEmpty==false) || store?.document.artboards.contains(where:{$0.artboard?.guides.isEmpty==false})==true)
    case #selector(clearCanvasGuides):return store?.canEditGuides==true && store?.document.guides?.isEmpty==false
    case #selector(toggleCanvasGuides):item.state=store?.showCanvasGuides==true ? .on:.off;return store != nil
    case #selector(lockCanvasGuides):item.state=store?.guidesLocked==true ? .on:.off;return store != nil && store?.guideGesture==nil
    case #selector(toggleGuideSnap):item.state=store?.snapToGuides==true ? .on:.off;return store != nil
    case #selector(toggleSnapping):item.state=store?.snappingEnabled==true ? .on:.off;return store != nil
    default:return nil
    }
  }
}
