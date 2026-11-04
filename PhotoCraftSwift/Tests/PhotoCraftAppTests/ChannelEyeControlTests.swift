import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
@testable import PhotoCraft

final class ChannelEyeControlTests:XCTestCase {
  @MainActor func setup()throws->(EditorStore,NSWindow,ChannelEyeTracking,ChannelEyeButton,ChannelEyeButton) {
    _ = NSApplication.shared
    let store=EditorStore(document:try IndependentChannelVisibilityTests().fixture())
    let window=NSWindow(contentRect:.init(x:0,y:0,width:200,height:130),styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    let tracking=ChannelEyeTracking(),ids=try XCTUnwrap(store.document.alphaChannels).map(\.id)
    func button(_ id:UUID,_ y:CGFloat)->ChannelEyeButton {
      let button=ChannelEyeButton();button.frame = .init(x:0,y:y,width:26,height:32);button.store=store;button.channel = .alpha(id);button.tracking=tracking
      window.contentView?.addSubview(button);tracking.buttons.add(button);return button
    }
    return (store,window,tracking,button(ids[0],80),button(ids[1],30))
  }
  @MainActor func event(_ type:NSEvent.EventType,_ point:NSPoint,_ window:NSWindow,_ flags:NSEvent.ModifierFlags=[] )throws->NSEvent {
    try XCTUnwrap(NSEvent.mouseEvent(with:type,location:point,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1))
  }
  @MainActor func testNativeClicksRetainTargetAtAllSixteenModifiers()throws {
    let (store,window,tracking,first,_)=try setup()
    defer{tracking.cancel();store.renderTask?.cancel();window.close()}
    let original=store.document,id=try XCTUnwrap(original.alphaChannels?.first?.id)
    for bits in 0..<16 {
      var flags:NSEvent.ModifierFlags=[]
      for (index,flag) in [NSEvent.ModifierFlags.control,.command,.option,.shift].enumerated() where bits&(1<<index) != 0 {flags.insert(flag)}
      first.mouseDown(with:try event(.leftMouseDown,.init(x:13,y:96),window,flags));XCTAssertNotNil(store.channelVisibilitySweep)
      first.mouseUp(with:try event(.leftMouseUp,.init(x:13,y:96),window,flags));XCTAssertNil(store.channelVisibilitySweep)
      XCTAssertEqual(store.isAlphaVisible(id),bits%2==0);XCTAssertNil(store.editingChannel);XCTAssertEqual(store.document,original)
    }
    XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertTrue(first.acceptsFirstMouse(for:nil))
  }
  @MainActor func testNativeSweepVisitsEachRowOnceAndEscapeRestoresView()throws {
    let (store,window,tracking,first,second)=try setup()
    defer{tracking.cancel();store.renderTask?.cancel();window.close()}
    let ids=try XCTUnwrap(store.document.alphaChannels).map(\.id)
    first.mouseDown(with:try event(.leftMouseDown,.init(x:13,y:96),window))
    tracking.drag(try event(.leftMouseDragged,.init(x:13,y:46),window))
    tracking.drag(try event(.leftMouseDragged,.init(x:13,y:96),window))
    XCTAssertEqual(store.visibleAlphaIDs,Set(ids));XCTAssertEqual(store.channelVisibilitySweep?.visited.count,2)
    first.cancelOperation(nil);XCTAssertTrue(store.visibleAlphaIDs.isEmpty);XCTAssertNil(store.channelVisibilitySweep)
    first.mouseDown(with:try event(.leftMouseDown,.init(x:13,y:96),window))
    second.mouseUp(with:try event(.leftMouseUp,.init(x:13,y:46),window))
    XCTAssertEqual(store.visibleAlphaIDs,Set(ids));XCTAssertNil(store.channelVisibilitySweep);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testFocusWindowAndDocumentChangesCancelWithoutForeignStateRestoration()throws {
    let (store,window,tracking,first,_)=try setup()
    defer{tracking.cancel();store.renderTask?.cancel();window.close()}
    first.mouseDown(with:try event(.leftMouseDown,.init(x:13,y:96),window))
    NotificationCenter.default.post(name:NSWindow.didResignKeyNotification,object:window)
    XCTAssertTrue(store.visibleAlphaIDs.isEmpty);XCTAssertNil(store.channelVisibilitySweep)
    first.mouseDown(with:try event(.leftMouseDown,.init(x:13,y:96),window))
    var replacement=store.document;replacement.id=UUID();store.session=EditorSession(document:replacement)
    tracking.drag(try event(.leftMouseDragged,.init(x:13,y:46),window))
    XCTAssertTrue(store.visibleAlphaIDs.isEmpty);XCTAssertNil(store.channelVisibilitySweep);XCTAssertEqual(store.document,replacement)
  }
  @MainActor func testSweepDoesNotHitRowsOutsideTheEyeColumn()throws {
    let (store,window,tracking,first,_)=try setup()
    defer{tracking.cancel();store.renderTask?.cancel();window.close()}
    let ids=try XCTUnwrap(store.document.alphaChannels).map(\.id)
    first.mouseDown(with:try event(.leftMouseDown,.init(x:13,y:96),window))
    tracking.drag(try event(.leftMouseDragged,.init(x:100,y:46),window))
    XCTAssertEqual(store.visibleAlphaIDs,[ids[0]])
    tracking.drag(try event(.leftMouseDragged,.init(x:13,y:46),window))
    XCTAssertEqual(store.visibleAlphaIDs,Set(ids));tracking.cancel();XCTAssertTrue(store.visibleAlphaIDs.isEmpty)
    XCTAssertFalse(ChannelEyeTracking.intersects(from:.init(x:100,y:100),to:.init(x:100,y:0),rect:.init(x:0,y:30,width:26,height:32)))
  }
  @MainActor func testHostedNativeEyeAccessibilityTracksVisibility()async throws {
    let store=EditorStore(document:try IndependentChannelVisibilityTests().fixture()),tracking=ChannelEyeTracking()
    let id=try XCTUnwrap(store.document.alphaChannels?.first?.id)
    let view=NSHostingView(rootView:ChannelEyeControl(store:store,channel:.alpha(id),tracking:tracking,label:"Visibility of saved mask",identifier:"saved-mask-eye",height:40).frame(width:26,height:40))
    let window=NSWindow(contentRect:.init(x:0,y:0,width:80,height:80),styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=view
    defer{tracking.cancel();store.renderTask?.cancel();window.close()}
    view.layoutSubtreeIfNeeded()
    func buttons(_ view:NSView)->[ChannelEyeButton] {(view as? ChannelEyeButton).map{[$0]} ?? view.subviews.flatMap(buttons)}
    let button=try XCTUnwrap(buttons(view).first)
    XCTAssertEqual(button.accessibilityLabel(),"Visibility of saved mask");XCTAssertEqual(button.accessibilityIdentifier(),"saved-mask-eye")
    XCTAssertEqual(button.accessibilityValue() as? String,"Hidden")
    button.performClick(nil);await store.renderTask?.value;await Task.yield();view.layoutSubtreeIfNeeded()
    XCTAssertTrue(store.isAlphaVisible(id));XCTAssertNil(store.editingChannel);XCTAssertEqual(button.accessibilityValue() as? String,"Visible")
  }
}
