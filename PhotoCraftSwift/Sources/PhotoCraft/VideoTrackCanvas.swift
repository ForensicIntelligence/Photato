import AppKit
import SwiftUI
import PhotoCraftCore

struct VideoTrackRow:Identifiable {
  let layer:Layer
  let clips:[Layer]
  var audio:TimelineAudioTrack? = nil
  var id:UUID{layer.id}
  var groupID:UUID?{layer.group?.videoStartTime == nil ? nil:layer.id}
  static func rows(_ document:CraftDocument)->[Self] {
    var result:[Self]=[]
    func visit(_ layer:Layer) {
      if layer.group?.videoStartTime != nil {result.append(.init(layer:layer,clips:document.children(of:layer.id)));return}
      if layer.isGroup,layer.videoTiming == nil {
        for child in document.children(of:layer.id){visit(child)}
      }else{result.append(.init(layer:layer,clips:[layer]))}
    }
    for layer in document.children(of:nil).reversed(){visit(layer)}
    for track in document.videoTimeline?.audioTracks ?? [] {
      var row=Layer(name:track.name,content:.fill(.clear));row.id=track.id
      result.append(.init(layer:row,clips:[],audio:track))
    }
    return result
  }
}
struct VideoTrackLayout {
  static let labelWidth:CGFloat=172,header:CGFloat=44,rowHeight:CGFloat=42
  let document:CraftDocument
  let pixelsPerSecond:Double
  var rows:[VideoTrackRow]{VideoTrackRow.rows(document)}
  var duration:Double{document.videoTimeline.map{Double($0.durationFrames)/$0.frameRate} ?? 1}
  func interval(_ layer:Layer)->VideoLayerTiming{layer.videoInterval ?? .init(startTime:0,duration:duration)}
  func visibleRect(_ timing:VideoLayerTiming,row:Int,inset:CGFloat,height:CGFloat)->NSRect {
    let start=max(0,timing.startTime),end=min(duration,timing.startTime+timing.duration)
    guard end>start else{return .zero}
    return NSRect(x:Self.labelWidth+start*pixelsPerSecond,y:Self.header+CGFloat(row)*Self.rowHeight+inset,width:(end-start)*pixelsPerSecond,height:height)
  }
  func rect(_ layer:Layer,row:Int)->NSRect {visibleRect(interval(layer),row:row,inset:6,height:30)}
  func audioRect(_ clip:TimelineAudioClip,row:Int)->NSRect {visibleRect(.init(startTime:clip.startTime,duration:clip.duration),row:row,inset:6,height:30)}
  func transitionRect(_ transition:VideoTransition,row:Int)->NSRect? {
    guard let time=transition.interval(in:document) else{return nil}
    let rect=visibleRect(time,row:row,inset:9,height:24)
    return rect.isEmpty ? nil:rect
  }
  func frame(at x:CGFloat)->Int {
    guard let timeline=document.videoTimeline else{return 0}
    return min(timeline.durationFrames-1,max(0,Int(((x-Self.labelWidth)/pixelsPerSecond*timeline.frameRate).rounded())))
  }
  func snapped(_ delta:CGFloat)->Double {
    let rate=document.videoTimeline?.frameRate ?? 24
    return (Double(delta)/pixelsPerSecond*rate).rounded()/rate
  }
}
extension EditorStore {
  func trimVideoClip(_ id:UUID,leading:Bool,seconds:Double)throws->VideoCommand {
    guard let layer=document.layers.first(where:{$0.id==id}),let timeline=document.videoTimeline else{throw CraftError.invalid("Clip no longer exists.")}
    let interval=layer.videoInterval ?? .init(startTime:0,duration:Double(timeline.durationFrames)/timeline.frameRate)
    let end=Double(timeline.durationFrames)/timeline.frameRate
    let seconds=seconds+(leading ? max(0,interval.startTime)-interval.startTime : min(end,interval.startTime+interval.duration)-(interval.startTime+interval.duration))
    let minimum=min(interval.duration,1/timeline.frameRate)
    let grouped=document.layers.first{$0.id==layer.parentID}?.group?.videoStartTime != nil
    if let clip=layer.video {
      if leading {
        let limit=max((clip.sourceUnit(0)-clip.sourceStart)/clip.frameRate,grouped ? -Double.infinity:-interval.startTime)
        let delta=min(interval.duration-minimum,max(limit,seconds))
        return .arrange(.trim(id,startTime:grouped ? interval.startTime:interval.startTime+delta,sourceIn:clip.sourceStart+delta*clip.frameRate,sourceOut:clip.sourceEnd))
      }
      let delta=max(minimum-interval.duration,min(seconds,(clip.sourceUnit(clip.frames.count)-clip.sourceEnd)/clip.frameRate))
      return .arrange(.trim(id,startTime:interval.startTime,sourceIn:clip.sourceStart,sourceOut:clip.sourceEnd+delta*clip.frameRate))
    }
    if leading {
      let delta=min(interval.duration-minimum,max(-interval.startTime,seconds))
      return .arrange(.stillTiming(id,startTime:grouped ? interval.startTime:interval.startTime+delta,duration:interval.duration-delta))
    }
    return .arrange(.stillTiming(id,startTime:interval.startTime,duration:max(minimum,min(86400-interval.startTime,interval.duration+seconds))))
  }
}
struct VideoTrackCanvas:NSViewRepresentable {
  @Bindable var store:EditorStore
  func makeNSView(context:Context)->VideoTrackScrollView {
    let scroll=VideoTrackScrollView();scroll.hasHorizontalScroller=true;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
    scroll.borderType = .noBorder;scroll.drawsBackground=true;scroll.backgroundColor=NSColor(white:0.18,alpha:1)
    let canvas=VideoTrackView();canvas.store=store;scroll.documentView=canvas;canvas.updateSize(viewport:scroll.contentSize)
    return scroll
  }
  func updateNSView(_ scroll:VideoTrackScrollView,context:Context) {
    guard let canvas=scroll.documentView as? VideoTrackView else{return};canvas.store=store;canvas.updateSize(viewport:scroll.contentSize);canvas.needsDisplay=true
  }
}
final class VideoTrackScrollView:NSScrollView {
  override func tile(){super.tile();(documentView as? VideoTrackView)?.updateSize(viewport:contentSize)}
}
final class VideoTrackView:NSView {
  weak var store:EditorStore?
  override var isFlipped:Bool{true}
  override var acceptsFirstResponder:Bool{true}
  override var wantsDefaultClipping:Bool{true}
  enum GestureKind {case playhead,workArea(Int),move(UUID),trim(UUID,Bool),transition(UUID,Bool),audioMove(UUID),audioTrim(UUID,Bool)}
  struct Gesture {
    let id=UUID()
    let kind:GestureKind
    let origin:NSPoint
    let document:CraftDocument
    var point:NSPoint
  }
  var gesture:Gesture?
  var layout:VideoTrackLayout?{store.map{.init(document:$0.document,pixelsPerSecond:$0.videoTimelinePixelsPerSecond)}}
  override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.masksToBounds=true;setAccessibilityIdentifier("photato.videoTimeline.tracks");setAccessibilityLabel("Video Timeline tracks")}
  required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
  func updateSize(viewport:NSSize) {
    guard let layout else{return}
    let size=NSSize(width:max(viewport.width,VideoTrackLayout.labelWidth+layout.duration*layout.pixelsPerSecond+32),height:max(viewport.height,VideoTrackLayout.header+CGFloat(max(1,layout.rows.count))*VideoTrackLayout.rowHeight))
    if frame.size != size{setFrameSize(size)}
  }
  func label(_ text:String,rect:NSRect,bold:Bool=false,color:NSColor=NSColor(white:0.84,alpha:1)) {
    let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byTruncatingTail
    (text as NSString).draw(in:rect,withAttributes:[.font:bold ? NSFont.boldSystemFont(ofSize:10):NSFont.systemFont(ofSize:10),.foregroundColor:color,.paragraphStyle:paragraph])
  }
  func workAreaPreview()->TimelineWorkArea? {
    guard let layout,let timeline=store?.document.videoTimeline else{return nil}
    guard let gesture,case .workArea(let edge)=gesture.kind,let original=gesture.document.videoTimeline else{return timeline.effectiveWorkArea}
    let area=original.effectiveWorkArea,delta=Int((layout.snapped(gesture.point.x-gesture.origin.x)*timeline.frameRate).rounded())
    if edge<0{return .init(startFrame:min(area.endFrame-1,max(0,area.startFrame+delta)),endFrame:area.endFrame)}
    if edge>0{return .init(startFrame:area.startFrame,endFrame:max(area.startFrame+1,min(timeline.durationFrames,area.endFrame+delta)))}
    let start=min(timeline.durationFrames-area.count,max(0,area.startFrame+delta))
    return .init(startFrame:start,endFrame:start+area.count)
  }
  func workAreaRect(_ area:TimelineWorkArea)->NSRect {
    guard let layout,let timeline=store?.document.videoTimeline else{return .zero}
    return NSRect(x:VideoTrackLayout.labelWidth+Double(area.startFrame)/timeline.frameRate*layout.pixelsPerSecond,y:27,
      width:max(1,Double(area.count)/timeline.frameRate*layout.pixelsPerSecond),height:11)
  }
  override func draw(_ dirtyRect:NSRect) {
    NSColor(white:0.18,alpha:1).setFill();dirtyRect.fill()
    guard let store,let layout,let timeline=store.document.videoTimeline else{return}
    let rows=layout.rows
    NSColor(white:0.24,alpha:1).setFill();NSRect(x:0,y:0,width:bounds.width,height:VideoTrackLayout.header).fill()
    let stride=max(1,pow(10,floor(log10(max(1,60/layout.pixelsPerSecond))))),visible=visibleRect
    let first=max(0,Int(floor((visible.minX-VideoTrackLayout.labelWidth)/layout.pixelsPerSecond/stride)))
    let last=max(first,Int(ceil((visible.maxX-VideoTrackLayout.labelWidth)/layout.pixelsPerSecond/stride)))
    for tick in first...last {
      let second=Double(tick)*stride,x=VideoTrackLayout.labelWidth+second*layout.pixelsPerSecond
      NSColor(white:0.28,alpha:1).setFill();NSRect(x:x,y:VideoTrackLayout.header,width:1,height:bounds.height).fill()
      label(String(format:"%02d:%02d",Int(second)/60,Int(second)%60),rect:NSRect(x:x+3,y:5,width:55,height:16))
    }
    if let area=workAreaPreview() {
      let rect=workAreaRect(area)
      NSColor(white:0.52,alpha:1).setFill();rect.fill()
      NSColor(white:0.86,alpha:1).setFill();NSRect(x:rect.minX,y:rect.minY-2,width:3,height:15).fill();NSRect(x:rect.maxX-3,y:rect.minY-2,width:3,height:15).fill()
      label("Work Area",rect:NSRect(x:10,y:25,width:150,height:16))
    }
    for (row,track) in rows.enumerated() {
      let y=VideoTrackLayout.header+CGFloat(row)*VideoTrackLayout.rowHeight
      guard NSRect(x:0,y:y,width:bounds.width,height:VideoTrackLayout.rowHeight).intersects(dirtyRect) else{continue}
      NSColor(white:0.23,alpha:1).setFill();NSRect(x:0,y:y,width:VideoTrackLayout.labelWidth-1,height:VideoTrackLayout.rowHeight-1).fill()
      label(track.layer.name,rect:NSRect(x:10,y:y+13,width:VideoTrackLayout.labelWidth-20,height:16),bold:track.groupID != nil)
      if let audio=track.audio {
        for clip in audio.clips {
          let rect=layout.audioRect(clip,row:row);guard !rect.isEmpty else{continue};let path=NSBezierPath(roundedRect:rect,xRadius:3,yRadius:3)
          NSColor(calibratedRed:0.23,green:0.47,blue:0.31,alpha:audio.muted || clip.settings.muted ? 0.35:1).setFill();path.fill()
          (store.selectedAudioClipID==clip.id ? NSColor.white:NSColor(white:0.1,alpha:1)).setStroke();path.stroke()
          label(clip.name,rect:rect.insetBy(dx:8,dy:7),color:.white)
          NSColor(white:1,alpha:0.35).setFill();NSRect(x:rect.minX+2,y:rect.minY+8,width:2,height:14).fill();NSRect(x:rect.maxX-4,y:rect.minY+8,width:2,height:14).fill()
          if let gesture,case .audioMove(let id)=gesture.kind,id==clip.id {NSColor.systemBlue.withAlphaComponent(0.4).setFill();rect.offsetBy(dx:gesture.point.x-gesture.origin.x,dy:gesture.point.y-gesture.origin.y).fill()}
        }
        continue
      }
      for clip in track.clips {
        let rect=layout.rect(clip,row:row);guard !rect.isEmpty else{continue};let path=NSBezierPath(roundedRect:rect,xRadius:3,yRadius:3)
        let selected=store.layoutSelection.contains(clip.id)
        (clip.video != nil ? NSColor(calibratedRed:0.25,green:0.40,blue:0.62,alpha:1):NSColor(calibratedRed:0.43,green:0.32,blue:0.54,alpha:1)).setFill();path.fill()
        (selected ? NSColor.white:NSColor(white:0.1,alpha:1)).setStroke();path.lineWidth=selected ? 1.5:1;path.stroke()
        label(clip.name,rect:rect.insetBy(dx:8,dy:7),color:.white)
        NSColor(white:1,alpha:0.35).setFill();NSRect(x:rect.minX+2,y:rect.minY+8,width:2,height:14).fill();NSRect(x:rect.maxX-4,y:rect.minY+8,width:2,height:14).fill()
        if let gesture,case .move(let id)=gesture.kind,id==clip.id {
          NSColor.systemBlue.withAlphaComponent(0.4).setFill();rect.offsetBy(dx:gesture.point.x-gesture.origin.x,dy:gesture.point.y-gesture.origin.y).fill()
        }
      }
      for transition in timeline.transitions ?? [] where track.clips.contains(where:{$0.id==transition.layerID}) {
        guard let rect=layout.transitionRect(transition,row:row) else{continue}
        NSColor.systemOrange.withAlphaComponent(0.65).setFill();rect.fill()
        let shape=NSBezierPath();shape.move(to:NSPoint(x:rect.minX,y:rect.maxY));shape.line(to:NSPoint(x:rect.maxX,y:rect.minY))
        if transition.kind == .crossFade {shape.move(to:NSPoint(x:rect.minX,y:rect.minY));shape.line(to:NSPoint(x:rect.maxX,y:rect.maxY))}
        NSColor.white.setStroke();shape.stroke()
        if store.videoSelectedTransitionID==transition.id {let outline=NSBezierPath(rect:rect);outline.lineWidth=2;outline.stroke()}
      }
    }
    let playhead=VideoTrackLayout.labelWidth+Double(store.timelinePreviewVideoFrame ?? timeline.currentFrame)/timeline.frameRate*layout.pixelsPerSecond
    NSColor.systemRed.setFill();NSRect(x:playhead,y:0,width:1.5,height:bounds.height).fill()
    let marker=NSBezierPath();marker.move(to:NSPoint(x:playhead-5,y:0));marker.line(to:NSPoint(x:playhead+6,y:0));marker.line(to:NSPoint(x:playhead,y:9));marker.close();marker.fill()
  }
  func hit(_ point:NSPoint)->(Int,VideoTrackRow)? {
    guard let layout,point.y>=VideoTrackLayout.header else{return nil}
    let row=Int((point.y-VideoTrackLayout.header)/VideoTrackLayout.rowHeight)
    guard layout.rows.indices.contains(row) else{return nil};return(row,layout.rows[row])
  }
  func begin(_ kind:GestureKind,point:NSPoint) {
    guard let store,store.canUseTimeline,gesture==nil else{return}
    store.stopTimelinePlayback(render:false)
    let value=Gesture(kind:kind,origin:point,document:store.document,point:point)
    gesture=value;store.videoTimelineGestureID=value.id;store.geometryBusy=true
  }
  override func mouseDown(with event:NSEvent) {
    guard let store,store.canUseTimeline,let layout else{return}
    window?.makeFirstResponder(self)
    let point=convert(event.locationInWindow,from:nil)
    if let area=workAreaPreview(),point.y>=24,point.y<=41,point.x>=VideoTrackLayout.labelWidth {
      let rect=workAreaRect(area)
      if abs(point.x-rect.minX)<=6{begin(.workArea(-1),point:point);return}
      if abs(point.x-rect.maxX)<=6{begin(.workArea(1),point:point);return}
      if rect.contains(point){begin(.workArea(0),point:point);return}
    }
    if point.y<VideoTrackLayout.header,point.x>=VideoTrackLayout.labelWidth {begin(.playhead,point:point);seek(point);return}
    guard let (row,track)=hit(point) else{return}
    if let audio=track.audio {
      store.selectedAudioTrackID=audio.id;store.videoSelectedTransitionID=nil
      guard let clip=audio.clips.last(where:{layout.audioRect($0,row:row).contains(point)}) else{store.selectedAudioClipID=nil;return}
      store.selectedAudioClipID=clip.id
      if event.clickCount>1{store.showAudioControls=true;return}
      let rect=layout.audioRect(clip,row:row)
      if abs(point.x-rect.minX)<6{begin(.audioTrim(clip.id,true),point:point)}
      else if abs(point.x-rect.maxX)<6{begin(.audioTrim(clip.id,false),point:point)}
      else{begin(.audioMove(clip.id),point:point)}
      needsDisplay=true;return
    }
    store.selectedAudioClipID=nil;store.selectedAudioTrackID=nil
    for t in store.document.videoTimeline?.transitions ?? [] where track.clips.contains(where:{$0.id==t.layerID}) {
      if let rect=layout.transitionRect(t,row:row),rect.contains(point) {
        store.videoSelectedTransitionID=t.id;store.select(t.layerID)
        if event.clickCount>1{store.videoTransitionEditorVisible=true}
        else if abs(point.x-rect.minX)<7,(t.kind == .crossFade || t.edge == .end){begin(.transition(t.id,true),point:point)}
        else if abs(point.x-rect.maxX)<7,(t.kind == .crossFade || t.edge == .start){begin(.transition(t.id,false),point:point)}
        needsDisplay=true;return
      }
    }
    guard let clip=track.clips.last(where:{layout.rect($0,row:row).contains(point)}) else{
      if point.x<VideoTrackLayout.labelWidth{store.select(track.id)}else{begin(.playhead,point:point);seek(point)};return
    }
    store.videoSelectedTransitionID=nil;store.select(clip.id,modifiers:event.modifierFlags)
    let rect=layout.rect(clip,row:row)
    if abs(point.x-rect.minX)<6{begin(.trim(clip.id,true),point:point)}
    else if abs(point.x-rect.maxX)<6{begin(.trim(clip.id,false),point:point)}
    else{begin(.move(clip.id),point:point)}
    needsDisplay=true
  }
  func seek(_ point:NSPoint) {
    guard let store,let layout else{return}
    do{try store.session.selectVideoFrame(layout.frame(at:point.x));store.render()}catch{store.error=error.localizedDescription}
    needsDisplay=true
  }
  override func mouseDragged(with event:NSEvent) {
    guard gesture != nil else{return};gesture!.point=convert(event.locationInWindow,from:nil)
    if case .playhead=gesture!.kind{seek(gesture!.point)}
    autoscroll(with:event);needsDisplay=true
  }
  func finish(cancelled:Bool) {
    guard let old=gesture,let store else{gesture=nil;return}
    let workArea=workAreaPreview()
    gesture=nil
    guard store.videoTimelineGestureID==old.id else{return}
    store.videoTimelineGestureID=nil;store.geometryBusy=false;needsDisplay=true
    guard !cancelled else{
      if case .playhead=old.kind,store.document.id==old.document.id,let frame=old.document.videoTimeline?.currentFrame {try? store.session.selectVideoFrame(frame);store.render()}
      return
    }
    if case .playhead=old.kind{return}
    guard store.document==old.document,let layout else{return}
    let delta=layout.snapped(old.point.x-old.origin.x)
    do {
      switch old.kind {
      case .playhead:break
      case .workArea:if let workArea,workArea != old.document.videoTimeline?.effectiveWorkArea{store.editVideo(.workspace(.workArea(workArea)))}
      case .audioTrim(let id,let leading):if delta != 0 {store.editVideo(.audio(try store.audioTrimCommand(id,leading:leading,delta:delta)))}
      case .audioMove(let id):
        guard abs(old.point.x-old.origin.x)>=3 || abs(old.point.y-old.origin.y)>=3,
          let (_,target)=hit(old.point),let audio=target.audio,
          let clip=store.document.videoTimeline?.audioTracks?.flatMap(\.clips).first(where:{$0.id==id}) else{return}
        store.editVideo(.audio(.move(id,track:audio.id,startTime:max(0,clip.startTime+delta))))
        store.selectedAudioTrackID=audio.id
      case .trim(let id,let leading):if delta != 0{store.editVideo(try store.trimVideoClip(id,leading:leading,seconds:delta))}
      case .transition(let id,let leading):
        guard var transition=store.document.videoTimeline?.transitions?.first(where:{$0.id==id}),let maximum=transition.maximumDuration(in:store.document) else{return}
        let change=delta*(leading ? -1:1)*(transition.kind == .crossFade ? 2:1)
        transition.duration=min(maximum,max(1/(store.document.videoTimeline?.frameRate ?? 24),transition.duration+change))
        if change != 0{store.editVideo(.transition(.set(transition)))}
      case .move(let id):
        guard abs(old.point.x-old.origin.x)>=3 || abs(old.point.y-old.origin.y)>=3 else{return}
        guard let layer=store.document.layers.first(where:{$0.id==id}),let (_,target)=hit(old.point),target.audio==nil else{return}
        if target.groupID != nil {
          let clips=target.clips.filter{$0.id != id},time=max(0,(old.point.x-VideoTrackLayout.labelWidth)/layout.pixelsPerSecond)
          let position=clips.firstIndex{let interval=layout.interval($0);return time<interval.startTime+interval.duration/2} ?? clips.count
          store.editVideo(.arrange(.move(id,group:target.groupID,position:position)))
        }else {
          let start=max(0,layout.interval(layer).startTime+delta)
          if target.id==id,let parent=layer.parentID,store.document.layers.first(where:{$0.id==parent})?.group?.videoStartTime == nil {
            if let clip=layer.video{store.editVideo(.timing(id,startTime:start,inFrame:clip.inFrame,outFrame:clip.outFrame,frameRate:clip.frameRate))}
            else{store.editVideo(.arrange(.stillTiming(id,startTime:start,duration:layout.interval(layer).duration)))}
          }else{
            let roots=store.document.children(of:nil),siblings=roots.filter{$0.id != id}
            let position=target.id==id ? (roots.firstIndex{$0.id==id} ?? siblings.count):(siblings.firstIndex{$0.id==target.id}.map{$0+(old.point.y<old.origin.y ? 1:0)} ?? siblings.count)
            store.editVideo(.arrange(.move(id,group:nil,position:position,startTime:start)))
          }
        }
      }
    }catch{store.error=error.localizedDescription}
  }
  override func mouseUp(with event:NSEvent){if gesture != nil{gesture!.point=convert(event.locationInWindow,from:nil)};finish(cancelled:false)}
  override func rightMouseDown(with event:NSEvent){mouseDown(with:event);finish(cancelled:true);if store?.videoSelectedTransitionID != nil{store?.videoTransitionEditorVisible=true}else if store?.selectedAudioClipID != nil || (store?.activeLayer?.video?.movie?.audioTracks ?? 0)>0{store?.showAudioControls=true}}
  override func keyDown(with event:NSEvent) {
    if event.keyCode==53{finish(cancelled:true);return}
    guard let store,store.canUseTimeline,let timeline=store.document.videoTimeline else{return}
    do {
      switch event.keyCode {
      case 123:try store.selectVideoFrame(max(0,timeline.currentFrame-1))
      case 124:try store.selectVideoFrame(min(timeline.durationFrames-1,timeline.currentFrame+1))
      case 115:try store.selectVideoFrame(0)
      case 119:try store.selectVideoFrame(timeline.durationFrames-1)
      case 49:if store.timelineTask != nil{store.stopTimelinePlayback()}else{try store.startVideoPlayback()}
      case 51:if let id=store.selectedAudioClipID{store.editVideo(.audio(.removeClip(id)))}else if let id=store.videoSelectedTransitionID{store.editVideo(.transition(.remove(id)));store.videoSelectedTransitionID=nil}
      default:super.keyDown(with:event)
      }
    }catch{store.error=error.localizedDescription}
  }
  override func viewWillMove(toWindow newWindow:NSWindow?){if newWindow==nil{finish(cancelled:true)};super.viewWillMove(toWindow:newWindow)}
}
