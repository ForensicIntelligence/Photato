import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

struct RichTypeControls:View {
  let store:EditorStore
  let style:TypeStyle
  let paragraph:TypeParagraph
  var scope:TypeControlScope = .all
  private var character:TypeCharacterFormatting{style.characterFormatting ?? .init()}
  private func binding<T>(_ key:WritableKeyPath<TypeCharacterFormatting,T>)->Binding<T>{Binding(get:{character[keyPath:key]},set:{value in store.formatType{s,_ in var extra=s.characterFormatting ?? .init();extra[keyPath:key]=value;s.characterFormatting=extra}})}
  var body:some View {
    if scope != .paragraph {
    DisclosureGroup("Character options") {
      HStack{Text("Weight");TextField("Weight",value:binding(\.weight),format:.number).textFieldStyle(.roundedBorder)}
      Toggle("Italic",isOn:binding(\.italic))
      HStack{Toggle("Faux Bold",isOn:binding(\.fauxBold));Toggle("Faux Italic",isOn:binding(\.fauxItalic))}
      Picker("Caps",selection:binding(\.caps)){ForEach(TypeCharacterFormatting.Caps.allCases,id:\.self){Text($0.rawValue).tag($0)}}
      Picker("Kerning",selection:binding(\.kerning)){ForEach(TypeCharacterFormatting.Kerning.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}
      HStack{Text("Manual kern");TextField("Manual kerning",value:binding(\.manualKerning),format:.number).textFieldStyle(.roundedBorder)}
      Toggle("Standard ligatures",isOn:binding(\.ligatures))
      Toggle("Discretionary ligatures",isOn:binding(\.discretionaryLigatures))
      if NSFont(name:style.font,size:12)==nil{Text("The requested font is missing. Source type uses a native fallback while editing; its font identity is retained.").font(.caption).foregroundStyle(.secondary)}
    }
    }
    if scope != .character {
    DisclosureGroup("Paragraph options") {
      Picker("Last line",selection:Binding(get:{paragraph.formatting?.lastLine ?? .left},set:{value in store.formatType(paragraph:true){_,p in var extra=p.formatting ?? .init();extra.lastLine=value;p.formatting=extra}})){ForEach(TypeParagraphFormatting.LastLine.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}.disabled(paragraph.alignment != .justified)
      HStack{Text("Auto leading ×");TextField("Auto leading",value:Binding(get:{paragraph.formatting?.autoLeading ?? 1.2},set:{value in store.formatType(paragraph:true){_,p in var extra=p.formatting ?? .init();extra.autoLeading=value;p.formatting=extra}}),format:.number).textFieldStyle(.roundedBorder)}
    }
    }
    if scope != .paragraph, let type=store.editableType?.typography {
      Picker("Anti-alias",selection:Binding(get:{type.antialiasMode ?? (type.antialias ? .smooth:.none)},set:{store.setTypeAntialias($0)})){ForEach(TypeAntialias.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}
    }
  }
}
extension EditorStore {
  func setTypeAntialias(_ mode:TypeAntialias){
    guard canEditType,var text=editableType else{return};text.typography?.antialiasMode=mode;text.typography?.antialias=mode != .none
    if let draft=typeEditingDraft{draft.content=text;render();return}
    guard let layer=activeLayer else{return};do{perform(try ShapedTextLayout.replacement(layer,content:text,document:document))}catch{self.error=error.localizedDescription}
  }
}

struct FractionalTypeFrameControls:View {
  let store:EditorStore
  let frame:TypeSourceFrame
  private func field(_ title:String,_ key:WritableKeyPath<TypeSourceFrame,Double>)->some View {
    HStack{Text(title);TextField(title,value:Binding(get:{frame[keyPath:key]},set:{value in var changed=frame;changed[keyPath:key]=value;store.setFractionalTypeFrame(changed)}),format:.number).textFieldStyle(.roundedBorder)}
  }
  var body:some View {
    DisclosureGroup("Text frame (px)") {
      field("X",\.x);field("Y",\.y);field("Width",\.width);field("Height",\.height)
    }
  }
}
extension EditorStore {
  func setFractionalTypeFrame(_ frame:TypeSourceFrame) {
    guard canEditType,var text=editableType else{return}
    do {
      try frame.validate();text.typography?.sourceFrame=frame
      text.typography?.kind=frame.kind == .box ? .paragraph:.point
      if frame.kind == .box{text.layoutWidth=Int(ceil(frame.width));text.layoutHeight=Int(ceil(frame.height))}
      else{text.layoutWidth=nil;text.layoutHeight=nil}
      _ = try NativeTextLayout.editingMetrics(text,dpi:document.pixelsPerInch)
      if let draft=typeEditingDraft{draft.content=text;typeEditor?.configureContainer();typeEditor?.superview?.needsLayout=true;render()}
      else if let layer=activeLayer{perform(try ShapedTextLayout.replacement(layer,content:text,document:document))}
    }catch{self.error=error.localizedDescription}
  }
}
