import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

@MainActor @Observable final class GeneratedResultsBrowser {
  let inbox:GeneratedResultInbox,controller:CraftDocumentController
  var entries:[GeneratedResultInbox.Entry]=[]
  var selected:UUID?
  var busy=false
  var error:String?
  private var operation:UUID?
  @ObservationIgnored var task:Task<Void,Never>?
  init(inbox:GeneratedResultInbox,controller:CraftDocumentController){self.inbox=inbox;self.controller=controller}
  var selectedEntry:GeneratedResultInbox.Entry? {entries.first{$0.id==selected}}
  func cancel(){operation=nil;task?.cancel();task=nil;busy=false}
  func refresh() {
    cancel();let id=UUID(),inbox=inbox;operation=id;busy=true;error=nil
    task=Task{[weak self] in
      let worker=Task.detached(priority:.userInitiated){try inbox.list()}
      do{
        let entries=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});try Task.checkCancellation()
        guard let self,self.operation==id else{return};self.entries=entries
        if !entries.contains(where:{$0.id==self.selected}){self.selected=entries.first?.id}
        self.busy=false;self.task=nil
      }catch{
        guard let self,self.operation==id else{return};self.busy=false;self.task=nil
        if !(error is CancellationError){self.error=error.localizedDescription}
      }
    }
  }
  /// Publish a fresh unsaved document; the source document is never edited or rebound.
  @discardableResult func publish(_ model:CraftDocument,display:Bool)->CraftNSDocument {
    let document=CraftNSDocument(model:model);controller.addDocument(document);document.updateChangeCount(.changeDone)
    if display {document.makeWindowControllers();document.showWindows()};return document
  }
  func openSelected() {
    guard !busy,let selected,selectedEntry?.record != nil else{return}
    let id=UUID(),inbox=inbox;operation=id;busy=true;error=nil
    let closing=controller.documentClosing.state?.id,opening=controller.documentOpening.generation
    let maintenance=controller.recoveryMaintenance.generation,discovery=controller.recoveryDiscovery.generation
    task=Task{[weak self] in
      let worker=Task.detached(priority:.userInitiated){let stamp=try inbox.identity(selected),value=try inbox.load(selected);return (try GeneratedImageStorage.recoveredDocument(value.0,original:value.1),stamp)}
      do{
        let model=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});try Task.checkCancellation()
        guard let self,self.operation==id else{return}
        guard !self.controller.documentClosing.isActive,self.controller.documentClosing.state?.id==closing,
          !self.controller.documentOpening.isActive,!self.controller.documentOpening.hasPendingRequests,self.controller.documentOpening.generation==opening,
          !self.controller.recoveryIndex.isBusy,self.controller.recoveryMaintenance.generation==maintenance,self.controller.recoveryDiscovery.generation==discovery,
          (try? inbox.identity(selected))==model.1 else{throw CraftError.invalid("The saved result or document lifecycle changed. Try opening the original again.")}
        self.publish(model.0,display:true);self.busy=false;self.task=nil
      }catch{
        guard let self,self.operation==id else{return};self.busy=false;self.task=nil
        if !(error is CancellationError){self.error=error.localizedDescription}
      }
    }
  }
  func trashSelected() {
    guard !busy,let selected else{return}
    let id=UUID(),inbox=inbox;operation=id;busy=true;error=nil
    task=Task{[weak self] in
      let worker=Task.detached(priority:.userInitiated){try inbox.moveToTrash(selected)}
      do{
        try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});try Task.checkCancellation()
        guard let self,self.operation==id else{return};self.busy=false;self.refresh()
      }catch{
        guard let self,self.operation==id else{return};self.busy=false;self.task=nil
        if !(error is CancellationError){self.error=error.localizedDescription}
      }
    }
  }
}

private struct GeneratedResultsView:View {
  @Bindable var browser:GeneratedResultsBrowser
  var body:some View {
    VStack(spacing:0) {
      HSplitView {
        List(selection:$browser.selected) {
          ForEach(browser.entries){entry in
            VStack(alignment:.leading,spacing:4) {
              Text(entry.record?.initialPrompt ?? "Unreadable result").lineLimit(2)
              if let record=entry.record {Text(record.acceptedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)}
              if entry.error != nil {Label("Could not read saved image",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)}
            }.tag(entry.id).padding(.vertical,3)
          }
        }.frame(minWidth:210,idealWidth:270).accessibilityIdentifier("generatedResults.list")
        ScrollView {
          VStack(alignment:.leading,spacing:14) {
            if let entry=browser.selectedEntry {
              if let record=entry.record {
                Text(record.initialPrompt).textSelection(.enabled)
                LabeledContent("Created",value:record.acceptedAt.formatted(date:.abbreviated,time:.standard))
                LabeledContent("Service",value:record.provider)
                LabeledContent("Original",value:ByteCountFormatter.string(fromByteCount:Int64(record.originalByteCount),countStyle:.file))
                Text("This record keeps the initial prompt. The model, seed and final edited prompt have not been identified.").font(.caption).foregroundStyle(.secondary)
              }
              if let error=entry.error {Text(error).foregroundStyle(.secondary).textSelection(.enabled)}
            }else{Text("No saved generated images.").foregroundStyle(.secondary)}
            Text("Open Original creates a separate unsaved document. The source document is unchanged.").font(.caption).foregroundStyle(.secondary)
          }.frame(maxWidth:.infinity,alignment:.leading).padding(18)
        }.frame(minWidth:300)
      }
      Divider()
      HStack(spacing:12) {
        Button("Refresh"){browser.refresh()}.disabled(browser.busy).accessibilityIdentifier("generatedResults.refresh")
        if browser.busy {ProgressView().controlSize(.small)}
        Spacer()
        Button("Move to Trash"){browser.trashSelected()}.disabled(browser.busy || browser.selected==nil).accessibilityIdentifier("generatedResults.trash")
        Button("Open Original"){browser.openSelected()}.disabled(browser.busy || browser.selectedEntry?.record==nil).keyboardShortcut(.defaultAction).accessibilityIdentifier("generatedResults.open")
      }.padding(14)
      if let error=browser.error {Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding([.horizontal,.bottom],14)}
      Text("Originals are kept locally until you move them to Trash. No model is needed to open them.").font(.caption).foregroundStyle(.secondary).padding([.horizontal,.bottom],14)
    }.frame(minWidth:560,minHeight:360)
  }
}

@MainActor final class GeneratedResultsWindowController:NSWindowController,NSWindowDelegate {
  let browser:GeneratedResultsBrowser
  init(controller:CraftDocumentController,inbox:GeneratedResultInbox = .shared) {
    browser=GeneratedResultsBrowser(inbox:inbox,controller:controller)
    let window=PhotatoWindow(contentRect:.init(x:0,y:0,width:760,height:480),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
    window.title="Generated Results";window.isReleasedWhenClosed=false
    super.init(window:window);window.delegate=self;window.contentView=NSHostingView(rootView:GeneratedResultsView(browser:browser));window.contentMinSize = .init(width:560,height:360);window.center()
  }
  required init?(coder:NSCoder){nil}
  func present(){showWindow(nil);window?.makeKeyAndOrderFront(nil);browser.refresh()}
  func windowWillClose(_ notification:Notification){browser.cancel()}
}

@MainActor extension AppDelegate {
  @objc func generatedResults() {
    if generatedResultsWindow==nil {generatedResultsWindow=GeneratedResultsWindowController(controller:controller)}
    generatedResultsWindow?.present()
  }
}
