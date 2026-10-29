import SwiftUI
import PhotoCraftCore

struct FocusAreaControls:View {
  @Bindable var model:SelectMaskWorkspace
  func number(_ key:WritableKeyPath<FocusAreaSettings,Double>,automatic:WritableKeyPath<FocusAreaSettings,Bool>)->Binding<Double>{
    Binding(get:{let p=model.state.focus ?? .init();return p[keyPath:automatic] ? (model.effectiveFocus ?? p)[keyPath:key]:p[keyPath:key]},set:{var next=model.state;next.focus?[keyPath:key]=$0;next.focus?[keyPath:automatic]=false;model.change(next)})
  }
  func flag(_ key:WritableKeyPath<FocusAreaSettings,Bool>)->Binding<Bool>{Binding(get:{model.state.focus?[keyPath:key] ?? false},set:{value in var next=model.state;let previous=next.focus ?? FocusAreaSettings()
    if !value,key == \FocusAreaSettings.autoRange{next.focus?.range=model.effectiveFocus?.range ?? previous.range}
    if !value,key == \FocusAreaSettings.autoNoise{next.focus?.noise=model.effectiveFocus?.noise ?? previous.noise}
    next.focus?[keyPath:key]=value;model.change(next)})}
  var body:some View {
    VStack(alignment:.leading,spacing:16){
      GroupBox("Focus Area"){
        VStack(alignment:.leading,spacing:10){
          HStack{Text("In-Focus Range");Spacer();TextField("In-Focus Range",value:number(\.range,automatic:\.autoRange),format:.number.precision(.fractionLength(0...2))).frame(width:60).textFieldStyle(.roundedBorder)}
          Slider(value:number(\.range,automatic:\.autoRange),in:0...10,onEditingChanged:model.slider)
          Toggle("Auto",isOn:flag(\.autoRange))
          Toggle("Soften Edge",isOn:flag(\.softenEdge))
        }.padding(5)
      }
      GroupBox("Advanced"){
        VStack(alignment:.leading,spacing:10){
          HStack{Text("Image Noise Level");Spacer();TextField("Image Noise Level",value:number(\.noise,automatic:\.autoNoise),format:.number.precision(.fractionLength(0...3))).frame(width:60).textFieldStyle(.roundedBorder)}
          Slider(value:number(\.noise,automatic:\.autoNoise),in:0...1,onEditingChanged:model.slider)
          Toggle("Auto",isOn:flag(\.autoNoise))
        }.padding(5)
      }
      Button("Select and Mask…"){model.refineFocusEdges()}.disabled(!model.canCommit)
      if !model.rendering,let mask=model.refinedMask,mask.bounds==nil{Text("No sharp area was found. Lower In-Focus Range or use the Add brush.").font(.caption).foregroundStyle(.secondary)}
    }
  }
}
