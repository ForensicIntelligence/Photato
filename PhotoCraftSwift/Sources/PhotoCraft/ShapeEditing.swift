import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

extension EditorTool {
  var shapeKind:ShapeGeometry.Kind? {switch self{case .rectangle:.rectangle;case .ellipse:.ellipse;case .triangle:.triangle;case .polygon:.polygon;case .star:.star;case .line:.line;case .customShape:.custom;default:nil}}
}
@MainActor @Observable final class ShapeDraft:Identifiable {
  let id=UUID(),original:CraftDocument,layerID:UUID?
  var definition:ShapeDefinition
  var component=0
  var error:String?
  var preview=true
  init(document:CraftDocument,layer:Layer?,definition:ShapeDefinition){original=document;layerID=layer?.id;self.definition=definition}
}
struct ShapeGesture:Sendable {
  let original:CraftDocument,start:CGPoint,definition:ShapeDefinition,mode:ShapeOutputMode,target:UUID?,operation:PathOperation?
  var end:CGPoint
  var square=false,center=false
  func result()throws->(ShapeDefinition,Transform2D){
    var definition=definition,dx=end.x-start.x,dy=end.y-start.y
    if square{let size=max(abs(dx),abs(dy));dx=(dx<0 ? -1:1)*size;dy=(dy<0 ? -1:1)*size}
    let line=definition.components[0].geometry.kind == .line
    if !line{dx=abs(dx)<1 ? (dx<0 ? -1:1):dx;dy=abs(dy)<1 ? (dy<0 ? -1:1):dy}
    guard abs(dx)+abs(dy)>=1 else{throw CraftError.invalid("Drag to draw a shape.")}
    definition.components[0].geometry.width=abs(dx)*(center ? 2:1);definition.components[0].geometry.height=abs(dy)*(center ? 2:1)
    let x=center ? start.x-dx:start.x,y=center ? start.y-dy:start.y
    let placement=Transform2D.translation(x,y) * .scale(dx<0 ? -1:1,dy<0 ? -1:1)
    return (definition,placement)
  }
}
extension EditorStore {
  var canDrawShapes:Bool {canBeginLayerCreation && isCompositeColorTarget && !editingMask}
  func shapePatterns(_ definition:ShapeDefinition)->[RasterPattern]{
    let ids=Set([definition.fill.pattern?.patternID,definition.stroke.paint.pattern?.patternID].compactMap{$0})
    return patterns.items.filter{ids.contains($0.id) && document.pattern($0.id)==nil}
  }
  func currentShape()throws->ShapeDefinition {
    var value=shapeTemplate
    value.components[0].geometry.kind=tool.shapeKind ?? value.components[0].geometry.kind
    if value.components[0].geometry.kind == .custom {
      if let id=selectedShapeID{value.components[0].geometry.customPath=try shapes.preset(id).path}
      guard value.components[0].geometry.customPath != nil else{throw CraftError.invalid("Define or import a custom shape in Window > Shapes first.")}
    }else{value.components[0].geometry.customPath=nil}
    try value.validate();return value
  }
  func beginShapeProperties(editLayer:Bool){
    guard canDrawShapes else{return}
    do{let layer=editLayer ? activeLayer:nil;guard !editLayer || layer?.shape != nil else{return}
      shapeDraft=ShapeDraft(document:document,layer:layer,definition:try layer?.shape?.editableDefinition ?? currentShape())
    }catch{self.error=error.localizedDescription}
  }
  func refreshShapePreview(){
    guard let draft=shapeDraft else{return};shapePreview=nil;draft.error=nil
    do{try draft.definition.validate();if let id=draft.layerID,draft.preview,draft.original==document{var next=document;try Command.shape(.configure(id,draft.definition,patterns:shapePatterns(draft.definition))).apply(to:&next);shapePreview=next}}catch{draft.error=error.localizedDescription}
    render()
  }
  func cancelShapeProperties(){shapeDraft=nil;shapePreview=nil;render()}
  func commitShapeProperties(_ draft:ShapeDraft){
    guard shapeDraft === draft,draft.original==document else{draft.error="The document changed. Reopen Shape Properties.";return}
    do{try draft.definition.validate();let resources=shapePatterns(draft.definition)
      if let id=draft.layerID{
        var check=document;let command=Command.shape(.configure(id,draft.definition,patterns:resources));try command.apply(to:&check)
        cancelShapeProperties();performGeometry(command)
      }else{shapeTemplate=draft.definition;shapeTemplate.components=Array(draft.definition.components.prefix(1));shapeTemplate.components[0].transform = .identity;shapeTemplate.components[0].operation = .combine;if let selected=EditorTool.allCases.first(where:{$0.shapeKind==shapeTemplate.components[0].geometry.kind}){tool=selected};cancelShapeProperties()}
    }catch{draft.error=error.localizedDescription}
  }
  func finishShapeGesture(){
    guard let gesture=shapeGesture else{return};shapeGesture=nil
    guard gesture.original==document else{return}
    do{let (definition,placement)=try gesture.result();let resources=shapePatterns(definition)
      if let operation=gesture.operation,gesture.mode == .shape{
        guard let target=gesture.target,let layer=document.layers.first(where:{$0.id==target}),layer.shape != nil else{throw CraftError.invalid("Select a shape layer to combine, or choose New Layer.")}
        let component=ShapeComponent(geometry:definition.components[0].geometry,transform:try layer.shapeTransform().inverted()*placement,operation:operation)
        performGeometry(.shape(.append(target,component)))
      }else{performGeometry(label:"Draw Shape",prepare:{original in try ShapeRenderer.creation(definition,name:definition.components[0].geometry.kind.rawValue.capitalized,placement:placement,mode:gesture.mode,target:gesture.target,document:original,patterns:resources)})}
    }catch{self.error=error.localizedDescription}
  }
  func defineShape(name:String)throws->UUID{
    guard canDrawShapes else{throw CraftError.invalid("Finish the current edit before defining a shape.")}
    let path:CGPath
    if let selected=selectedVectorPath{path=try VectorRasterizer.filledPath(selected)}else if let layer=activeLayer,let definition=layer.shape?.editableDefinition{path=try ShapeRenderer.outline(definition)}else{throw CraftError.invalid("Select a closed path or shape layer first.")}
    let preset=ShapePreset(name:name,path:try FrameRenderer.normalized(path).0);try shapes.add(preset);selectedShapeID=preset.id;return preset.id
  }
}
