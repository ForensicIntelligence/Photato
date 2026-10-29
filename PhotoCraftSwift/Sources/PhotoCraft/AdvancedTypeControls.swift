import AppKit
import CoreText
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var currentTypeStyle:TypeStyle {
    if let editor=typeEditor{let r=editor.selectedRange();return NativeTextLayout.styles(r.length>0 ? editor.textStorage!.attributes(at:r.location,effectiveRange:nil):editor.typingAttributes,dpi:document.pixelsPerInch).0}
    return editableType?.typography?.defaultStyle ?? .init()
  }
  func setTypeOrientation(_ orientation:TextTypography.Orientation) {
    guard canEditType,var text=editableType else{return}
    text.typography?.orientation=orientation == .horizontal ? nil:orientation
    do{_ = try NativeTextLayout.metrics(text,dpi:document.pixelsPerInch)
      if let draft=typeEditingDraft{draft.content=text;if let editor=typeEditor{editor.textStorage?.addAttribute(.verticalGlyphForm,value:orientation == .vertical ? 1:0,range:NSRange(location:0,length:editor.string.utf16.count));editor.typingAttributes[.verticalGlyphForm]=orientation == .vertical ? 1:0;editor.configureContainer();editor.superview?.needsLayout=true};typeSelectionRevision += 1}
      else if let id=activeLayer?.id{if let layer=document.layers.first(where:{$0.id==id}){perform(try ShapedTextLayout.replacement(layer,content:text,document:document))}}
    }catch{self.error=error.localizedDescription}
  }
  func setFontFeature(_ tag:String,_ value:Int?) {formatType{s,_ in var options=s.fontOptions ?? .init();options.features.removeAll{$0.tag==tag};if let value{options.features.append(.init(tag,value))};s.fontOptions=options.isEmpty ? nil:options}}
  func setFontAxis(_ id:UInt32,_ value:Double) {formatType{s,_ in var options=s.fontOptions ?? .init();options.variations.removeAll{$0.axis==id};options.variations.append(.init(id,value));s.fontOptions=options}}
  func insertGlyph(font:String,glyph:NativeFonts.Glyph) {
    guard canEditType else{return}
    do{
      var style=currentTypeStyle,paragraph=editableType?.typography?.defaultParagraph ?? .init()
      if let editor=typeEditor{let range=editor.selectedRange();paragraph=NativeTextLayout.styles(range.length>0 ? editor.textStorage!.attributes(at:range.location,effectiveRange:nil):editor.typingAttributes,dpi:document.pixelsPerInch).1}
      else if let text=editableType {let attributed=try NativeTextLayout.attributed(text,dpi:document.pixelsPerInch);if attributed.length>0{(style,paragraph)=NativeTextLayout.styles(attributed.attributes(at:attributed.length-1,effectiveRange:nil),dpi:document.pixelsPerInch)}}
      let replacement=try NativeTextLayout.glyphString(style:style,paragraph:paragraph,font:font,glyph:glyph,dpi:document.pixelsPerInch,orientation:editableType?.typography?.writingOrientation ?? .horizontal),string=replacement.string
      if let editor=typeEditor{let range=editor.selectedRange();if editor.shouldChangeText(in:range,replacementString:string){editor.textStorage?.replaceCharacters(in:range,with:replacement);editor.didChangeText();editor.setSelectedRange(.init(location:range.location+string.utf16.count,length:0));editor.typingAttributes.removeValue(forKey:.glyphInfo);editor.typingAttributes.removeValue(forKey:NSAttributedString.Key("PhotatoGlyphOverride"))}}
      else if let text=editableType,let id=activeLayer?.id{let attributed=NSMutableAttributedString(attributedString:try NativeTextLayout.attributed(text,dpi:document.pixelsPerInch));attributed.append(replacement);let content=try NativeTextLayout.content(attributed,template:text,dpi:document.pixelsPerInch);if let layer=document.layers.first(where:{$0.id==id}){perform(try ShapedTextLayout.replacement(layer,content:content,document:document))}}
    }catch{self.error=error.localizedDescription}
  }
}
struct AdvancedTypeControls:View {
  @Bindable var store:EditorStore
  let style:TypeStyle
  var body:some View {
    Picker("Orientation",selection:Binding(get:{store.editableType?.typography?.writingOrientation ?? .horizontal},set:{store.setTypeOrientation($0)})){Text("Horizontal").tag(TextTypography.Orientation.horizontal);Text("Vertical").tag(TextTypography.Orientation.vertical)}
    DisclosureGroup("OpenType") {
      let available=(try? NativeFonts.availableFeatures(style.font)) ?? []
      ForEach(NativeFonts.features.filter{available.contains($0.tag)},id:\.tag){feature in
        Toggle(feature.name,isOn:Binding(get:{style.fontOptions?.features.first{$0.tag==feature.tag}?.value != 0 && (style.fontOptions?.features.contains{$0.tag==feature.tag}==true || feature.tag=="liga")},set:{store.setFontFeature(feature.tag,$0 ? 1:0)}))
      }
      if available.isEmpty{Text("This font has no supported OpenType controls.").foregroundStyle(.secondary)}
      TextField("Language tag (e.g. ja, ar)",text:Binding(get:{style.fontOptions?.language ?? ""},set:{value in store.formatType{s,_ in var options=s.fontOptions ?? .init();options.language=value.isEmpty ? nil:value;s.fontOptions=options.isEmpty ? nil:options}}))
    }
    let axes=(try? NativeFonts.axes(style.font)) ?? []
    if !axes.isEmpty{DisclosureGroup("Variable font") {ForEach(axes){axis in HStack{Text(axis.name).frame(width:70,alignment:.leading);Slider(value:Binding(get:{style.fontOptions?.variations.first{$0.axis==axis.id}?.value ?? axis.defaultValue},set:{store.setFontAxis(axis.id,$0)}),in:axis.minimum...axis.maximum,onEditingChanged:store.coalesce);Text((style.fontOptions?.variations.first{$0.axis==axis.id}?.value ?? axis.defaultValue).formatted(.number.precision(.fractionLength(2)))).frame(width:45)}}}}
  }
}
struct GlyphPreview:View {
  let font:String,glyph:UInt16
  var body:some View{Canvas{context,size in guard let font=NSFont(name:font,size:36) else{return};var id=glyph;let box=CTFontGetBoundingRectsForGlyphs(font as CTFont,.default,&id,nil,1);guard box.width>0,box.height>0 else{return};let scale=min((size.width-6)/box.width,(size.height-6)/box.height);context.withCGContext{cg in cg.setFillColor(NSColor.labelColor.cgColor);cg.translateBy(x:(size.width-box.width*scale)/2-box.minX*scale,y:(size.height+box.height*scale)/2+box.minY*scale);cg.scaleBy(x:scale,y:-scale);var point=CGPoint.zero;CTFontDrawGlyphs(font as CTFont,&id,&point,1,cg)}}}
}
struct GlyphsPanel:View {
  @Bindable var store:EditorStore
  @State var font=""
  @State var page=0
  @State var glyphs:[NativeFonts.Glyph]=[]
  @State var error:String?
  func load(){do{glyphs=try NativeFonts.glyphs(font,start:page*128+1,count:128);error=nil}catch{self.error=error.localizedDescription}}
  var body:some View{VStack(alignment:.leading){
    Picker("Font",selection:$font){ForEach(NSFontManager.shared.availableFonts.sorted(),id:\.self){Text($0).tag($0)}}.onChange(of:font){_,_ in page=0;load()}
    ScrollView{LazyVGrid(columns:[GridItem(.adaptive(minimum:48))]){ForEach(glyphs){glyph in Button{store.insertGlyph(font:font,glyph:glyph)}label:{GlyphPreview(font:font,glyph:glyph.id).frame(height:44).contentShape(Rectangle())}.buttonStyle(.plain).help("\(glyph.name) · glyph \(glyph.id)\(glyph.unicode.map{" · \($0)"} ?? "")").accessibilityLabel(glyph.name).disabled(!store.canEditType || store.editableType==nil)}}}
    HStack{Button("Previous"){page=max(0,page-1);load()}.disabled(page==0);Text("\(page*128+1)–\(page*128+glyphs.count)");Button("Next"){page += 1;load()}.disabled(glyphs.count<128)}
    Text("Click a glyph to insert at the text cursor, or append to the selected type layer.").font(.caption).foregroundStyle(.secondary)
    if let error{Text(error).foregroundStyle(.red)}
  }.padding(12).frame(minWidth:330,minHeight:380).onAppear{font=store.currentTypeStyle.font;load()}}
}
struct GlyphsPanelRoot:View {
  @Bindable var documents:DocumentWindows
  var body:some View{if let document=documents.activeDocument{GlyphsPanel(store:document.store).id(ObjectIdentifier(document.store))}else{Text("Open a document to use glyphs.").padding(30)}}
}
@MainActor extension AppDelegate {
  @objc func showGlyphs(){
    if glyphsWindow==nil{let panel=FloatingPanelWindow(contentRect:NSRect(x:170,y:170,width:380,height:500),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false);panel.title="Glyphs";panel.isReleasedWhenClosed=false;panel.isFloatingPanel=true;panel.hidesOnDeactivate=true;panel.documents=controller.documentWindows;panel.appearance=NSAppearance(named:.darkAqua);panel.tabbingMode = .disallowed;panel.contentView=NSHostingView(rootView:GlyphsPanelRoot(documents:controller.documentWindows));glyphsWindow=NSWindowController(window:panel)};glyphsWindow?.showWindow(nil)
  }
  @objc func horizontalType(){store?.setTypeOrientation(.horizontal)}
  @objc func verticalType(){store?.setTypeOrientation(.vertical)}
  @objc func toggleTypeFeature(_ sender:NSMenuItem){guard let tag=NativeFonts.features.first(where:{$0.name==sender.title})?.tag,let store else{return};let on=store.currentTypeStyle.fontOptions?.features.first{$0.tag==tag}?.value ?? (tag=="liga" ? 1:0);store.setFontFeature(tag,on==0 ? 1:0)}
}
