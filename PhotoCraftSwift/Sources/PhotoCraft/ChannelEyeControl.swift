import AppKit
import SwiftUI

/// One tracker per Channels panel, with native input/focus cleanup and no pixel edit.
@MainActor final class ChannelEyeTracking {
  let buttons=NSHashTable<ChannelEyeButton>.weakObjects()
  private(set) weak var store:EditorStore?
  private weak var window:NSWindow?
  private weak var scrollView:NSScrollView?
  private var point:NSPoint?
  private var token:UUID?
  private var monitor:Any?
  private var observers:[NSObjectProtocol]=[]
  private var timer:Timer?
  func press(_ button:ChannelEyeButton,event:NSEvent) {
    cancel()
    guard button.isEnabled,let store=button.store,let window=button.window,
      let token=store.beginChannelVisibilitySweep(button.channel) else{return}
    self.store=store;self.window=window;self.token=token;point=event.locationInWindow;scrollView=button.enclosingScrollView
    monitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDragged,.leftMouseUp,.keyDown,.rightMouseDown,.otherMouseDown]) {[weak self] event in
      let consumed=MainActor.assumeIsolated {() -> Bool in
        guard let self,self.token != nil else{return false}
        switch event.type {
        case .leftMouseDragged:self.drag(event);return true
        case .leftMouseUp:self.release(event);return true
        case .keyDown:if event.keyCode==53{self.cancel()};return true
        default:self.cancel();return false
        }
      };return consumed ? nil:event
    }
    for (name,object) in [(NSApplication.didResignActiveNotification,nil),(NSWindow.willCloseNotification,window),(NSWindow.didResignKeyNotification,window)] as [(Notification.Name,Any?)] {
      observers.append(NotificationCenter.default.addObserver(forName:name,object:object,queue:.main) {[weak self] _ in MainActor.assumeIsolated{self?.cancel()}})
    }
    let timer=Timer(timeInterval:0.05,repeats:true){[weak self] _ in MainActor.assumeIsolated{self?.autoscroll()}}
    self.timer=timer;RunLoop.main.add(timer,forMode:.common)
  }
  func drag(_ event:NSEvent) {
    guard event.window === window else{cancel();return};sweep(to:event.locationInWindow)
  }
  func sweep(to next:NSPoint) {
    guard let store,let token,store.channelVisibilitySweep?.id==token else{cancel();return}
    let previous=point ?? next
    let targets=buttons.allObjects.compactMap {button -> ChannelEyeTarget? in
      guard button.tracking === self,button.store === store,button.window === window,!button.isHiddenOrHasHiddenAncestor,
        !button.visibleRect.intersection(button.bounds).isEmpty else{return nil}
      let rect=button.convert(button.visibleRect.intersection(button.bounds),to:nil)
      return Self.intersects(from:previous,to:next,rect:rect) ? button.channel:nil
    }
    store.extendChannelVisibilitySweep(token,over:targets);point=next
    if store.channelVisibilitySweep?.id != token {cancel()}
  }
  static func intersects(from a:NSPoint,to b:NSPoint,rect:NSRect)->Bool {
    var low:CGFloat=0,high:CGFloat=1
    for (start,delta,minimum,maximum) in [(a.x,b.x-a.x,rect.minX,rect.maxX),(a.y,b.y-a.y,rect.minY,rect.maxY)] {
      if abs(delta)<0.000001 {if start<minimum || start>maximum{return false}}
      else {let p=(minimum-start)/delta,q=(maximum-start)/delta;low=max(low,min(p,q));high=min(high,max(p,q));if low>high{return false}}
    };return true
  }
  func release(_ event:NSEvent) {
    guard event.window === window,let token else{cancel();return}
    sweep(to:event.locationInWindow);store?.finishChannelVisibilitySweep(token);cleanup()
  }
  func autoscroll() {
    guard let point,let scrollView,let content=scrollView.documentView,let token,store?.channelVisibilitySweep?.id==token else{return}
    let clip=scrollView.contentView,local=clip.convert(point,from:nil),bounds=clip.bounds,margin=min(18,bounds.height/3)
    let delta:CGFloat=local.y<bounds.minY+margin ? -12:(local.y>bounds.maxY-margin ? 12:0)
    guard delta != 0 else{return}
    let y=min(max(content.frame.minY,bounds.minY+delta),max(content.frame.minY,content.frame.maxY-bounds.height))
    guard y != bounds.minY else{return};clip.scroll(to:.init(x:bounds.minX,y:y));scrollView.reflectScrolledClipView(clip);content.layoutSubtreeIfNeeded();sweep(to:point)
  }
  func cancel() {if let token {store?.finishChannelVisibilitySweep(token,cancel:true)};cleanup()}
  private func cleanup() {
    if let monitor {NSEvent.removeMonitor(monitor)};monitor=nil
    for observer in observers {NotificationCenter.default.removeObserver(observer)};observers=[];timer?.invalidate();timer=nil
    token=nil;point=nil;window=nil;scrollView=nil;store=nil
  }
}
struct ChannelEyeControl:View {
  let store:EditorStore
  let channel:ChannelEyeTarget
  let tracking:ChannelEyeTracking
  let label:String
  let identifier:String
  var height:CGFloat=36
  var body:some View {
    ChannelEyeRepresentable(store:store,channel:channel,tracking:tracking,label:label,identifier:identifier,height:height,
      visible:store.channelEyeVisible(channel),enabled:store.canChangeChannelVisibility)
  }
}
private struct ChannelEyeRepresentable:NSViewRepresentable {
  let store:EditorStore
  let channel:ChannelEyeTarget
  let tracking:ChannelEyeTracking
  let label:String
  let identifier:String
  let height:CGFloat
  let visible:Bool
  let enabled:Bool
  func makeNSView(context:Context)->ChannelEyeButton {ChannelEyeButton()}
  func updateNSView(_ button:ChannelEyeButton,context:Context) {
    button.store=store;button.channel=channel;button.tracking=tracking;tracking.buttons.add(button);button.controlHeight=height
    button.isEnabled=enabled
    button.image=visible ? NSImage(systemSymbolName:"eye",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:11,weight:.regular)):nil
    button.setAccessibilityLabel(label);button.setAccessibilityValue(visible ? "Visible":"Hidden");button.setAccessibilityIdentifier(identifier)
    button.toolTip="Toggle visibility without selecting the channel. Drag through eyes to show or hide channels."
  }
}
@MainActor final class ChannelEyeButton:NSButton {
  weak var store:EditorStore?
  weak var tracking:ChannelEyeTracking?
  var channel=ChannelEyeTarget.quickMask
  var controlHeight:CGFloat=36 {didSet{if controlHeight != oldValue{invalidateIntrinsicContentSize()}}}
  init() {super.init(frame:.zero);title="";isBordered=false;imagePosition = .imageOnly;contentTintColor=NSColor(calibratedWhite:0.88,alpha:1);target=self;action=#selector(toggle)}
  required init?(coder:NSCoder){nil}
  override var intrinsicContentSize:NSSize {NSSize(width:26,height:controlHeight)}
  override var alignmentRectInsets:NSEdgeInsets {NSEdgeInsets(top:0,left:0,bottom:0,right:0)}
  override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
  override func resetCursorRects() {addCursorRect(bounds,cursor:.arrow)}
  @objc private func toggle() {guard let store else{return};do{try store.setChannelEye(channel,visible:!store.channelEyeVisible(channel))}catch{store.error=error.localizedDescription}}
  override func mouseDown(with event:NSEvent){tracking?.press(self,event:event)}
  override func mouseDragged(with event:NSEvent){tracking?.drag(event)}
  override func mouseUp(with event:NSEvent){tracking?.release(event)}
  override func cancelOperation(_ sender:Any?){tracking?.cancel()}
}
