import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

struct PatternDialogSource:Sendable {
  let documentID,session,generation,libraryID,libraryRevision:UUID
  @MainActor init(_ store:EditorStore) {
    documentID=store.document.id;session=store.sessionGeneration;generation=store.layerPanelGeneration
    libraryID=store.patterns.identity;libraryRevision=store.patterns.revision
  }
  @MainActor func matches(_ store:EditorStore)->Bool {
    store.document.id==documentID && store.sessionGeneration==session && store.layerPanelGeneration==generation
      && store.patterns.identity==libraryID && store.patterns.revision==libraryRevision
  }
}
@MainActor extension EditorStore {
  var selectedPatternGroup:UUID? {
    let selected=patterns.state.nodes.filter{patterns.state.selectedNodes.contains($0.id)}
    if selected.count==1,selected[0].isGroup{return selected[0].id}
    let parents=Set(selected.map(\.parentID));return parents.count==1 ? selected.first?.parentID:nil
  }
  var selectedPatternSiblingParent:UUID? {
    let selected=patterns.state.nodes.filter{patterns.state.selectedNodes.contains($0.id)}
    return Set(selected.map(\.parentID)).count==1 ? selected.first?.parentID:nil
  }
  func beginPatternGroup(parent:UUID?=nil) {
    guard !patterns.busy,!geometryBusy else{return}
    patternNameDraft = .init(purpose:.group(parent),name:"New Group",source:PatternDialogSource(self))
  }
  func beginPatternRename(_ id:UUID) {
    guard !patterns.busy,!geometryBusy,let name=patterns.state.name(id)else{return}
    patternNameDraft = .init(purpose:.renameNode(id),name:name,source:PatternDialogSource(self))
  }
  @discardableResult func mutatePatterns(_ mutation:PatternLibraryMutation)->Task<Void,Never> {
    let source=PatternDialogSource(self)
    return patternAction{[weak self]in
      guard let self else{return}
      _=try await self.patterns.mutate(mutation,authorize:{[weak self]in self.map{source.matches($0)} ?? false})
    }
  }
  @discardableResult func commitPatternName(_ draft:PatternNameDraft,name:String)->Task<Void,Never>? {
    patternNameDraft=nil
    guard draft.source?.matches(self) != false else{error="The pattern dialog source changed. Try again.";return nil}
    switch draft.purpose {
    case .define:definePattern(name:name);return geometryTask
    case .group(let parent):return mutatePatterns(.createGroup(name,parent:parent))
    case .renameNode(let id):return mutatePatterns(.rename(id,name))
    case .rename(let id):return patternAction{[weak self]in try await self?.patterns.rename(id,to:name)}
    }
  }
}

private struct PatternDisplayBlock:Identifiable {
  let entries:[PatternLibraryNode]
  var id:UUID{entries[0].id}
  var group:PatternLibraryNode?{entries.count==1 && entries[0].isGroup ? entries[0]:nil}
  static func blocks(_ nodes:[PatternLibraryNode])->[Self] {
    var result=[Self](),leaves=[PatternLibraryNode]()
    func flush(){if !leaves.isEmpty{result.append(.init(entries:leaves));leaves=[]}}
    for node in nodes{if node.isGroup{flush();result.append(.init(entries:[node]))}else{leaves.append(node)}}
    flush();return result
  }
}
@MainActor struct PatternLibraryPanel:View {
  @Bindable var store:EditorStore
  @State private var search=""
  var body:some View {
    VStack(spacing:8) {
      HStack {
        TextField("Search patterns",text:$search).textFieldStyle(.roundedBorder)
        Menu {
          Button("New Pattern Group…"){store.beginPatternGroup(parent:store.selectedPatternGroup)}
          Button("Rename…"){if let id=store.patterns.state.selectedNodes.first{store.beginPatternRename(id)}}.disabled(store.patterns.state.selectedNodes.count != 1)
          Button("Duplicate"){store.mutatePatterns(.duplicate(store.patterns.state.selectedNodes,parent:store.selectedPatternSiblingParent,before:nil))}.disabled(store.patterns.state.selectedNodes.isEmpty)
          Button("Delete"){store.mutatePatterns(.delete(store.patterns.state.selectedNodes))}.disabled(store.patterns.state.selectedNodes.isEmpty)
          Button("Move to Root"){store.mutatePatterns(.move(store.patterns.state.selectedNodes,parent:nil,before:nil))}.disabled(store.patterns.state.selectedNodes.isEmpty)
          Divider()
          Button("Import Patterns…"){store.importPatterns()}
          Button("Export Selected Patterns…"){store.exportPatterns(all:false)}.disabled(store.patterns.state.selectedNodes.isEmpty)
          Button("Export All Patterns…"){store.exportPatterns(all:true)}.disabled(store.patterns.state.nodes.isEmpty)
          Divider()
          Button("Restore Built-in Patterns"){store.patternAction{try await store.patterns.resetBuiltins()}}
          Button("Legacy Patterns and More"){ }.disabled(true)
        }label:{Image(systemName:"line.3.horizontal")}.menuStyle(.borderlessButton).frame(width:22)
      }
      ScrollView {
        PatternLibraryBranch(store:store,parent:nil,search:search)
        Text("Drop here to move to root").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:30)
          .modifier(PatternLibraryDropTarget(store:store,parent:nil,before:nil))
      }
      if let selected=store.patterns.selected{Text("\(selected.displayName) · \(selected.surface.width) × \(selected.surface.height)").lineLimit(1).font(.caption).foregroundStyle(.secondary)}
      if let error=store.patterns.error{Text(error).font(.caption).foregroundStyle(.orange)}
      HStack {
        Text("\(store.patterns.state.selectedNodes.count) selected").font(.caption).foregroundStyle(.secondary);Spacer()
        Button{store.beginDefinePattern()}label:{Image(systemName:"plus.square")}.help("Define Pattern from this document")
        Button{store.beginPatternGroup(parent:store.selectedPatternGroup)}label:{Image(systemName:"folder.badge.plus")}.help("New Pattern Group")
        Button{store.mutatePatterns(.delete(store.patterns.state.selectedNodes))}label:{Image(systemName:"trash")}.disabled(store.patterns.state.selectedNodes.isEmpty).help("Delete selected patterns or groups")
      }.buttonStyle(.plain)
      if store.patterns.busy{ProgressView().controlSize(.small)}
    }.padding(9).disabled(store.patterns.busy || store.geometryBusy)
  }
}
@MainActor private struct PatternLibraryBranch:View {
  @Bindable var store:EditorStore
  let parent:UUID?
  let search:String
  var matching:[PatternLibraryNode] {
    store.patterns.state.children(of:parent).filter { node in
      search.isEmpty || store.patterns.state.descendants(of:node.id).contains{ id in
        store.patterns.state.name(id)?.localizedCaseInsensitiveContains(search)==true
      }
    }
  }
  var body:some View {
    VStack(alignment:.leading,spacing:6) {
      ForEach(PatternDisplayBlock.blocks(matching)){block in
        if let group=block.group {
          VStack(alignment:.leading,spacing:5) {
            Color.clear.frame(height:5).contentShape(Rectangle()).modifier(PatternLibraryDropTarget(store:store,parent:parent,before:group.id))
            HStack(spacing:5) {
              Button{do{try store.patterns.collapse(group.id,!store.patterns.state.collapsed.contains(group.id))}catch{store.error=error.localizedDescription}}label:{Image(systemName:store.patterns.state.collapsed.contains(group.id) ? "chevron.right":"chevron.down").frame(width:12)}.help("Expand or collapse \(group.name)")
              Button{select(group)}label:{Label(group.name,systemImage:"folder").frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())}
                .onDrag{PatternLibraryDrag.provider(store:store,nodeID:group.id)}
            }.buttonStyle(.plain).padding(5)
              .background(store.patterns.state.selectedNodes.contains(group.id) ? StudioTheme.selected:.clear)
              .modifier(PatternLibraryDropTarget(store:store,parent:group.id,before:nil))
              .contextMenu{Button("New Pattern Group…"){store.beginPatternGroup(parent:group.id)};Button("Rename Group…"){store.beginPatternRename(group.id)};Button("Delete Group"){store.mutatePatterns(.delete([group.id]))}}
            if !store.patterns.state.collapsed.contains(group.id) || !search.isEmpty {
              AnyView(PatternLibraryBranch(store:store,parent:group.id,search:search)).padding(.leading,12)
            }
          }
        }else{
          LazyVGrid(columns:[GridItem(.adaptive(minimum:46),spacing:7)],spacing:7) {
            ForEach(block.entries){node in
              if let asset=store.patterns.items.first(where:{$0.id==node.patternID}) {
                Button{select(node);if NSEvent.modifierFlags.intersection([.shift,.command]).isEmpty{store.choosePattern(asset,preservingLibrarySelection:true)}}label:{
                  PatternSwatch(pattern:asset).frame(height:44).overlay(Rectangle().stroke(store.patterns.state.selectedNodes.contains(node.id) ? StudioTheme.accent:.white.opacity(0.2),lineWidth:2))
                }.buttonStyle(.plain).help("\(asset.displayName) · \(asset.surface.width) × \(asset.surface.height)").accessibilityLabel(asset.displayName)
                  .onDrag{PatternLibraryDrag.provider(store:store,nodeID:node.id)}
                  .modifier(PatternLibraryDropTarget(store:store,parent:parent,before:node.id))
                  .contextMenu{Button("Rename Pattern…"){store.beginPatternRename(node.id)};Button("Duplicate Pattern"){store.mutatePatterns(.duplicate([node.id],parent:parent,before:nil))};Button("Delete Pattern"){store.mutatePatterns(.delete([node.id]))}}
              }
            }
          }.padding(2)
        }
      }
    }
  }
  func select(_ node:PatternLibraryNode){do{try store.patterns.click(node.id,modifiers:NSEvent.modifierFlags)}catch{store.error=error.localizedDescription}}
}
