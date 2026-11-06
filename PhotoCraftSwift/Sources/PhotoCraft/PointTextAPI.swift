import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum PointTextAPI {
  static var pointSchema:[String:Any] {BrushAPI.object(["x":["type":"number"],"y":["type":"number"]],required:["x","y"])}
  static var metricSchema:[String:Any] {BrushAPI.object([
    "width":["type":"integer","minimum":1,"maximum":32768],"height":["type":"integer","minimum":1,"maximum":32768],
    "localRasterOrigin":pointSchema,"textKitCropOrigin":pointSchema,"pointAnchored":BrushAPI.flag],
    required:["width","height","localRasterOrigin","textKitCropOrigin","pointAnchored"])}
  static var stateSchema:[String:Any] {BrushAPI.object([
    "layerID":["type":["string","null"],"format":"uuid"],"draft":BrushAPI.flag,"available":BrushAPI.flag,
    "metrics":["anyOf":[["type":"null"],metricSchema]],"error":["type":["string","null"]]],
    required:["layerID","draft","available","metrics","error"])}
  static var capabilities:[String:Any] {[
    "commands":["text.create","text.set"],"state":"textGeometry","stateSchema":stateSchema,
    "coordinates":"Point text with center/right alignment shares one insertion coordinate per hard line. TextKit uses positive virtual line fragments; only final glyph bounds form a raster. localRasterOrigin is the model-local raster offset from that insertion space; textKitCropOrigin is the separate internal drawing/caret offset. Layer transforms and source frames remain authoritative.",
    "native":"Renderer, outlines, native editor container, insertion-point/hit-test conversion and edited-layer frame use the same geometry. Plain left point and paragraph frames retain their previous rendering path. Existing text schemas/commands, document Undo/Actions and native serialization are unchanged.",
    "limits":"Current type raster32768side/16MP,100000UTF16units and existing fonts/style/frame limits remain working bounds, not Photoshop maxima.65536virtual layout width is not an image allocation. Remaining large-type/point-wrap/whitespace/composer/affine-editor and exact Photoshop defaults/pixels/physical-platform fidelity stay open.",
    "adobe":"Existing supported Adobe text edits share native layout. No point-geometry endpoint or unverified proprietary descriptor is invented."]}
  @MainActor static func state(_ store:EditorStore)->[String:Any] {
    let draft=store.typeEditingDraft
    var result:[String:Any]=["layerID":(draft?.layer.id ?? store.document.activeLayerID)?.uuidString as Any? ?? NSNull(),"draft":draft != nil,"available":false,"metrics":NSNull(),"error":NSNull()]
    guard let text=draft?.content ?? store.activeLayer?.typeContent else{return result}
    do {
      let metrics=try draft == nil ? NativeTextLayout.metrics(text,dpi:store.document.pixelsPerInch):NativeTextLayout.editingMetrics(text,dpi:store.document.pixelsPerInch)
      result["available"]=true
      result["metrics"]=["width":metrics.width,"height":metrics.height,
        "localRasterOrigin":["x":metrics.origin.x,"y":metrics.origin.y],"textKitCropOrigin":["x":metrics.layoutOrigin.x,"y":metrics.layoutOrigin.y],
        "pointAnchored":NativeTextLayout.usesPointAnchoring(text) && (draft != nil || text.pristineSourceAppearance == nil)]
    }catch{result["error"]=error.localizedDescription}
    return result
  }
}
