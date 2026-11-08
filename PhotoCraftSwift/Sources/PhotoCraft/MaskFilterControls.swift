import PhotoCraftCore

@MainActor extension EditorStore {
  var currentMaskFilterTarget:MaskFilterTarget? {
    guard let layer=activeLayer,maskEditingLayerID==layer.id else{return nil}
    if smartFilterMaskEditing {return .smartFilterMask}
    return layer.mask == nil ? nil:.layerMask
  }
  func canFilterMask(_ target:MaskFilterTarget,kind:RasterFilter.Kind?=nil)->Bool {
    guard canBeginLayerCreation,!editingComponent,!aiBusy,let id=activeLayer?.id,
      selectedLayerIDs.isEmpty || selectedLayerIDs==[id] else{return false}
    return MaskFiltering.available(document,layerID:id,target:target,kind:kind)
  }
}
enum MaskFilterAPI {
  static var capabilities:[String:Any] {[
    "parameter":"filter.apply target","targets":MaskFilterTarget.allCases.map(\.rawValue),
    "kinds":MaskFiltering.kinds.map(\.rawValue),
    "native":"Existing filter menus/dialogs, captured mask target, Preview/Cancel/commit and Repeat Last Filter. Layer and Smart Filter masks share the same prepared engine. Default API target remains pixels.",
    "samples":"Stored mask rectangle/placement/depth retained. Numeric grayscale has no RGB gamma conversion; inversion is interpreted for displayed gray, while density/feather/enabled/link/exterior remain properties. Selection maps through mask placement. Source color content/Smart Object/filter payloads and other masks are unchanged. Unchanged scalar values retain original sample bits and ignored alpha.",
    "history":"One prepared Undo/Redo transaction and native archive89. Semantic mask-filter Actions recording is not implemented; Actions58 unchanged.",
    "capacity":"Common raster-filter admission and pagedFilterKinds apply to stored mask dimensions. No new logical document cap. Sparse maximum geometry is separate from dense physical memory/disk/performance qualification.",
    "limits":"These eight common filters only; wider grayscale families remain work. Existing stored-raster border/kernel rules apply; exact Photoshop affine radius/exterior/border/rounding/default/random policies and independent output remain unqualified. Vector masks must be rasterized separately. No new Adobe endpoint/descriptor/runtime is invented."] }
}
