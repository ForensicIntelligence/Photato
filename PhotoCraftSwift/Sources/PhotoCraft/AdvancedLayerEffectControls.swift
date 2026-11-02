import AppKit
import SwiftUI
import PhotoCraftCore

/// Standard native controls; no custom pointer/modifier gesture or shortcut.
struct AdvancedLayerEffectControls:View {
  @Binding var effect:LayerEffect
  let document:CraftDocument
  func advanced<T>(_ key:WritableKeyPath<LayerEffectAdvanced,T>,_ fallback:T)->Binding<T> {
    Binding(get:{effect.advanced?[keyPath:key] ?? fallback},set:{value in var a=effect.advanced ?? .init();a[keyPath:key]=value;effect.advanced=a})
  }
  private func number(_ title:String,_ binding:Binding<Float>,_ bounds:ClosedRange<Double>,percent:Bool=false)->some View {
    let value=Binding<Double>(get:{Double(binding.wrappedValue)*(percent ? 100:1)},set:{binding.wrappedValue=Float($0/(percent ? 100:1))})
    return HStack{Text(title).frame(width:110,alignment:.leading);Slider(value:value,in:bounds).accessibilityLabel(title);TextField(title,value:value,format:.number.precision(.fractionLength(0...4))).frame(width:75).textFieldStyle(.roundedBorder)}
  }
  private func color(_ title:String,_ binding:Binding<Pixel>)->some View {
    ColorPicker(title,selection:Binding(get:{let p=binding.wrappedValue;return Color(red:Double(p.r),green:Double(p.g),blue:Double(p.b))},set:{value in guard let c=NSColor(value).usingColorSpace(.sRGB)else{return};binding.wrappedValue=Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent),binding.wrappedValue.a)}),supportsOpacity:false)
  }
  private var paint:Binding<EffectPaint> {Binding(get:{effect.advanced?.paint ?? EffectPaint(.color)},set:{value in var a=effect.advanced ?? .init();a.paint=value;effect.advanced=a})}
  @ViewBuilder var body:some View {
    if let a=effect.advanced {
      Divider()
      if [.dropShadow,.innerShadow].contains(effect.kind) {
        EffectContourControls(title:"Contour",contour:advanced(\.contour,.init()))
        if effect.kind == .dropShadow {Toggle("Layer Knocks Out Drop Shadow",isOn:advanced(\.knocksOut,true))}
      }
      if [.innerGlow,.outerGlow].contains(effect.kind) {
        Picker("Technique",selection:advanced(\.glowTechnique,.softer)){ForEach(LayerEffectAdvanced.GlowTechnique.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}
        if effect.kind == .innerGlow {Picker("Source",selection:advanced(\.glowSource,.edge)){ForEach(LayerEffectAdvanced.GlowSource.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}}
        number("Range (%)",advanced(\.range,1),0...100,percent:true)
        EffectContourControls(title:"Contour",contour:advanced(\.contour,.init()))
      }
      if [.stroke,.innerGlow,.outerGlow].contains(effect.kind) {
        Picker("Fill Type",selection:Binding(get:{paint.wrappedValue.kind},set:{kind in switch kind{case .color:paint.wrappedValue=EffectPaint(.color);case .gradient:paint.wrappedValue=EffectPaint(.gradient,gradient:.init());case .pattern:paint.wrappedValue=EffectPaint(.pattern,pattern:EffectPattern(patternID:document.patterns?.first?.id))}})){ForEach(EffectPaint.Kind.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}
      }
      if a.paint?.kind == .gradient {
        EffectGradientControls(gradient:Binding(get:{paint.wrappedValue.gradient ?? .init()},set:{value in var p=paint.wrappedValue;p.gradient=value;paint.wrappedValue=p}))
      }
      if a.paint?.kind == .pattern {
        EffectPatternControls(pattern:Binding(get:{paint.wrappedValue.pattern ?? .init()},set:{value in var p=paint.wrappedValue;p.pattern=value;paint.wrappedValue=p}),patterns:document.patterns ?? [])
      }
      if effect.kind == .satin {Toggle("Invert",isOn:advanced(\.satinInverted,false));EffectContourControls(title:"Contour",contour:advanced(\.contour,.init()))}
      if effect.kind == .bevelEmboss {
        Picker("Style",selection:advanced(\.bevelStyle,.innerBevel)){ForEach(LayerEffectAdvanced.BevelStyle.allCases,id:\.self){Text(label($0.rawValue)).tag($0)}}
        Picker("Technique",selection:advanced(\.bevelTechnique,.smooth)){ForEach(LayerEffectAdvanced.BevelTechnique.allCases,id:\.self){Text(label($0.rawValue)).tag($0)}}
        Toggle("Direction Up",isOn:advanced(\.directionUp,true))
        if !effect.useGlobalLight {number("Light Altitude",advanced(\.altitude,30),0...90)}
        Picker("Highlight Mode",selection:advanced(\.highlightBlendMode,.screen)){ForEach(BlendMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}
        Picker("Shadow Mode",selection:advanced(\.shadowBlendMode,.multiply)){ForEach(BlendMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}
        EffectContourControls(title:"Gloss Contour",contour:advanced(\.glossContour,.init()))
        Toggle("Bevel Contour",isOn:Binding(get:{effect.advanced?.bevelContour != nil},set:{enabled in effect.advanced?.bevelContour=enabled ? EffectBevelContour():nil}))
        if a.bevelContour != nil {
          EffectContourControls(title:"Bevel Contour",contour:Binding(get:{effect.advanced?.bevelContour?.contour ?? .init()},set:{effect.advanced?.bevelContour?.contour=$0}))
          number("Contour Range",Binding(get:{effect.advanced?.bevelContour?.range ?? 0.5},set:{effect.advanced?.bevelContour?.range=$0}),0...100,percent:true)
        }
        Toggle("Texture",isOn:Binding(get:{effect.advanced?.texture != nil},set:{enabled in effect.advanced?.texture=enabled ? EffectBevelTexture(pattern:EffectPattern(patternID:document.patterns?.first?.id)):nil}))
        if a.texture != nil {
          EffectPatternControls(pattern:Binding(get:{effect.advanced?.texture?.pattern ?? .init()},set:{effect.advanced?.texture?.pattern=$0}),patterns:document.patterns ?? [])
          number("Texture Depth (%)",Binding(get:{effect.advanced?.texture?.depth ?? 1},set:{effect.advanced?.texture?.depth=$0}),-1000...1000,percent:true)
          Toggle("Invert Texture",isOn:Binding(get:{effect.advanced?.texture?.inverted ?? false},set:{effect.advanced?.texture?.inverted=$0}))
        }
      }
      if a.noise != 0 || a.jitter != 0 || a.antiAlias {Text("Source noise, jitter and anti-alias settings are retained; these options are not yet active.").font(.caption).foregroundStyle(.secondary)}
    }
  }
  private func label(_ name:String)->String {name.replacingOccurrences(of:"([a-z])([A-Z])",with:"$1 $2",options:.regularExpression).capitalized}
}

struct EffectContourControls:View {
  let title:String
  @Binding var contour:EffectContour
  var body:some View {
    DisclosureGroup(title) {
      TextField("Name",text:$contour.name)
      if contour.points.isEmpty {Text("Linear").foregroundStyle(.secondary)}
      LazyVStack {
        ForEach(contour.points.indices,id:\.self){i in
          HStack {
            Text("\(i+1)").frame(width:24)
            coordinate("Input",i,0);coordinate("Output",i,1)
            Button("Remove"){guard contour.points.indices.contains(i)else{return};contour.points.remove(at:i)}.buttonStyle(.borderless)
          }
        }
      }
      HStack{Button("Add Point"){contour.points.append([0.5,0.5]);contour.points.sort{$0[0]<$1[0]}}.disabled(contour.points.count>=256);Button("Linear"){contour=EffectContour()}}
    }
  }
  private func coordinate(_ title:String,_ i:Int,_ c:Int)->some View {
    TextField(title,value:Binding(get:{contour.points.indices.contains(i) ? contour.points[i][c]:0},set:{if contour.points.indices.contains(i){contour.points[i][c]=$0}}),format:.number.precision(.fractionLength(0...5))).textFieldStyle(.roundedBorder).accessibilityLabel("\(self.title) point \(i+1) \(title)")
  }
}

struct EffectPatternControls:View {
  @Binding var pattern:EffectPattern
  let patterns:[RasterPattern]
  var body:some View {
    Picker("Pattern",selection:Binding(get:{pattern.patternID ?? ""},set:{pattern.patternID=$0.isEmpty ? nil:$0})) {
      Text(pattern.sourceName.map{"Unresolved: \($0)"} ?? "Choose a Pattern").tag("")
      ForEach(patterns){Text($0.displayName).tag($0.id)}
    }
    if pattern.patternID==nil {Text("No artwork is bound. Choose an existing document pattern to activate this effect.").font(.caption).foregroundStyle(.secondary)}
    HStack{Text("Scale (%)");TextField("Scale",value:Binding(get:{Double(pattern.scale)*100},set:{pattern.scale=Float($0/100)}),format:.number.precision(.fractionLength(0...4)))}
    HStack{Text("Angle");TextField("Angle",value:$pattern.angle,format:.number.precision(.fractionLength(0...4)))}
    Toggle("Link with Layer",isOn:$pattern.linked)
    HStack{Text("Phase");TextField("X",value:$pattern.phase.x,format:.number.precision(.fractionLength(0...4)));TextField("Y",value:$pattern.phase.y,format:.number.precision(.fractionLength(0...4)))}
  }
}

struct EffectGradientControls:View {
  @Binding var gradient:EffectGradient
  var body:some View {
    Picker("Gradient Style",selection:$gradient.placement.style){ForEach(GradientStyle.allCases,id:\.self){Text($0.rawValue).tag($0)}}
    HStack{Text("Angle");TextField("Angle",value:$gradient.placement.angle,format:.number.precision(.fractionLength(0...4)))}
    HStack{Text("Scale (%)");TextField("Scale",value:Binding(get:{Double(gradient.placement.scale)*100},set:{gradient.placement.scale=Float($0/100)}),format:.number.precision(.fractionLength(0...4)))}
    HStack{Text("Offset");TextField("X",value:$gradient.placement.offsetX,format:.number.precision(.fractionLength(0...4)));TextField("Y",value:$gradient.placement.offsetY,format:.number.precision(.fractionLength(0...4)))}
    Toggle("Reverse",isOn:$gradient.placement.reverse)
    DisclosureGroup("Color Stops") {
      LazyVStack{ForEach(gradient.stops.indices,id:\.self){i in HStack {
        TextField("Position",value:Binding(get:{gradient.stops.indices.contains(i) ? gradient.stops[i].location:0},set:{if gradient.stops.indices.contains(i){gradient.stops[i].location=$0}}),format:.number.precision(.fractionLength(0...5))).frame(width:75)
        ColorPicker("Color",selection:Binding(get:{let c=gradient.stops.indices.contains(i) ? gradient.stops[i].color:.black;return Color(red:Double(c.r),green:Double(c.g),blue:Double(c.b))},set:{value in guard gradient.stops.indices.contains(i),let c=NSColor(value).usingColorSpace(.sRGB)else{return};gradient.stops[i].color=Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent),gradient.stops[i].color.a)}),supportsOpacity:false)
        Button("Remove"){if gradient.stops.indices.contains(i){gradient.stops.remove(at:i)}}.buttonStyle(.borderless)
      }}}
      Button("Add Color Stop"){gradient.stops.append(.init(0.5,.white));gradient.stops.sort{$0.location<$1.location}}.disabled(gradient.stops.count>=4096)
    }
    DisclosureGroup("Opacity Stops") {
      LazyVStack{ForEach(gradient.opacityStops.indices,id:\.self){i in HStack {
        TextField("Position",value:Binding(get:{gradient.opacityStops.indices.contains(i) ? gradient.opacityStops[i][0]:0},set:{if gradient.opacityStops.indices.contains(i){gradient.opacityStops[i][0]=$0}}),format:.number.precision(.fractionLength(0...5)))
        TextField("Opacity",value:Binding(get:{gradient.opacityStops.indices.contains(i) ? gradient.opacityStops[i][1]:1},set:{if gradient.opacityStops.indices.contains(i){gradient.opacityStops[i][1]=$0}}),format:.number.precision(.fractionLength(0...5)))
        Button("Remove"){if gradient.opacityStops.indices.contains(i){gradient.opacityStops.remove(at:i)}}.buttonStyle(.borderless)
      }}}
      Button("Add Opacity Stop"){gradient.opacityStops.append([0.5,1]);gradient.opacityStops.sort{$0[0]<$1[0]}}.disabled(gradient.opacityStops.count>=4096)
    }
    Text("Stops use positions and opacity from0 to1. Color-stop alpha, align and dither are retained; they are not active in this source effect renderer.").font(.caption).foregroundStyle(.secondary)
  }
}
