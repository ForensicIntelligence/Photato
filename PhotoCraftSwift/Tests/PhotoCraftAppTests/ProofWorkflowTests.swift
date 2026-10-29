import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
import SwiftUI
@testable import PhotoCraft

final class ProofWorkflowTests: XCTestCase {
  @MainActor func testConfigurePreviewAndReadShareNativeStateWithoutHistoryOrExports() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      let store=document.store
      var source=store.document; source.layers[0].content = .raster(try Surface(width:4,height:3,fill:Pixel(1,0,0)))
      store.session=EditorSession(document:source)
      try service.share(document)
      let id=try XCTUnwrap(service.shares.first?.id), original=store.document, undo=store.session.undoStack.count
      let originalPNG=try AutomationService.png(original), originalPSD=try DocumentIO.encode(original,format:.psd)
      let revision=service.revision(store)
      let status=try await helper.edit(service,document,"proof.configure",["settings":["enabled":true,"simulatePaper":true,"simulateBlack":true]])
      XCTAssertEqual(status,200); await store.renderTask?.value
      XCTAssertEqual(store.document,original); XCTAssertEqual(store.session.undoStack.count,undo); XCTAssertFalse(document.isDocumentEdited)
      XCTAssertNotEqual(service.revision(store),revision)
      let proof=try await helper.request(service,path:"/v1/documents/\(id)/proof-preview.png")
      XCTAssertEqual(proof.0.statusCode,200)
      XCTAssertEqual(proof.1,try AutomationService.png(original,proof:store.proofSettings)); XCTAssertNotEqual(proof.1,originalPNG)
      let normal=try await helper.request(service,path:"/v1/documents/\(id)/preview.png")
      XCTAssertEqual(normal.1,originalPNG); XCTAssertEqual(try DocumentIO.encode(store.document,format:.psd),originalPSD)
      let screen=try RasterIO.surface(XCTUnwrap(store.image)), expected=try RasterIO.surface(SoftProof.image(original,settings:store.proofSettings))
      XCTAssertEqual(try screen.rgbaData(depth:.u8),try expected.rgbaData(depth:.u8))
      XCTAssertEqual(store.surface,try Renderer.composite(original))
      let read=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"proof.settings.read","revision":service.revision(store),"parameters":[:]])
      XCTAssertEqual(read.0.statusCode,200)
      let decoded=try XCTUnwrap(JSONSerialization.jsonObject(with:read.1) as? [String:Any])
      XCTAssertNotNil(decoded["proofing"])
      let stale = try await helper.edit(service,document,"proof.configure",["settings":["enabled":false]],revision:revision)
      XCTAssertEqual(stale,409)
    }
  }
  @MainActor func testDraftPreviewCancelCommitAndAPIBusyLeavePixelsUntouched() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      let store=document.store; try service.share(document); let original=store.document, before=store.proofSettings
      store.beginProof(); let draft=try XCTUnwrap(store.proofWorkspace)
      XCTAssertTrue(store.hasToneDraft); XCTAssertTrue(store.effectiveProof.enabled)
      draft.settings.simulatePaper=true; store.previewProof()
      let busy=try await helper.edit(service,document,"proof.configure",["settings":["enabled":true]])
      XCTAssertEqual(busy,409)
      let id=try XCTUnwrap(service.shares.first?.id)
      let bytes=try await helper.request(service,path:"/v1/documents/\(id)/proof-preview.png")
      XCTAssertEqual(bytes.0.statusCode,200); XCTAssertEqual(bytes.1,try AutomationService.png(original))
      store.cancelProof(); XCTAssertEqual(store.proofSettings,before); XCTAssertFalse(store.hasToneDraft)
      store.beginProof(); store.proofWorkspace?.settings.simulateBlack=true; store.commitProof()
      XCTAssertTrue(store.proofSettings.enabled); XCTAssertTrue(store.proofSettings.simulateBlack); XCTAssertNil(store.proofWorkspace)
      XCTAssertEqual(store.document,original); XCTAssertTrue(store.session.undoStack.isEmpty); XCTAssertFalse(document.isDocumentEdited)
    }
  }
  @MainActor func testInvalidConfigurationIsAtomicAndCustomProfileRoundTrips() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      try service.share(document); let store=document.store, before=store.proofSettings
      for settings:[String:Any] in [["notASetting":true],["warningOpacity":2],["device":"custom","profile":"invalid"],["preserveNumbers":true],["device":"sRGB","plate":"cyan"]] {
        let status=try await helper.edit(service,document,"proof.configure",["settings":settings]); XCTAssertGreaterThanOrEqual(status,400); XCTAssertEqual(store.proofSettings,before)
      }
      let data=try NativeModeProfile.standard(.rgb,depth:.u16)
      let status=try await helper.edit(service,document,"proof.configure",["settings":["device":"custom","profile":data.base64EncodedString(),"profileName":"Owned sRGB","enabled":true,"preserveNumbers":true]])
      XCTAssertEqual(status,200); XCTAssertEqual(store.proofSettings.profile,data)
      let roundtrip=try JSONDecoder().decode(ProofSettings.self,from:JSONEncoder().encode(store.proofSettings)); XCTAssertEqual(roundtrip,store.proofSettings)
      let revokedID = try XCTUnwrap(service.shares.first?.id); service.revoke(revokedID)
      let failed=try await helper.request(service,path:"/v1/documents/\(revokedID)/proof-preview.png"); XCTAssertEqual(failed.0.statusCode,404)
    }
  }
  @MainActor func testEditingInvalidatesPreservedProofWithoutFreezingCanvas() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      let store=document.store
      var source=store.document; source.layers[0].content = .raster(try Surface(width:4,height:3,fill:Pixel(0.3,0.6,0.8)))
      source=try source.convertingMode(.init(mode:.cmyk,depth:.u16)); store.session=EditorSession(document:source)
      var settings=ProofSettings(); settings.enabled=true; settings.preserveNumbers=true
      try store.setProof(settings); await store.renderTask?.value; XCTAssertNil(store.proofDisplayError)
      var edited=store.document; edited.layers[0].opacity=0.5; store.session=EditorSession(document:edited); store.render(); await store.renderTask?.value
      XCTAssertNotNil(store.proofDisplayError); XCTAssertEqual(store.document,edited); XCTAssertEqual(store.surface,try Renderer.composite(edited))
      XCTAssertNil(store.error)
      settings.preserveNumbers=false; try store.setProof(settings); await store.renderTask?.value; XCTAssertNil(store.proofDisplayError)
    }
  }
  @MainActor func testCustomProofSheetFitsAndCapturesOffscreen() async throws {
    _ = NSApplication.shared
    let document=try CraftNSDocument.blankModel(width:4,height:3,background:.white)
    let store=EditorStore(document:document); defer { store.renderTask?.cancel() }
    store.beginProof(); await store.renderTask?.value
    let model=try XCTUnwrap(store.proofWorkspace)
    let view=NSHostingView(rootView:ProofSheet(store:store,model:model))
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:470,height:550),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false; window.appearance=NSAppearance(named:.darkAqua); window.contentView=view
    defer { window.close(); store.cancelProof() }
    view.frame=NSRect(x:0,y:0,width:470,height:550); view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
    XCTAssertLessThanOrEqual(view.fittingSize.width,470); XCTAssertLessThanOrEqual(view.fittingSize.height,550)
    let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds)); view.cacheDisplay(in:view.bounds,to:bitmap)
    let bytes=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    try bytes.write(to:root.appendingPathComponent("artifacts/runs/20261028T181113Z-223-proofing/proof-controls-\(UUID()).png"))
  }
  @MainActor func testFactoryProofMenusAndShortcutsAreBound() throws {
    let helper=PhotoshopMenuTests()
    try helper.withMenus { app,menu in
      let items=helper.allItems(menu)
      for (title,modifiers) in [("Proof Colors",NSEvent.ModifierFlags.command),("Gamut Warning",[.command,.shift])] {
        let item=try XCTUnwrap(items.first{$0.identifier?.rawValue == "View > " + title})
        XCTAssertEqual(item.action,#selector(AppDelegate.proofCommand(_:))); XCTAssertEqual(item.keyEquivalent,"y"); XCTAssertEqual(item.keyEquivalentModifierMask,modifiers)
        XCTAssertFalse(app.validateMenuItem(item))
      }
      for name in AppDelegate.proofMenus.keys {
        let item=try XCTUnwrap(items.first{$0.identifier?.rawValue == "View > Proof Setup > " + name}); XCTAssertEqual(item.action,#selector(AppDelegate.proofCommand(_:)))
      }
    }
  }
}
