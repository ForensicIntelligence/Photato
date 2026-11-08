import Foundation
import Observation
import SwiftUI
import PhotoCraftCore

enum SkyGroupFilter:Hashable {
  case all,ungrouped,group(UUID)
  var groupID:UUID?{if case .group(let id)=self{return id};return nil}
  var apiValue:String{switch self{case .all:return "all";case .ungrouped:return "ungrouped";case .group(let id):return id.uuidString}}
  func contains(_ preset:SkyPreset)->Bool{switch self{case .all:return true;case .ungrouped:return preset.groupID==nil;case .group(let id):return preset.groupID==id}}
}
@MainActor @Observable final class SkyGroupDraft:Identifiable {
  enum Operation{case create,rename,delete}
  let id=UUID()
  let operation:Operation
  let groupID:UUID?
  let libraryRevision:Int
  let sourceState:SkyState
  let filter:SkyGroupFilter
  var name:String
  var error:String?
  init(_ operation:Operation,model:SkyWorkspace){
    let selected=model.groupFilter.groupID
    self.operation=operation;filter=model.groupFilter;groupID=selected;libraryRevision=model.library.revision;sourceState=model.state
    name=operation == .create ? "":model.library.groups.first{$0.id==selected}?.name ?? ""
  }
}
@MainActor extension SkyWorkspace {
  var visibleSkies:[SkyPreset]{library.skies.filter{groupFilter.contains($0)}}
  func filterSkies(_ filter:SkyGroupFilter){
    guard canManageSkyGroups,filter.groupID.map({id in library.groups.contains{$0.id==id}}) ?? true else{return}
    groupFilter=filter
    if state.sourceLayerID==nil,!visibleSkies.contains(where:{$0.id==state.skyID}){chooseSky(visibleSkies.first?.id)}
  }
  func beginSkyGroup(_ operation:SkyGroupDraft.Operation){
    guard canManageSkyGroups,operation == .create || groupFilter.groupID.map({id in library.groups.contains{$0.id==id}}) == true else{return}
    groupDraft=SkyGroupDraft(operation,model:self)
  }
  func cancelSkyGroup(_ draft:SkyGroupDraft){if groupDraft === draft{groupDraft=nil}}
  @discardableResult func confirmSkyGroup(_ draft:SkyGroupDraft,removeSkies:Bool=false)->Bool {
    guard groupDraft === draft else{return false}
    guard ready,library.revision==draft.libraryRevision,state==draft.sourceState,groupFilter==draft.filter else{
      groupDraft=nil;error="The sky library or selection changed. Open the group controls again.";return false
    }
    do{
      switch draft.operation {
      case .create:let id=try library.createGroup(draft.name);groupDraft=nil;filterSkies(.group(id))
      case .rename:try library.renameGroup(draft.groupID!,draft.name);groupDraft=nil
      case .delete:try library.deleteGroup(draft.groupID!,removeSkies:removeSkies);groupDraft=nil;filterSkies(removeSkies ? .all:.ungrouped)
      }
      return true
    }catch{draft.error=error.localizedDescription;return false}
  }
  func moveSelectedSky(to groupID:UUID?){
    guard canRenameSky,let id=state.skyID else{return}
    do{try library.move([id],to:groupID);if let preset=try? library.preset(id),!groupFilter.contains(preset){chooseSky(visibleSkies.first?.id)}}
    catch{self.error=error.localizedDescription}
  }
}
struct SkyGroupControls:View {
  @Bindable var model:SkyWorkspace
  var body:some View {
    VStack(alignment:.leading,spacing:8){
      Picker("Group",selection:Binding(get:{model.groupFilter},set:{model.filterSkies($0)})){
        Text("All Skies").tag(SkyGroupFilter.all);Text("Ungrouped").tag(SkyGroupFilter.ungrouped)
        ForEach(model.library.groups){Text($0.name).tag(SkyGroupFilter.group($0.id))}
      }
      Menu("Manage Groups"){
        Button("Create New Sky Group…"){model.beginSkyGroup(.create)}.disabled(model.library.groups.count>=64)
        Button("Rename Sky Group…"){model.beginSkyGroup(.rename)}.disabled(model.groupFilter.groupID==nil)
        Button("Delete Sky Group…"){model.beginSkyGroup(.delete)}.disabled(model.groupFilter.groupID==nil)
      }
      if let id=model.state.skyID,let preset=try? model.library.preset(id){
        Picker("Move Sky To",selection:Binding(get:{preset.groupID},set:{model.moveSelectedSky(to:$0)})){
          Text("Ungrouped").tag(UUID?.none)
          ForEach(model.library.groups){Text($0.name).tag(Optional($0.id))}
        }.disabled(!model.canRenameSky)
      }
    }.disabled(!model.canManageSkyGroups)
  }
}
struct SkyGroupSheet:View {
  @Bindable var model:SkyWorkspace
  @Bindable var draft:SkyGroupDraft
  @FocusState private var editingName:Bool
  var title:String{switch draft.operation{case .create:return "Create New Sky Group";case .rename:return "Rename Sky Group";case .delete:return "Delete Sky Group"}}
  var body:some View {
    VStack(alignment:.leading,spacing:14){
      Text(title).font(.headline)
      if draft.operation == .delete {
        Text("Remove “\(draft.name)”? Choose whether to keep its skies in Ungrouped or delete them from the library.")
        Text("Existing document layers keep their imported pixels.").font(.caption).foregroundStyle(.secondary)
      }else{
        TextField("Name",text:$draft.name).textFieldStyle(.roundedBorder).focused($editingName)
          .onSubmit{model.confirmSkyGroup(draft)}
      }
      if let error=draft.error{Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)}
      HStack{
        Button("Cancel"){model.cancelSkyGroup(draft)}.keyboardShortcut(.cancelAction);Spacer()
        if draft.operation == .delete {
          Button("Keep Skies"){model.confirmSkyGroup(draft)}
          Button("Delete Group and Skies",role:.destructive){model.confirmSkyGroup(draft,removeSkies:true)}
        }else{
          Button("OK"){model.confirmSkyGroup(draft)}.keyboardShortcut(.defaultAction)
            .disabled(draft.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        }
      }
    }.padding(20).frame(width:draft.operation == .delete ? 480:380)
      .task{editingName=draft.operation != .delete}
      .onDisappear{model.cancelSkyGroup(draft)}
  }
}
