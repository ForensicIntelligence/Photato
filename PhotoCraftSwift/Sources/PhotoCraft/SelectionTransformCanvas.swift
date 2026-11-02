import AppKit
import PhotoCraftCore

extension CraftCanvas {
  func selectionTransformHit(_ point:CGPoint,draft:TransformDraft)->Int {
    if let item=draft.handles.enumerated().min(by:{hypot($0.element.x-point.x,$0.element.y-point.y)<hypot($1.element.x-point.x,$1.element.y-point.y)}),hypot(item.element.x-point.x,item.element.y-point.y)*scale<10{return item.offset}
    let p=try? draft.selectionProjection.inverted().point(point.x,point.y)
    if let p,p.x>=Double(draft.bounds.x),p.y>=Double(draft.bounds.y),p.x<=Double(draft.bounds.x+draft.bounds.width),p.y<=Double(draft.bounds.y+draft.bounds.height){return -1}
    return 8
  }
  func selectionTransformMenu(for event:NSEvent)->NSMenu? {
    guard store.transformDraft?.selection == true,store.transformDraft?.movingPixels != true else{return nil}
    let menu=NSMenu()
    for mode in SelectionTransformMode.allCases {let enabled=store.transformDraft?.supportsSelectionMode(mode) != false;let item=NSMenuItem(title:mode.rawValue,action:enabled ? #selector(selectionTransformModeMenu(_:)):nil,keyEquivalent:"");item.target=self;item.representedObject=mode.rawValue;item.state=store.transformDraft?.selectionMode == mode ? .on:.off;item.isEnabled=enabled;if !enabled{item.toolTip="Projective transforms for this target are not implemented yet."};menu.addItem(item)}
    let warp=NSMenuItem(title:"Warp",action:nil,keyEquivalent:"");warp.isEnabled=false;warp.toolTip="Warp is not available for this transform target yet.";menu.addItem(warp)
    menu.addItem(.separator());for (title,tag) in [("Rotate 180°",180),("Rotate 90° Clockwise",90),("Rotate 90° Counter Clockwise",-90),("Flip Horizontal",1000),("Flip Vertical",1001)] {let item=NSMenuItem(title:title,action:#selector(selectionTransformTurnMenu(_:)),keyEquivalent:"");item.target=self;item.tag=tag;menu.addItem(item)}
    return menu
  }
  @objc func selectionTransformModeMenu(_ item:NSMenuItem){if let value=item.representedObject as? String,let mode=SelectionTransformMode(rawValue:value){store.chooseSelectionTransformMode(mode);refreshToolCursor()}}
  @objc func selectionTransformTurnMenu(_ item:NSMenuItem){store.transformLayer(angle:abs(item.tag)<1000 ? Double(item.tag):0,horizontal:item.tag==1000,vertical:item.tag==1001);refreshToolCursor()}
}