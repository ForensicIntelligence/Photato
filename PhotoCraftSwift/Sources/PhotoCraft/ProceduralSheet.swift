import AppKit
import PhotoCraftCore
import SwiftUI

struct ProceduralSheet:View {
  @Bindable var store:EditorStore
  @Bindable var model:ProceduralWorkspace
  var kind:ProceduralRenderSettings.Kind {model.request.settings.kind}
  var body:some View {
    VStack(spacing:12) {
      HStack {Text(kind.title).font(.headline);Spacer();if model.rendering || model.committing{ProgressView().controlSize(.small)}}
      HStack(alignment:.top,spacing:16) {
        preview.frame(minWidth:400,maxWidth:.infinity,maxHeight:.infinity)
        ScrollView {VStack(alignment:.leading,spacing:12) {
          controls
          Divider()
          Toggle("Render on New Layer",isOn:choice(\.newLayer))
          HStack {
            Button("Randomize") {model.update {value in let seed=UInt32.random(in:.min ... .max);switch kind {case .flame:value.settings.flame.seed=seed;case .tree:value.settings.tree.seed=seed;case .pictureFrame:value.settings.frame.seed=seed}}}
            Button("Reset") {model.update{$0.settings=ProceduralRenderSettings(kind)}}
          }
          seed
        }.padding(.trailing,6)}.frame(width:285).disabled(model.committing)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview)
        Button("−"){model.fit=false;model.zoom=max(0.125,model.zoom/1.5)}
        Button("+"){model.fit=false;model.zoom=min(8,model.zoom*1.5)}
        Button("100%"){model.fit=false;model.zoom=1};Button("Fit"){model.fit=true}
        Button("Undo"){model.undo()}.disabled(model.undoStates.isEmpty || model.committing).keyboardShortcut("z",modifiers:.command)
        Button("Redo"){model.redo()}.disabled(model.redoStates.isEmpty || model.committing).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel"){store.cancelProcedural()}.keyboardShortcut(.cancelAction)
        Button("OK"){store.commitProcedural()}.disabled(!model.ready).keyboardShortcut(.defaultAction)
      }.controlSize(.small)
      if let error=model.error {Text(error).foregroundStyle(.red).font(.caption).fixedSize(horizontal:false,vertical:true)}
    }.padding(16).frame(width:860,height:640)
    .onDisappear {model.close();if store.proceduralWorkspace === model {store.proceduralWorkspace=nil}}
  }
  var preview:some View {
    GeometryReader {g in ScrollView([.horizontal,.vertical]) {
      if let image=model.preview ? model.image:model.originalImage {
        let scale=model.fit ? min((g.size.width-24)/Double(image.width),(g.size.height-24)/Double(image.height)):model.zoom
        Image(decorative:image,scale:1).resizable().interpolation(.none).frame(width:Double(image.width)*scale,height:Double(image.height)*scale)
          .overlay {
            if kind == .tree {
              GeometryReader {area in
                ZStack {
                  Color.clear.contentShape(Rectangle())
                  Circle().stroke(.white,lineWidth:1).frame(width:12,height:12).background(Circle().stroke(.black,lineWidth:3))
                    .position(x:Double(model.request.settings.tree.x)*area.size.width,y:Double(model.request.settings.tree.y)*area.size.height).allowsHitTesting(false)
                }.gesture(DragGesture(minimumDistance:0).onChanged {value in
                  model.beginGesture();model.setTreeBase(.init(value.location.x/area.size.width,value.location.y/area.size.height))
                }.onEnded{_ in model.endGesture()})
              }.disabled(model.committing)
            }
          }.padding(12).frame(minWidth:g.size.width,minHeight:g.size.height)
      }
    }.background(Color(white:0.12)).clipped().accessibilityLabel("\(kind.title) preview")}
  }
  func choice<T>(_ key:WritableKeyPath<ProceduralRenderRequest,T>)->Binding<T> {
    Binding(get:{model.request[keyPath:key]},set:{value in model.update{$0[keyPath:key]=value}})
  }
  func number(_ title:String,_ key:WritableKeyPath<ProceduralRenderRequest,Float>,_ range:ClosedRange<Double>,step:Double=1,multiplier:Double=1)->some View {
    let value=Binding<Double>(get:{Double(model.request[keyPath:key])*multiplier},set:{n in model.update{$0[keyPath:key]=Float(n/multiplier)}})
    return VStack(spacing:4) {
      HStack {Text(title);Spacer();TextField(title,value:value,format:.number.precision(.fractionLength(step<1 ? 1:0))).frame(width:65).textFieldStyle(.roundedBorder)}
      Slider(value:value,in:range,step:step,onEditingChanged:{editing in if editing{model.beginGesture()}else{model.endGesture()}}).accessibilityLabel(title)
    }
  }
  func color(_ title:String,_ key:WritableKeyPath<ProceduralRenderRequest,Pixel>)->some View {
    ColorPicker(title,selection:Binding(get:{let p=model.request[keyPath:key];return Color(red:Double(p.r),green:Double(p.g),blue:Double(p.b),opacity:Double(p.a))},set:{value in
      guard let c=NSColor(value).usingColorSpace(.sRGB) else{return};model.update{$0[keyPath:key]=Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent),Float(c.alphaComponent))}
    }),supportsOpacity:true)
  }
  static func title(_ value:String)->String {value.replacingOccurrences(of:"([a-z])([A-Z])",with:"$1 $2",options:.regularExpression).capitalized}
  @ViewBuilder var controls:some View {
    switch kind {case .flame:flame;case .tree:tree;case .pictureFrame:frame}
  }
  var flame:some View {
    VStack(alignment:.leading,spacing:12) {
      Picker("Path",selection:Binding(get:{model.paths.firstIndex{$0.path==model.request.path} ?? 0},set:{i in let paths=model.paths;guard paths.indices.contains(i) else{return};model.update{$0.path=paths[i].path}})) {
        ForEach(Array(model.paths.enumerated()),id:\.offset){i,value in Text(value.name).tag(i)}
      }
      Picker("Flame Type",selection:choice(\.settings.flame.flameType)){ForEach(FlameSettings.Mode.allCases,id:\.self){Text(Self.title($0.rawValue)).tag($0)}}
      number("Length",\.settings.flame.length,1...1000)
      number("Width",\.settings.flame.width,1...1000)
      number("Angle",\.settings.flame.angle,-180...180)
      number("Interval",\.settings.flame.interval,1...1000)
      Toggle("Randomize Length",isOn:choice(\.settings.flame.randomizeLength))
      Toggle("Adjust Interval for Loops",isOn:choice(\.settings.flame.adjustIntervalForLoops))
      Toggle("Use Custom Color",isOn:choice(\.settings.flame.useCustomColor))
      color("Flame Color",\.settings.flame.color).disabled(!model.request.settings.flame.useCustomColor)
      Divider();Text("Advanced").font(.headline)
      number("Turbulent",\.settings.flame.turbulent,0...100)
      number("Jag",\.settings.flame.jag,0...100)
      number("Opacity",\.settings.flame.opacity,0...100)
      number("Flame Lines",\.settings.flame.flameLines,1...100)
      number("Flame Bottom Alignment",\.settings.flame.flameBottomAlignment,0...100)
      Picker("Flame Style",selection:choice(\.settings.flame.flameStyle)){ForEach(FlameSettings.Style.allCases,id:\.self){Text(Self.title($0.rawValue)).tag($0)}}
      Picker("Flame Shape",selection:choice(\.settings.flame.flameShape)){ForEach(FlameSettings.Shape.allCases,id:\.self){Text(Self.title($0.rawValue)).tag($0)}}
      Toggle("Randomize Shapes",isOn:choice(\.settings.flame.randomizeShapes))
      Picker("Quality",selection:choice(\.settings.flame.quality)){ForEach(0...4,id:\.self){Text(["Draft","Low","Medium","High","Very High"][$0]).tag($0)}}
    }
  }
  var tree:some View {
    VStack(alignment:.leading,spacing:12) {
      Picker("Base Tree Type",selection:choice(\.settings.tree.baseTreeType)){ForEach(Array(TreeSettings.names.enumerated()),id:\.offset){i,name in Text(name).tag(i+1)}}
      Picker("Light Direction",selection:choice(\.settings.tree.lightDirection)){ForEach(1...5,id:\.self){Text(String($0)).tag($0)}}
      number("Leaves Amount",\.settings.tree.leavesAmount,0...100)
      number("Leaves Size",\.settings.tree.leavesSize,0...200)
      number("Branches Height",\.settings.tree.branchesHeight,50...300)
      number("Branches Thickness",\.settings.tree.branchesThickness,50...200)
      Toggle("Default Leaves Color",isOn:choice(\.settings.tree.defaultLeaves))
      color("Leaves Color",\.settings.tree.leavesColor).disabled(model.request.settings.tree.defaultLeaves)
      Toggle("Custom Branch Color",isOn:choice(\.settings.tree.customBranchColor))
      color("Branches Color",\.settings.tree.branchesColor).disabled(!model.request.settings.tree.customBranchColor)
      Toggle("Flat Shading",isOn:choice(\.settings.tree.flatShading))
      Divider();Text("Click or drag in the preview to position the tree.").font(.caption).foregroundStyle(.secondary)
      number("Base X (%)",\.settings.tree.x,0...100,step:0.1,multiplier:100)
      number("Base Y (%)",\.settings.tree.y,0...100,step:0.1,multiplier:100)
      number("Scale (%)",\.settings.tree.size,5...200,step:0.1,multiplier:100)
    }
  }
  var frame:some View {
    VStack(alignment:.leading,spacing:12) {
      Picker("Frame",selection:choice(\.settings.frame.frame)){ForEach(Array(PictureFrameSettings.styles.enumerated()),id:\.offset){i,name in Text(Self.title(name)).tag(i+1)}}
      Picker("Lines",selection:choice(\.settings.frame.lines)){ForEach(1...5,id:\.self){Text(String($0)).tag($0)}}
      number("Margin (%)",\.settings.frame.margin,0...30)
      number("Size",\.settings.frame.size,1...100)
      number("Arrangement",\.settings.frame.arrangement,1...100)
      number("Thickness",\.settings.frame.thickness,1...100)
      number("Fade",\.settings.frame.fade,0...100)
      color("Vine Color",\.settings.frame.vineColor)
      color("Flower Color",\.settings.frame.flowerColor)
      color("Leaf Color",\.settings.frame.leafColor)
    }
  }
  @ViewBuilder var seed:some View {
    switch kind {
    case .flame:TextField("Seed",value:choice(\.settings.flame.seed),format:.number)
    case .tree:TextField("Seed",value:choice(\.settings.tree.seed),format:.number)
    case .pictureFrame:TextField("Seed",value:choice(\.settings.frame.seed),format:.number)
    }
  }
}
