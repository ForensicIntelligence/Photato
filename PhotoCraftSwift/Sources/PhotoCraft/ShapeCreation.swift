import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

struct ShapeCreationRequest:Sendable {
  let definition:ShapeDefinition,point:CGPoint,fromCenter:Bool,mode:ShapeOutputMode,target:UUID?,combine:PathOperation?,name:String
  func placement()throws->Transform2D {
    try definition.validate()
    guard point.x.isFinite,point.y.isFinite,abs(point.x)<=1_000_000,abs(point.y)<=1_000_000,
      definition.components.count==1,let part=definition.components.first,part.transform == .identity,
      part.pathOverride==nil else {throw CraftError.invalid("Precise creation needs one parametric shape and a finite point within the coordinate limits.")}
    let g=part.geometry
    return .translation(point.x-(fromCenter ? g.width/2:0),point.y-(fromCenter ? g.height/2:0))
  }
  func command(in document:CraftDocument,patterns:[RasterPattern])throws->Command {
    let placement=try placement()
    if combine != nil {return try combination(in:document,placement:placement)}
    return try ShapeRenderer.creation(definition,name:name,placement:placement,mode:mode,target:target,document:document,patterns:patterns)
  }
  // Keep large Layer temporaries off the common creation call stack. Pixel
  // creation already nests validated engine commands on a cooperative worker.
  @inline(never) private func combination(in document:CraftDocument,placement:Transform2D)throws->Command {
    guard let combine,mode == .shape,let target,let layer=document.layers.first(where:{$0.id==target}),layer.shape != nil else {throw CraftError.invalid("Select a shape layer to combine, or choose New Layer.")}
    return .shape(.append(target,.init(geometry:definition.components[0].geometry,transform:try layer.shapeTransform().inverted()*placement,operation:combine)))
  }
}
@MainActor @Observable final class ShapeCreationDraft:Identifiable {
  let id=UUID(),original:CraftDocument,session:UUID,lifecycle:UUID,revision:Int,tool:EditorTool
  let point:CGPoint,mode:ShapeOutputMode,target:UUID?,combine:PathOperation?,patterns:[RasterPattern]
  var definition:ShapeDefinition
  var fromCenter:Bool
  var linkedCorners:Bool
  var error:String?
  init(store:EditorStore,gesture:ShapeGesture) {
    original=gesture.original;session=store.sessionGeneration;lifecycle=store.layerPanelGeneration;revision=store.shapeRevision;tool=store.tool
    point=gesture.start;mode=gesture.mode;target=gesture.target;combine=gesture.mode == .shape ? gesture.operation:nil
    definition=gesture.definition;fromCenter=gesture.center;patterns=store.shapePatterns(gesture.definition)
    linkedCorners=Set(gesture.definition.components[0].geometry.radii).count==1
  }
  var request:ShapeCreationRequest {
    .init(definition:definition,point:point,fromCenter:fromCenter,mode:mode,target:target,combine:combine,name:definition.components[0].geometry.kind.rawValue.capitalized)
  }
  var valid:Bool {(try? request.placement()) != nil}
  func setLinkedCorners(_ value:Bool) {linkedCorners=value;if value{definition.components[0].geometry.radii=Array(repeating:definition.components[0].geometry.radii[0],count:4)}}
  func setRadius(_ value:Double,corner:Int) {
    guard (0..<4).contains(corner)else{return}
    if linkedCorners {definition.components[0].geometry.radii=Array(repeating:value,count:4)}
    else {definition.components[0].geometry.radii[corner]=value}
  }
}
@MainActor extension EditorStore {
  func beginShapeCreation(_ gesture:ShapeGesture) {
    guard gesture.original==document,canDrawShapes,
      [.rectangle,.ellipse].contains(gesture.definition.components[0].geometry.kind)else{return}
    let draft=ShapeCreationDraft(store:self,gesture:gesture)
    guard draft.valid else{error="The shape template cannot be created precisely.";return}
    shapeCreationEpoch=UUID();shapeCreationDraft=draft
  }
  func cancelShapeCreation(){shapeCreationEpoch=UUID();shapeCreationDraft=nil}
  func commitShapeCreation(_ draft:ShapeCreationDraft) {
    guard shapeCreationDraft === draft,!geometryBusy,draft.valid else{return}
    guard document==draft.original,sessionGeneration==draft.session,layerPanelGeneration==draft.lifecycle,
      shapeRevision==draft.revision,tool==draft.tool else {draft.error="The source or shape settings changed. Cancel and reopen Create Shape.";return}
    let request=draft.request,resources=draft.patterns,epoch=shapeCreationEpoch,settings=workingColorSettings,prepare=shapeCreationPreparation
    shapeCreationDraft=nil
    guard canDrawShapes else{shapeCreationDraft=draft;draft.error="Finish the current edit before creating the shape.";return}
    performPreparedGeometry(label:"Create "+request.name,prepare:{source in try prepare(source,request,resources)},validateCommit:{
      guard self.shapeCreationEpoch==epoch,self.workingColorSettings==settings,self.tool==draft.tool,self.shapeRevision==draft.revision else {throw CraftError.invalid("Shape creation was cancelled or its settings changed.")}
    })
  }
}
