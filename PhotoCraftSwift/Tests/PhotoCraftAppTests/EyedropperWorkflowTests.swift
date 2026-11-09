import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

@MainActor private final class EyedropperAdmissionWindow459:NSWindow {override var isKeyWindow:Bool{true}}
private final class SampleGate459:@unchecked Sendable {
  private let condition=NSCondition();private var open=false;private var started=false
  func wait(){condition.lock();started=true;condition.broadcast();while !open{condition.wait()};condition.unlock()}
  func release(){condition.lock();open=true;condition.broadcast();condition.unlock()}
  var entered:Bool{condition.lock();defer{condition.unlock()};return started}
}
final class EyedropperWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:8,height:4,depth:depth)
    var s=try Surface(width:8,height:4,depth:depth,fill:Pixel(1,0,0));for y in 0..<4{for x in 4..<8{s.setPixel(x:x,y:y,Pixel(0,0,1))}}
    d.layers[0].content = .raster(s);return d
  }
  @MainActor func testNativeDragOptionCaptureEscapeAndNoDocumentHistory()async throws {
    let d=try fixture(),s=EditorStore(document:d);defer{s.cancelEyedropper();s.renderTask?.cancel()};s.tool = .eyedropper
    let original=s.activePaintColorPair
    s.beginEyedropper(at:.init(x:1,y:1),modifiers:[]);await s.eyedropperTask?.value
    XCTAssertEqual(s.brush.color,Pixel(1,0,0));XCTAssertEqual(s.backgroundColor,original.background)
    s.requestEyedropper(at:.init(x:6,y:1));await s.eyedropperTask?.value;XCTAssertEqual(s.brush.color,Pixel(0,0,1))
    s.cancelEyedropper(restore:true);XCTAssertEqual(s.activePaintColorPair,original)
    s.beginEyedropper(at:.init(x:1,y:1),modifiers:.option);await s.eyedropperTask?.value
    s.requestEyedropper(at:.init(x:6,y:1),finishing:true);await s.eyedropperTask?.value
    XCTAssertEqual(s.brush.color,original.foreground);XCTAssertEqual(s.backgroundColor,Pixel(0,0,1));XCTAssertNil(s.eyedropperGesture)
    XCTAssertTrue(s.document==d);XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testStaleToolFocusPalettePreferencesAndSessionRejectPendingSamples()async throws {
    for mode in 0..<5 {
      let s=EditorStore(document:try fixture());defer{s.cancelEyedropper();s.renderTask?.cancel()};s.tool = .eyedropper
      let original=s.activePaintColorPair;s.beginEyedropper(at:.init(x:1,y:1),modifiers:[]);let task=s.eyedropperTask
      switch mode {
      case 0:s.tool = .brush
      case 1:CraftCanvas(store:s).clearCursorInput()
      case 2:s.brush.color=Pixel(0,1,0)
      case 3:var settings=s.eyedropperSettings;settings.size=3;s.eyedropperSettings=settings
      default:s.session=EditorSession(document:try fixture(.u16))
      }
      await task?.value
      XCTAssertEqual(s.brush.color,mode==2 ? Pixel(0,1,0):original.foreground);XCTAssertNil(s.eyedropperGesture)
    }
  }
  @MainActor func testPreferencesSharedPersistedNoopDetachedAndProductionStartup()throws {
    _=CraftDocumentController(workspaces:WorkspaceLibrary());_=NSApplication.shared
    let name="Photato.Eyedropper.Tests."+UUID().uuidString,defaults=try XCTUnwrap(UserDefaults(suiteName:name));defer{defaults.removePersistentDomain(forName:name)}
    let preferences=EyedropperPreferences(defaults:defaults);var settings=preferences.settings;settings.size=31;settings.source = .allNoAdjustments;settings.showRing=false;try preferences.set(settings)
    let revision=preferences.revision;try preferences.set(settings);XCTAssertEqual(preferences.revision,revision);XCTAssertEqual(EyedropperPreferences(defaults:defaults).settings,settings)
    var invalid=settings;invalid.size=2;XCTAssertThrowsError(try preferences.set(invalid));XCTAssertEqual(preferences.settings,settings)
    let controller=CraftDocumentController(workspaces:WorkspaceLibrary(),eyedropperPreferences:preferences),a=CraftNSDocument(model:try fixture()),b=CraftNSDocument(model:try fixture())
    controller.addDocument(a);controller.addDocument(b);defer{controller.removeDocument(a);controller.removeDocument(b);a.store.renderTask?.cancel();b.store.renderTask?.cancel()}
    XCTAssertTrue(a.store.eyedropperPreferences===b.store.eyedropperPreferences);XCTAssertEqual(b.store.eyedropperSettings,settings)
    controller.removeDocument(b);settings.size=51;a.store.eyedropperSettings=settings;XCTAssertEqual(b.store.eyedropperSettings.size,31)
    let saved=UserDefaults.standard.object(forKey:EyedropperPreferences.key);defer{if let saved{UserDefaults.standard.set(saved,forKey:EyedropperPreferences.key)}else{UserDefaults.standard.removeObject(forKey:EyedropperPreferences.key)}}
    UserDefaults.standard.set(try JSONEncoder().encode(settings),forKey:EyedropperPreferences.key)
    XCTAssertEqual(AppDelegate().controller.eyedropperPreferences.settings,settings)
    XCTAssertEqual(PhotatoApp.makeDelegate(isolatedSession:false).controller.eyedropperPreferences.settings,settings)
    XCTAssertEqual(PhotatoApp.makeDelegate(isolatedSession:true).controller.eyedropperPreferences.settings,ColorSampleSettings())
    defaults.set(Data("invalid".utf8),forKey:EyedropperPreferences.key);XCTAssertEqual(EyedropperPreferences(defaults:defaults).settings,ColorSampleSettings());XCTAssertEqual(defaults.data(forKey:EyedropperPreferences.key),Data("invalid".utf8))
  }
  @MainActor func testSixteenModifiersCaptureTargetAndDisableMissingColorSampler()async throws {
    let s=EditorStore(document:try fixture());defer{s.cancelEyedropper();s.renderTask?.cancel()};s.tool = .eyedropper
    let v=CraftCanvas(store:s),flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for bits in 0..<16 {
      let modifiers=flags.enumerated().reduce(NSEvent.ModifierFlags()){bits & (1 << $1.offset)==0 ? $0:$0.union($1.element)}
      v.updateCursorModifiers(modifiers);let expected:ToolCursor=modifiers.contains(.shift) ? .unavailable:.colorSample(target:modifiers.contains(.option) ? .background:.foreground,available:true)
      XCTAssertEqual(v.toolCursor,expected);XCTAssertEqual(EditorTool.eyedropper.cursor(modifiers:modifiers),expected)
      s.beginEyedropper(at:.init(x:1,y:1),modifiers:modifiers)
      if modifiers.contains(.shift){XCTAssertNil(s.eyedropperGesture)}else{
        v.beginCursorGesture(try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:.zero,modifierFlags:modifiers,timestamp:1,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1)));v.updateCursorModifiers(modifiers.symmetricDifference(.option));XCTAssertEqual(v.toolCursor,expected)
        XCTAssertEqual(s.eyedropperGesture?.target,modifiers.contains(.option) ? .background:.foreground)
      }
      v.endCursorGesture(try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseUp,location:.zero,modifierFlags:[],timestamp:1,windowNumber:0,context:nil,eventNumber:2,clickCount:1,pressure:0)));s.cancelEyedropper()
    }
    v.spaceHeld=true;XCTAssertEqual(v.toolCursor,.openHand)
  }
  @MainActor func testHTTPPureSamplingOverridesAndNativeColorEquivalenceEveryDepth()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,file in
      try service.share(file);service.setPreferenceChangesEnabled(true)
      let shared=try XCTUnwrap(service.shares.first?.id)
      let configured=try await h.request(service,path:"/v1/documents/\(shared)/commands",body:["command":"color.sample","revision":service.revision(file.store),"parameters":["operation":"configure","size":1]])
      XCTAssertEqual(configured.0.statusCode,200)
      let configuredValue=try JSONDecoder().decode(AutomationValue.self,from:configured.1)
      XCTAssertNoThrow(try BrushAPI.merge(configuredValue,schema:ColorSamplingAPI.resultSchema))
      for depth in PixelDepth.allCases {
        let d=try fixture(depth);file.store.session=EditorSession(document:d);try service.share(file)
        let id=try XCTUnwrap(service.shares.first?.id),original=file.store.activePaintColorPair,revision=service.revision(file.store)
        @MainActor func call(_ p:[String:Any])async throws->(HTTPURLResponse,Data){try await h.request(service,path:"/v1/documents/\(id)/commands",body:["command":"color.sample","revision":service.revision(file.store),"parameters":p])}
        let p:[String:Any]=["operation":"sample","x":3,"y":1,"size":3,"source":"All Layers"]
        let (http,data)=try await call(p);XCTAssertEqual(http.statusCode,200)
        let payload=try XCTUnwrap(JSONSerialization.jsonObject(with:data)as?[String:Any]),color=try XCTUnwrap(payload["color"]as?[String:Double])
        let sampledValue=try JSONDecoder().decode(AutomationValue.self,from:data)
        XCTAssertNoThrow(try BrushAPI.merge(sampledValue,schema:ColorSamplingAPI.resultSchema))
        let stateValue=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:ColorSamplingAPI.state(file.store)))
        XCTAssertNoThrow(try BrushAPI.merge(stateValue,schema:ColorSamplingAPI.stateSchema))
        var settings=ColorSampleSettings();settings.size=3;let native=try ColorSampling.sample(d,x:3,y:1,settings:settings)
        XCTAssertEqual(color["r"],Double(native.color.r));XCTAssertEqual(color["g"],Double(native.color.g));XCTAssertEqual(color["b"],Double(native.color.b));XCTAssertEqual(service.revision(file.store),revision);XCTAssertEqual(file.store.activePaintColorPair,original);XCTAssertEqual(file.store.eyedropperSettings,ColorSampleSettings())
        var foreground=p;foreground["target"]="foreground";let (applied,_)=try await call(foreground);XCTAssertEqual(applied.statusCode,200);XCTAssertEqual(file.store.brush.color,native.color)
        var background=p;background["target"]="background";let (bg,_)=try await call(background);XCTAssertEqual(bg.statusCode,200);XCTAssertEqual(file.store.backgroundColor,native.color)
        XCTAssertTrue(file.store.document==d);XCTAssertTrue(file.store.session.undoStack.isEmpty);XCTAssertFalse(file.isDocumentEdited)
      }
      let large=try CraftDocument(width:300000,height:1);file.store.session=EditorSession(document:large);try service.share(file)
      let id=try XCTUnwrap(service.shares.first?.id)
      let edge=try await h.request(service,path:"/v1/documents/\(id)/commands",body:["command":"color.sample","revision":service.revision(file.store),"parameters":["operation":"sample","x":299999.9999995,"y":0]])
      XCTAssertEqual(edge.0.statusCode,200)
      let edgePayload=try XCTUnwrap(JSONSerialization.jsonObject(with:edge.1)as?[String:Any]),edgeColor=try XCTUnwrap(edgePayload["color"]as?[String:Double]);XCTAssertEqual(edgeColor["r"],1);XCTAssertEqual(edgeColor["g"],1);XCTAssertEqual(edgeColor["b"],1)
      XCTAssertTrue(file.store.document==large);XCTAssertTrue(file.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testHTTPConfigurationPermissionAtomicValidationBusyAndStale()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,file in
      file.store.session=EditorSession(document:try fixture());try service.share(file)
      var status=try await h.edit(service,file,"color.sample",["operation":"configure","size":5]);XCTAssertEqual(status,403)
      service.setPreferenceChangesEnabled(true)
      status=try await h.edit(service,file,"color.sample",["operation":"configure","size":5,"source":"Current Layer","showRing":false]);XCTAssertEqual(status,200);XCTAssertEqual(file.store.eyedropperSettings.size,5)
      let revision=service.revision(file.store),settings=file.store.eyedropperSettings
      status=try await h.edit(service,file,"color.sample",["operation":"configure","size":5]);XCTAssertEqual(status,200);XCTAssertEqual(service.revision(file.store),revision)
      for p:[String:Any]in [["operation":"configure"],["operation":"configure","size":2,"source":"All Layers"],["operation":"configure","x":1],["operation":"sample","x":1],["operation":"sample","x":-1,"y":1],["operation":"sample","x":8,"y":1],["operation":"sample","x":1,"y":1,"showRing":true],["operation":"sample","x":1,"y":1,"target":"bad"],["operation":"sample","x":1,"y":1,"layerID":UUID().uuidString]] {
        status=try await h.edit(service,file,"color.sample",p);XCTAssertEqual(status,400,"\(p)");XCTAssertEqual(file.store.eyedropperSettings,settings)
      }
      file.store.tool = .eyedropper;file.store.beginEyedropper(at:.init(x:1,y:1),modifiers:[])
      status=try await h.edit(service,file,"color.sample",["operation":"sample","x":1,"y":1]);XCTAssertEqual(status,409);file.store.cancelEyedropper()
      let id=try XCTUnwrap(service.shares.first?.id)
      let stale=try await h.request(service,path:"/v1/documents/\(id)/commands",body:["command":"color.sample","revision":"stale","parameters":["operation":"sample","x":1,"y":1]])
      XCTAssertEqual(stale.0.statusCode,409);XCTAssertTrue(file.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testAPIRejectsCancelledRevokedAndStaleWorkerResults()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,file in
      file.store.session=EditorSession(document:try fixture());try service.share(file)
      for mode in 0..<5 {
        if service.shares.isEmpty{try service.share(file)}
        let id=try XCTUnwrap(service.shares.first?.id),gate=SampleGate459();defer{gate.release()}
        service.prepareColorSample={input,x,y,settings,layer in gate.wait();try Task.checkCancellation();return try input.sample(x:x,y:y,settings:settings,layerID:layer)}
        let command=try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"color.sample","revision":service.revision(file.store),"parameters":["operation":"sample","x":1,"y":1,"target":"background"]]))
        let before=file.store.activePaintColorPair
        let task=Task{try await service.executeColorSample(command,document:file,shareID:id)}
        let deadline=Date().addingTimeInterval(5);while !gate.entered,Date()<deadline{try await Task.sleep(for:.milliseconds(1))};XCTAssertTrue(gate.entered)
        switch mode {
        case 0:task.cancel()
        case 1:service.revoke(id)
        case 2:file.store.brush.color=Pixel(0,1,0)
        case 3:var settings=file.store.eyedropperSettings;settings.size=3;file.store.eyedropperSettings=settings
        default:file.store.session=EditorSession(document:try fixture(.u16))
        }
        gate.release()
        do{_ = try await task.value;XCTFail("Stale/cancelled result published")}catch is CancellationError{XCTAssertEqual(mode,0)}catch let failure as AutomationFailure{XCTAssertEqual(failure.status,409)}
        XCTAssertEqual(file.store.backgroundColor,before.background);XCTAssertTrue(file.store.session.undoStack.isEmpty)
      }
    }
  }
  @MainActor func testDisplayedTargetUsesDocumentDepthAndRejectsExplicitLayerSources()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,file in
      for depth in PixelDepth.allCases {
        let d=try fixture(depth);file.store.session=EditorSession(document:d);file.store.toggleQuickMask();await file.store.renderTask?.value;try service.share(file)
        file.store.tool = .eyedropper
        XCTAssertTrue(file.store.editingComponent);XCTAssertTrue(file.store.canUseComponentCanvasTool)
        let canvas=CraftCanvas(store:file.store);canvas.frame = .init(x:0,y:0,width:200,height:100)
        let window=EyedropperAdmissionWindow459(contentRect:canvas.frame,styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=canvas;window.makeKeyAndOrderFront(nil)
        defer{window.contentView=nil;window.close()}
        file.store.updateViewport(size:canvas.bounds.size,backingScale:1);file.store.setZoom(1,center:true);await file.store.renderTask?.value
        let before=file.store.document,history=file.store.session.undoStack.count
        let down=try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:.init(x:100,y:50),modifierFlags:[],timestamp:1,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1))
        let point=canvas.docPoint(down),expectedPoint=try file.store.colorSamplingInput().sample(x:point.x,y:point.y,settings:file.store.eyedropperSettings,layerID:nil)
        canvas.mouseDown(with:down);XCTAssertNotNil(file.store.eyedropperGesture)
        let up=try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseUp,location:.init(x:100,y:50),modifierFlags:[],timestamp:2,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0))
        canvas.mouseUp(with:up);await file.store.eyedropperTask?.value
        XCTAssertNil(file.store.eyedropperGesture);XCTAssertTrue(file.store.document==before);XCTAssertEqual(file.store.session.undoStack.count,history)
        XCTAssertEqual(file.store.eyedropperResult?.color,expectedPoint.color);XCTAssertEqual(file.store.activePaintColorPair.foreground,expectedPoint.color)
        let input=try file.store.colorSamplingInput(),surface=try XCTUnwrap(input.displayed);var settings=ColorSampleSettings();settings.size=3
        let expected=try ColorAveraging.sample(region:.init(x:2,y:0,width:3,height:3),depth:depth){surface.pixel(x:$0,y:$1)}
        XCTAssertEqual(try input.sample(x:3,y:1,settings:settings,layerID:nil),expected)
        for parameter in ["source":"All Layers","layerID":d.layers[0].id.uuidString]{
          var p:[String:Any]=["operation":"sample","x":3,"y":1,"size":3];p[parameter.key]=parameter.value
          let status=try await h.edit(service,file,"color.sample",p);XCTAssertEqual(status,parameter.key=="layerID" ? 400:422)
        }
        file.store.toggleQuickMask()
      }
    }
  }
  @MainActor func testSamplingRingNativeOptionsAndSchemas()async throws {
    _=NSApplication.shared
    let s=EditorStore(document:try fixture());defer{s.cancelEyedropper();s.renderTask?.cancel()};s.tool = .eyedropper;s.beginEyedropper(at:.init(x:1,y:1),modifiers:[]);await s.eyedropperTask?.value
    let canvas=CraftCanvas(store:s);canvas.frame = .init(x:0,y:0,width:180,height:100);canvas.cursorLocationInView = .init(x:90,y:50)
    for appearance in [NSAppearance.Name.aqua,.darkAqua]{
      let view=NSHostingView(rootView:EyedropperOptions(store:s));view.appearance=NSAppearance(named:appearance);view.frame = .init(x:0,y:0,width:850,height:45);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.height,0)
      let image=NSImage(size:canvas.bounds.size);image.lockFocus();if let context=NSGraphicsContext.current?.cgContext{canvas.drawEyedropperRing(in:context)};image.unlockFocus();XCTAssertNotNil(image.tiffRepresentation)
    }
    XCTAssertEqual(ColorSampleSettings.sizes,[1,3,5,11,31,51,101]);XCTAssertEqual(ColorSampleSource.allCases.count,5)
    XCTAssertNotNil(AutomationService.capabilities["eyedropper"]);XCTAssertNotNil(ColorSamplingAPI.parameterSchema["oneOf"]);XCTAssertEqual(AutomationCommand.definitions.count,267);XCTAssertEqual(ActionLibraryFile.maximumVersion,61)
  }
}
