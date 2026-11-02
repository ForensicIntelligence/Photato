import AppKit
import PhotoCraftCore
import SwiftUI
import UniformTypeIdentifiers

struct ColorRangeSheet:View {
  @Bindable var store:EditorStore
  @Bindable var model:ColorRangeWorkspace
  func number(_ title:String,_ key:WritableKeyPath<ColorRangeSettings,Double>,_ range:ClosedRange<Double>)->some View {
    VStack(spacing:5) {
      HStack { Text(title);Spacer();TextField(title,value:Binding(get:{model.settings[keyPath:key]},set:{var s=model.settings;s[keyPath:key]=$0;model.change(s)}),format:.number.precision(.fractionLength(0...1))).frame(width:60).textFieldStyle(.roundedBorder) }
      Slider(value:Binding(get:{model.settings[keyPath:key]},set:{var s=model.settings;s[keyPath:key]=$0;model.change(s)}),in:range).accessibilityLabel(title)
    }
  }
  func presets(save:Bool) {
    do {
      if save {
        let data=try model.settings.presetData(),panel=NSSavePanel();panel.allowedContentTypes=[.json];panel.nameFieldStringValue="Color Range.json"
        if panel.runModal() == .OK,let url=panel.url {try data.write(to:url,options:.atomic)}
      }else{
        let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false
        if panel.runModal() == .OK,let url=panel.url {let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0;guard size<=131_072 else {throw CraftError.invalid("Color Range preset exceeds 128 KiB.")};model.load(try Data(contentsOf:url,options:.mappedIfSafe))}
      }
    }catch{model.error=error.localizedDescription}
  }
  var body:some View {
    VStack(spacing:12) {
      HStack {Text("Color Range").font(.headline);Spacer();if model.loading || model.rendering || model.committing {ProgressView().controlSize(.small)}}
      HStack(alignment:.top,spacing:18) {
        ColorRangeCanvas(model:model,thumbnail:false).frame(width:490,height:480).clipped()
        VStack(alignment:.leading,spacing:12) {
          Picker("Select",selection:Binding(get:{model.settings.kind},set:{var s=model.settings;s.kind=$0;model.change(s)})) {
            ForEach(ColorRangeSettings.Kind.allCases,id:\.self) {Text($0.title).tag($0)}
          }
          number("Fuzziness",\.fuzziness,0...200)
          if model.settings.kind == .sampled {
            Toggle("Localized Color Clusters",isOn:Binding(get:{model.settings.localized},set:model.setLocalized))
            if model.settings.localized {number("Range (%)",\.range,0...100)}
            Picker("Eyedropper",selection:$model.sampler) {
              Text("Sample").tag(ColorRangeSampler.sample)
              Text("Add").tag(ColorRangeSampler.add)
              Text("Subtract").tag(ColorRangeSampler.subtract)
            }.pickerStyle(.segmented).help("Sample · Add to sample · Subtract from sample")
            Text("Shift adds · Option subtracts").font(.caption).foregroundStyle(.secondary)
          }
          if [.highlights,.midtones].contains(model.settings.kind) {number("Minimum",\.minimum,0...model.settings.maximum)}
          if [.shadows,.midtones].contains(model.settings.kind) {number("Maximum",\.maximum,model.settings.minimum...255)}
          ColorRangeCanvas(model:model,thumbnail:true).frame(height:130).clipped()
          Picker("Preview",selection:$model.showImage) {Text("Selection").tag(false);Text("Image").tag(true)}.pickerStyle(.radioGroup)
          Toggle("Invert",isOn:Binding(get:{model.settings.invert},set:{var s=model.settings;s.invert=$0;model.change(s)}))
          HStack {Button("Load…"){presets(save:false)};Button("Save…"){presets(save:true)}}
        }.frame(width:260).disabled(!model.ready)
      }
      HStack {Picker("Selection Preview",selection:$model.preview) {ForEach(ColorRangePreview.allCases,id:\.self){Text($0.rawValue).tag($0)}}.frame(width:300).onChange(of:model.preview){_,_ in model.refresh()};Spacer();Text("⌘ toggles the preview").font(.caption).foregroundStyle(.secondary)}
      if let error=model.error {Text(error).foregroundStyle(.red).font(.caption).frame(maxWidth:.infinity,alignment:.leading)}
      HStack {Button("Reset"){model.reset()}.disabled(!model.ready);Spacer();Button("Cancel"){store.cancelColorRange()}.keyboardShortcut(.cancelAction);Button("OK"){store.commitColorRange()}.keyboardShortcut(.defaultAction).disabled(!model.canCommit)}
    }.padding(20).frame(width:810).background(Color(nsColor:.windowBackgroundColor)).onDisappear {model.close()}
  }
}

struct ColorRangeCanvas:NSViewRepresentable {
  @Bindable var model:ColorRangeWorkspace
  var thumbnail:Bool
  func makeNSView(context:Context)->ColorRangeCanvasView {let view=ColorRangeCanvasView();view.model=model;view.thumbnail=thumbnail;return view}
  func updateNSView(_ view:ColorRangeCanvasView,context:Context) {
    _=model.previewImage;_=model.selectionImage;_=model.showImage;_=model.sampler;_=model.settings.kind;_=model.loading;_=model.committing
    view.model=model;view.thumbnail=thumbnail;view.needsDisplay=true;view.refreshToolCursor()
  }
}
@MainActor final class ColorRangeCanvasView:ModifierCursorView {
  weak var model:ColorRangeWorkspace?
  var thumbnail=false
  var capturedSampler:ColorRangeSampler?
  override var isFlipped:Bool {true}
  override var acceptsFirstResponder:Bool {true}
  override var toolCursor:ToolCursor {
    guard let model,model.ready,model.settings.kind == .sampled else{return .arrow}
    return ToolCursor.colorRange(capturedSampler ?? ToolCursor.colorRangeSampler(model.sampler,modifiers:cursorModifiers))
  }
  override func updateCursorModifiers(_ flags:NSEvent.ModifierFlags) {
    let changed=cursorModifiers.contains(.command) != flags.contains(.command)
    super.updateCursorModifiers(flags);if changed {needsDisplay=true}
  }
  override func clearCursorInput() {super.clearCursorInput();capturedSampler=nil;needsDisplay=true}
  var image:CGImage? {
    guard let m=model else{return nil}
    if thumbnail {return m.showImage != cursorModifiers.contains(.command) ? m.sourceImage:m.selectionImage}
    return cursorModifiers.contains(.command) ? m.selectionImage:m.previewImage ?? m.sourceImage
  }
  var imageRect:CGRect {
    guard let image else{return .zero};let scale=min(max(1,bounds.width-12)/Double(image.width),max(1,bounds.height-12)/Double(image.height))
    let size=CGSize(width:Double(image.width)*scale,height:Double(image.height)*scale)
    return CGRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2,width:size.width,height:size.height)
  }
  override func draw(_ dirtyRect:NSRect) {
    NSColor(calibratedWhite:0.12,alpha:1).setFill();bounds.fill()
    if let image {NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)).draw(in:imageRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])}
  }
  func sample(_ event:NSEvent) {
    guard let model,let mode=capturedSampler else{return}
    let p=convert(event.locationInWindow,from:nil),r=imageRect
    guard r.contains(p),r.width>0,r.height>0 else{return}
    model.sample(x:(p.x-r.minX)/r.width*Double(model.original.width),y:(p.y-r.minY)/r.height*Double(model.original.height),mode:mode)
  }
  override func mouseDown(with event:NSEvent) {
    beginCursorGesture(event);guard let model,model.ready,model.settings.kind == .sampled else{return}
    window?.makeFirstResponder(self);capturedSampler=ToolCursor.colorRangeSampler(model.sampler,modifiers:event.modifierFlags);sample(event);refreshToolCursor()
  }
  override func mouseDragged(with event:NSEvent) {updateCursorModifiers(event.modifierFlags);sample(event)}
  override func mouseUp(with event:NSEvent) {capturedSampler=nil;endCursorGesture(event)}
}