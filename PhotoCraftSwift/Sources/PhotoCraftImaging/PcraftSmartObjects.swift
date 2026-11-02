import Foundation
import PhotoCraftCore

/// Editable originals and per-instance placed appearance. Source cache pixels
/// have already passed through placement, warp and filters in the Rust engine.
enum PcraftSmartObjects {
  struct Decoded {let source:SmartObject;let pixels:Surface}
  @inline(never) static func layer(_ node:PcraftNode,name:String,project:PcraftProject,namespace:Data,parent:CraftDocument,
    budget:inout Int,sources:inout [String:Decoded])throws->Layer {
    let decoded = try original(node, project:project, namespace:namespace, parent:parent, budget:budget, sources:&sources)
    return try assemble(node, name:name, project:project, namespace:namespace, parent:parent, decoded:decoded, budget:&budget)
  }
  // Opening a child must not retain the much larger layer/filter/cache assembly
  // frame for every admitted nesting level on a cooperative worker stack.
  @inline(never) private static func original(_ node:PcraftNode,project:PcraftProject,namespace:Data,parent:CraftDocument,
    budget:Int,sources:inout [String:Decoded])throws->Decoded {
    try node.keys("kind source transform smart_filters cache psd_raw filters_enabled filter_mask warp stack_mode perspective")
    let origin=try node.field("source");try origin.keys("kind file_name blob path")
    guard try origin.field("kind").string()=="embedded" else {
      throw origin.unsupported("Linked Smart Objects need explicit unknown-source geometry and authorized resolution before migration; no file was opened.")
    }
    let fileName=try origin.field("file_name").string(),blob=try origin.field("blob").string()
    guard let bytes=project.blobs[blob],!bytes.isEmpty,bytes.count<=SmartObject.maximumSourceBytes else{throw origin.invalid}
    let mode:ImageStackMode?
    if let stack=node.optional("stack_mode") {
      let name=try stack.string(),key=name.prefix(1).lowercased()+name.dropFirst()
      guard let native=ImageStackMode(rawValue:key) else{throw stack.unsupported("Unknown source stack mode.")};mode=native
    }else{mode=nil}
    let key=blob+"\0"+fileName+"\0"+(mode?.rawValue ?? "")
    let decoded:Decoded
    if let cached=sources[key]{decoded=cached}else{
      guard bytes.count<=budget else{throw origin.unsupported("Embedded originals exceed the remaining import budget.")}
      let child=try SmartObjectIO.decode(bytes,fileName:fileName)
      var (object,pixels)=try SmartObjectIO.embedded(document:child,in:parent,originalData:bytes,fileName:fileName)
      object.sourceID=PcraftImport.identity(namespace,role:"smart-source:"+blob+"\0"+fileName,id:0)
      if let mode{object.stackMode=mode;pixels=try ImageStack.render(child,mode:mode,in:parent)}
      try object.validate();decoded=Decoded(source:object,pixels:pixels);sources[key]=decoded
    }
    return decoded
  }
  @inline(never) private static func assemble(_ node:PcraftNode,name:String,project:PcraftProject,namespace:Data,parent:CraftDocument,
    decoded:Decoded,budget:inout Int)throws->Layer {
    var layer=Layer(name:name,content:.raster(decoded.pixels));layer.smartObject=decoded.source
    let transform=try node.field("transform");try transform.keys("m");let values=try transform.field("m").array().map{try $0.double()}
    guard values.count==6 else{throw transform.invalid}
    let affine=Transform2D(a:values[0],b:values[1],c:values[2],d:values[3],tx:values[4],ty:values[5])
    if let projection=node.optional("perspective") {
      let full=try ProjectiveTransform(projection.array().map{try $0.double()})
      // Rust's full homography overrides its affine approximation. Factor that
      // approximation out for native position/reset controls without placing twice.
      if let inverse=try? affine.inverted() {
        layer.x=Int(floor(affine.tx));layer.y=Int(floor(affine.ty))
        layer.affine = .translation(-Double(layer.x),-Double(layer.y))*affine
        layer.sourceProjection=try full.followed(by:inverse)
      }else{layer.sourceProjection=full}
    }else{
      let full=affine;try full.validated()
      layer.x=Int(floor(full.tx));layer.y=Int(floor(full.ty));layer.affine = .translation(-Double(layer.x),-Double(layer.y))*full
      if layer.affine == .identity{layer.affine=nil}
    }
    if let warp=node.optional("warp"){layer.warp=try warpDefinition(warp)}
    var stack=SmartFilterStack();stack.enabled=try node.optional("filters_enabled")?.boolean() ?? true
    for (index,filter) in try node.field("smart_filters").array().enumerated() {
      try filter.keys("command params blend opacity visible")
      let id=PcraftImport.identity(namespace,role:"smart-filter:"+node.path,id:UInt64(index))
      let command=try filter.field("command").string(),parameters=try filter.field("params")
      let blend=try blendMode(filter.field("blend"))
      let native=try PcraftSmartFilters.convert(command,parameters),visible=try filter.field("visible").boolean(),opacity=try filter.field("opacity").float()
      stack.filters.append(SmartFilter(id:id,filter:native,enabled:visible,opacity:opacity,blendMode:blend))
    }
    if let mask=node.optional("filter_mask") {
      let mapped=try pixelMask(mask,project:project,budget:&budget)
      stack.mask=mapped.0;stack.maskProperties=mapped.1
    }
    try stack.validate();layer.smartFilters=stack
    var cache:Surface?,x=0,y=0
    if let cacheNode=node.optional("cache") {
      try PcraftSamples.validateSchema(cacheNode)
      guard let source=project.surfaces[cacheNode.path],try PcraftSamples.depth(source.sample)==parent.depth else{throw cacheNode.invalid}
      let placed=try PcraftSamples.placed(source,mask:false,budget:&budget);cache=placed.surface;x=placed.x;y=placed.y
    }
    let record:Data?
    if let raw=node.optional("psd_raw") {guard let data=project.blobs[try raw.string()],data.count<=16*1024*1024 else{throw raw.invalid};record=data}else{record=nil}
    // Reference snapshots share immutable values but are conservatively budgeted
    // as independently owned content, matching native archive accounting.
    let retained=2*(decoded.source.data.count+decoded.pixels.allocatedBytes+stack.programBytes+(stack.mask?.allocatedBytes ?? 0))+(record?.count ?? 0)+4096
    guard retained<=budget else{throw node.unsupported("Smart Object source/reference data exceeds the remaining import budget.")};budget-=retained
    layer.importedSmartAppearance=try .init(layer:layer,pixels:cache,x:x,y:y,placedRecord:record)
    return layer
  }
  static func blendMode(_ node:PcraftNode)throws->BlendMode {
    let name=try node.string();guard let mode=BlendMode.allCases.first(where:{$0.rawValue.replacingOccurrences(of:" ",with:"")==name})else{throw node.unsupported("Unsupported Smart Filter blend mode.")};return mode
  }
  static func pixelMask(_ node:PcraftNode,project:PcraftProject,budget:inout Int)throws->(Surface,MaskProperties) {
    try node.keys("surface enabled linked density feather");let field=try node.field("surface");try PcraftSamples.validateSchema(field)
    guard let source=project.surfaces[field.path] else{throw node.invalid}
    let placed=try PcraftSamples.placed(source,mask:true,budget:&budget)
    var properties=MaskProperties();properties.transform = .translation(Double(placed.x),Double(placed.y));properties.outside=placed.outside
    properties.enabled=try node.field("enabled").boolean();properties.linked=try node.field("linked").boolean();properties.density=try node.field("density").float();properties.feather=Double(try node.field("feather").float());try properties.validate()
    return(placed.surface,properties)
  }
  static func warpDefinition(_ node:PcraftNode)throws->WarpDefinition {
    try node.keys("style bend hDistort vDistort vertical bounds mesh")
    let name=try node.field("style").string(),key=name.prefix(1).lowercased()+name.dropFirst()
    guard let style=WarpStyle(rawValue:key) else{throw node.unsupported("Unknown source warp style.")}
    let bounds=try node.field("bounds").array().map{try $0.double()};guard bounds.count==4 else{throw node.invalid}
    var warp=WarpDefinition();warp.style=style;warp.sourceBounds = .init(x:bounds[0],y:bounds[1],width:bounds[2]-bounds[0],height:bounds[3]-bounds[1])
    warp.bend=try node.optional("bend")?.double() ?? 0;warp.horizontalDistortion=try node.optional("hDistort")?.double() ?? 0;warp.verticalDistortion=try node.optional("vDistort")?.double() ?? 0;warp.vertical=try node.optional("vertical")?.boolean() ?? false
    if let mesh=node.optional("mesh") {
      try mesh.keys("us vs points")
      let us=try mesh.field("us").array().map{try $0.double()},vs=try mesh.field("vs").array().map{try $0.double()}
      let points=try mesh.field("points").array().map{point->PathPoint in let values=try point.array().map{try $0.double()};guard values.count==2 else{throw point.invalid};return .init(values[0],values[1])}
      warp.mesh = .init(us:us,vs:vs,points:points)
    }
    try warp.validate();return warp
  }
}
