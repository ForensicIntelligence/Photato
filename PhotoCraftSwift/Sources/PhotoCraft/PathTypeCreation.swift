import AppKit
import PhotoCraftCore
import PhotoCraftImaging

struct PathTypeHit {
  var path:VectorPath
  var fraction:Double
}
struct PathTypePress {
  var hit:PathTypeHit
  var baseline:CraftDocument
  var tool:EditorTool
  var start:CGPoint
}
@MainActor extension EditorStore {
  func typeLayer(at point:CGPoint)->Layer? {
    for layer in document.layers.reversed() where layer.visible && layer.group==nil {
      guard let text=layer.typeContent,let inverse=try?layer.coordinateTransform.inverted(),let metrics=try?NativeTextLayout.metrics(text,dpi:document.pixelsPerInch)else{continue}
      let p=inverse.point(point.x,point.y)
      if p.x>=0,p.y>=0,p.x<Double(metrics.width),p.y<Double(metrics.height){return layer}
    }
    return nil
  }
  func beginTypeOnPath(_ hit:PathTypeHit) {
    guard canBeginLayerCreation,!editingComponent,!editingMask,tool == .text else{return}
    do {
      var text=TextContent(text:"",fontName:fontName,size:fontSize,color:brush.color),type=TextTypography(),geometry=TextGeometry()
      type.defaultStyle.font=fontName;type.defaultStyle.size=fontSize;type.defaultStyle.color=brush.color
      geometry.mode = .path;geometry.path=hit.path;geometry.start=min(0.9998,max(0,hit.fraction))
      try geometry.validate();type.geometry=geometry;text.typography=type
      _=try ShapedTextLayout.pathEditingGeometry(text,dpi:document.pixelsPerInch)
      let layer=Layer(name:"Type",content:.text(text))
      typeEditingDraft=TypeEditingDraft(layer:layer,content:text,baseline:document,isNew:true);render()
    }catch{self.error=error.localizedDescription}
  }
}
extension CraftCanvas {
  var pathTypeHit:PathTypeHit? {
    guard [.text,.verticalText].contains(store.tool),let point=cursorDocumentPoint,store.typeEditingDraft==nil,
      let path=store.selectedVectorPath,path.components.count==1,!path.inverted,store.typeLayer(at:point)==nil,
      let component=path.components.first,component.knots.count>=2 else{return nil}
    if typeBaselinePath != path {typeBaselinePath=path;typeBaseline=try?PathTextBaseline(component)}
    guard let fraction=typeBaseline?.nearestFraction(to:.init(point.x,point.y),tolerance:6/max(0.000001,Double(scale)))else{return nil}
    return .init(path:path,fraction:fraction)
  }
  var pathTypeAvailable:Bool{store.tool == .text && store.canBeginLayerCreation && !store.editingMask && !store.editingComponent}
  func beginPathTypePress(_ event:NSEvent)->Bool {
    guard !spaceHeld,let hit=pathTypeHit else{return false}
    guard pathTypeAvailable else{store.status="Horizontal path typing requires an available RGB type target. Vertical path typing is not implemented yet.";return true}
    pathTypePress = .init(hit:hit,baseline:store.document,tool:store.tool,start:docPoint(event));return true
  }
  func endPathTypePress(_ event:NSEvent)->Bool {
    guard let press=pathTypePress else{return false};pathTypePress=nil
    guard press.baseline==store.document,press.tool==store.tool else{return true}
    let p=docPoint(event)
    guard hypot(p.x-press.start.x,p.y-press.start.y)*scale<=4 else{return true}
    store.beginTypeOnPath(press.hit);synchronizeTypeEditor();return true
  }
}
