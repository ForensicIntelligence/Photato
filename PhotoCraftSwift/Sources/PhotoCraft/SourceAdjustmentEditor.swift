import AppKit
import SwiftUI
import PhotoCraftCore

struct SourceAdjustmentEditor:View {
  @Bindable var store:EditorStore
  let layerID:UUID
  @State private var selectedRows:[String:Int]=[:]
  private var settings:SourceAdjustment? {if case .adjustment(.source(let value))=store.document.layers.first(where:{$0.id==layerID})?.content{return value};return nil}
  private func change(_ edit:(inout SourceAdjustment)->Void) {
    guard var value=settings else {return};edit(&value)
    do {try value.validate();_ = try SourceAdjustmentTransfer(value,depth:store.document.depth);store.setSourceAdjustment(layerID,value)}
    catch {store.error=error.localizedDescription}
  }
  private func title(_ key:String)->String {
    let names=["preserveLuminosity":"Preserve Luminosity","colorize":"Colorize","tetrahedral":"Tetrahedral Interpolation","legacy":"Use Legacy","monochrome":"Monochrome","reverse":"Reverse","dither":"Dither","relative":"Relative","in_black":"Input Black","out_black":"Output Black"]
    return names[key] ?? key.prefix(1).uppercased()+key.dropFirst()
  }
  private func number(_ label:String,_ value:Binding<Float>)->some View {
    HStack {Text(label);Spacer();TextField(label,value:value,format:.number.precision(.fractionLength(0...8))).textFieldStyle(.roundedBorder).monospacedDigit().frame(width:96)}
  }
  private func labels(_ key:String,_ columns:Int,_ kind:SourceAdjustment.Kind)->[String] {
    if kind == .levels {return ["Input Black","Input White","Gamma","Output Black","Output White"]}
    if kind == .curves {return ["Input","Output"]}
    if key=="ranges" {return ["Hue","Saturation","Lightness","Fade In","Full Start","Full End","Fade Out"]}
    if key=="weights" {return ["Reds","Yellows","Greens","Cyans","Blues","Magentas"]}
    if kind == .selectiveColor {return ["Cyan","Magenta","Yellow","Black"]}
    if key=="stops" {return ["Location","Red","Green","Blue"]}
    return Array(["Red","Green","Blue","Constant"].prefix(columns))
  }
  private func rowName(_ group:String,_ i:Int,_ kind:SourceAdjustment.Kind)->String {
    if group=="channels" {return ["Master","Red","Green","Blue","Black"][i]}
    if group=="ranges" {return ["Reds","Yellows","Greens","Cyans","Blues","Magentas"][i]}
    if group=="matrix" {return ["Red Output","Green Output","Blue Output"][i]}
    if kind == .selectiveColor {return ClassicAdjustment.rangeNames[i]}
    return "Point \(i+1)"
  }
  var body:some View {
    if let value=settings {
      VStack(alignment:.leading,spacing:10) {
        Text(value.kind.title).fontWeight(.semibold)
        if value.isOpaque {Text(value.kind == .unsupported ? "This original adjustment is preserved but cannot be evaluated." : "The original profile reference is preserved. Choose a color cube to enable the lookup.").font(.caption).foregroundStyle(.secondary)}
        if let name=value.name {Text(name).font(.caption).textSelection(.enabled)}
        ForEach(value.parameters.keys.sorted().filter{$0 != "size"},id:\.self) {key in
          number(title(key),Binding(get:{settings?.parameters[key] ?? 0},set:{next in change{$0.parameters[key]=next}}))
        }
        ForEach(value.options.keys.sorted(),id:\.self) {key in
          Toggle(title(key),isOn:Binding(get:{settings?.options[key] ?? false},set:{next in change{$0.options[key]=next}}))
        }
        ForEach(value.records.keys.sorted().filter{$0 != "lut"},id:\.self) {key in
          if let rows=value.records[key] {
            VStack(alignment:.leading,spacing:6) {
              Text(title(key)).fontWeight(.medium)
              if rows.isEmpty {Text("Identity").foregroundStyle(.secondary)}
              if rows.count>1 {Picker("Channel or point",selection:Binding(get:{min(selectedRows[key] ?? 0,rows.count-1)},set:{selectedRows[key]=$0})) {ForEach(rows.indices,id:\.self) {i in Text(rowName(key,i,value.kind)).tag(i)}}}
              if !rows.isEmpty {
                let row=min(selectedRows[key] ?? 0,rows.count-1),names=labels(key,rows[row].count,value.kind)
                ForEach(rows[row].indices,id:\.self) {column in
                  number(column<names.count ? names[column]:"Value \(column+1)",Binding(get:{settings?.records[key]?[row][column] ?? 0},set:{next in change{$0.records[key]?[row][column]=next}}))
                }
              }
              if value.kind == .curves || key=="stops" {
                HStack {
                  Button("Add Point") {change{v in if key=="stops" {v.records[key]?.append([1,1,1,1])} else {let input=(v.records[key] ?? []).map{$0[0]}.sorted();let x:Float=input.isEmpty ? 0:input.count==1 ? 1:zip(input,input.dropFirst()).max(by:{$0.1-$0.0 < $1.1-$1.0}).map{($0.0+$0.1)/2} ?? 0.5;v.records[key]?.append([x,x])}}}
                  Button("Remove Point") {let row=min(selectedRows[key] ?? 0,max(0,rows.count-1));change{$0.records[key]?.remove(at:row)}}.disabled(rows.isEmpty)
                }
              }
            }
          }
        }
        if value.kind == .colorLookup {
          Text(value.records["lut"] == nil ? "No color cube" : "\(Int(value.parameters["size"] ?? 0)) × \(Int(value.parameters["size"] ?? 0)) × \(Int(value.parameters["size"] ?? 0)) color cube").font(.caption)
          Button("Choose Color Cube…") {chooseLookup()}
        }
        if value.kind == .blackWhite {
          Toggle("Tint",isOn:Binding(get:{settings?.records["tint"] != nil},set:{enabled in change{if enabled {$0.records["tint"]=[[0.88,0.82,0.7]]} else {$0.records.removeValue(forKey:"tint")}}}))
        }
      }.font(.system(size:11))
    }
  }
  private func chooseLookup() {
    let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
    guard panel.runModal() == .OK,let url=panel.url else {return}
    do {let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max;guard size<=ColorLUT.maximumFileBytes else {throw CraftError.invalid("Color cube exceeds64MiB.")};let lut=try ColorLUTFile.read(Data(contentsOf:url),name:url.lastPathComponent);try lut.validate();guard lut.curve==nil,lut.inputGrid==nil,lut.domainMin==[0,0,0],lut.domainMax==[1,1,1] else {throw CraftError.unsupported("This original lookup requires a uniform normalized3D cube.")};change{$0.parameters["size"]=Float(lut.size);$0.records["lut"]=[lut.values];$0.name=lut.title.isEmpty ? url.lastPathComponent:lut.title}}
    catch {store.error=error.localizedDescription}
  }
}

extension EditorStore {
  func setSourceAdjustment(_ id:UUID,_ value:SourceAdjustment) {
    guard case .adjustment(.source(let old))=document.layers.first(where:{$0.id==id})?.content,old.kind==value.kind else {return}
    perform(.replaceContent(id,.adjustment(.source(value))))
  }
}
