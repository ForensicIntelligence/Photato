import AppKit
import SwiftUI
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class PeopleWorkspace {
  var cacheID = UUID()
  var source: ObjectFinderSource?
  var scene: PeopleScene?
  var busy = false
  var error: String?
  var presented = false
  var selectedIDs = Set<Int>()
  var selectedFeatures: Set<PeopleFeature> = [.wholePerson]
  var hoveredFeature = PeopleFeature.wholePerson
  var hoveredID: Int?
  var image: CGImage?
  @ObservationIgnored var task: Task<Void,Never>?
  @ObservationIgnored var overlayTask: Task<Void,Never>?
  @ObservationIgnored var overlayID = UUID()
  func cancel() {
    task?.cancel(); task = nil; overlayTask?.cancel(); overlayTask = nil
    cacheID = UUID(); overlayID = UUID(); source = nil; scene = nil; busy = false
    error = nil; selectedIDs = []; selectedFeatures = [.wholePerson]; hoveredID = nil; hoveredFeature = .wholePerson; image = nil
  }
  func close() { presented = false; cancel() }
}

extension EditorStore {
  var canSelectPeople: Bool { canFindObjects }
  func invalidatePeopleIfNeeded() {
    if let source = peopleWorkspace.source, source != objectFinderSource { peopleWorkspace.cancel() }
  }
  func stopPeopleDetection() {
    guard peopleWorkspace.source != nil || peopleWorkspace.busy else { return }
    peopleWorkspace.cancel(); peopleWorkspace.source = objectFinderSource
    peopleWorkspace.error = "Person detection cancelled. Refresh to try again."
  }
  func openPeoplePicker() {
    guard canSelectPeople else { return }
    peopleWorkspace.presented = true; clearObjectHover(); requestPeople()
  }
  func requestPeople(force: Bool = false) {
    guard canSelectPeople else { return }
    let key = objectFinderSource
    if !force, peopleWorkspace.source == key { return }
    peopleWorkspace.cancel(); peopleWorkspace.source = key; peopleWorkspace.busy = true
    let identity = peopleWorkspace.cacheID, original = document, detector = peopleDetector, featureDetector = peopleFeaturesDetector
    peopleWorkspace.task = Task { [weak self] in
      let worker = Task.detached(priority:.userInitiated) {
        try await PeopleScene.detect(original,layerID:key.layerID,sampleAllLayers:key.sampleAllLayers,detector:detector,featuresDetector:featureDetector)
      }
      do {
        let scene = try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
        try Task.checkCancellation()
        guard let self, self.peopleWorkspace.cacheID == identity, self.objectFinderSource == key else { return }
        self.peopleWorkspace.scene = scene; self.peopleWorkspace.busy = false
      } catch {
        guard let self, self.peopleWorkspace.cacheID == identity else { return }
        self.peopleWorkspace.busy = false
        if !(error is CancellationError) { self.peopleWorkspace.error = error.localizedDescription }
      }
    }
  }
  func hoverPerson(_ id: Int?, feature: PeopleFeature = .wholePerson) {
    invalidatePeopleIfNeeded()
    let workspace = peopleWorkspace
    guard workspace.hoveredID != id || workspace.hoveredFeature != feature else { return }
    workspace.overlayTask?.cancel(); workspace.overlayID = UUID(); workspace.image = nil; workspace.hoveredID = id; workspace.hoveredFeature = feature
    guard let id, let scene = workspace.scene, scene.people.contains(where:{$0.instanceID == id}), scene.availableFeatures.contains(feature) else { workspace.hoveredID = nil; return }
    clearObjectHover()
    let cacheID = workspace.cacheID, overlayID = workspace.overlayID, color = objectFinderColor
    workspace.overlayTask = Task { [weak self] in
      let worker = Task.detached(priority:.userInitiated) { try SelectionToolPreparation.overlay(scene.coverage(instanceIDs:[id],hardEdge:false,features:[feature]),color:color) }
      do {
        let image = try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
        guard !Task.isCancelled, let self, self.peopleWorkspace.cacheID == cacheID, self.peopleWorkspace.overlayID == overlayID else { return }
        self.peopleWorkspace.image = image
      } catch { /* A superseded hover must not replace the current overlay. */ }
    }
  }
  @discardableResult func selectPeople(_ ids: [Int], mode: SelectionMode? = nil, hardEdge: Bool? = nil, features: [PeopleFeature]? = nil) -> Task<Void,Never>? {
    guard canSelectPeople, peopleWorkspace.source == objectFinderSource, let scene = peopleWorkspace.scene else { return nil }
    let mode=mode ?? selectionMode,hard=hardEdge ?? objectFinderHardEdge,features=features ?? peopleWorkspace.selectedFeatures.sorted{$0.rawValue<$1.rawValue}
    performGeometry(label:"Select People",allowAuxiliary:true,prepare:{_ in try scene.command(instanceIDs:ids,mode:mode,hardEdge:hard,features:features)})
    return geometryTask
  }
  func selectPeopleAndRefine() {
    guard canSelectPeople, peopleWorkspace.source == objectFinderSource, let scene = peopleWorkspace.scene else { return }
    let cacheID=peopleWorkspace.cacheID,ids=peopleWorkspace.selectedIDs.sorted(),features=peopleWorkspace.selectedFeatures.sorted{$0.rawValue<$1.rawValue},mode=selectionMode,hard=objectFinderHardEdge
    performGeometry(label:"Select People",allowAuxiliary:true,prepare:{_ in try scene.command(instanceIDs:ids,mode:mode,hardEdge:hard,features:features)},onSuccess:{ [weak self] in
      guard let self, self.peopleWorkspace.cacheID == cacheID, self.canBeginSelectMask else { return }
      self.peopleWorkspace.presented = false; self.hoverPerson(nil); self.beginSelectMask()
    })
  }
  func togglePeopleFeature(_ feature:PeopleFeature) {
    if feature == .wholePerson { peopleWorkspace.selectedFeatures=[.wholePerson] }
    else {
      peopleWorkspace.selectedFeatures.remove(.wholePerson)
      if !peopleWorkspace.selectedFeatures.insert(feature).inserted {peopleWorkspace.selectedFeatures.remove(feature)}
    }
  }

}

struct PeoplePickerView: View {
  @Bindable var store: EditorStore
  var body: some View {
    VStack(alignment:.leading,spacing:12) {
      HStack { Text("Select People").font(.headline); Spacer()
        Button { store.requestPeople(force:true) } label: { Image(systemName:"arrow.clockwise") }.help("Detect people again").disabled(!store.canSelectPeople)
        Button { store.peopleWorkspace.close() } label: { Image(systemName:"xmark") }.help("Close")
      }
      if store.peopleWorkspace.busy { HStack { ProgressView().controlSize(.small); Text("Detecting people…"); Spacer(); Button("Cancel"){store.stopPeopleDetection()} } }
      if let error = store.peopleWorkspace.error { Text(error).foregroundStyle(.secondary) }
      if let scene = store.peopleWorkspace.scene {
        if scene.people.isEmpty { Text("No people found. Try another image or make a selection manually.").foregroundStyle(.secondary) }
        else {
          Text("Choose one or more people. Hover to preview.").font(.caption).foregroundStyle(.secondary)
          ScrollView {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:90))],spacing:10) {
              ForEach(Array(scene.people.enumerated()),id:\.element.instanceID) { index, person in
                Button {
                  if !store.peopleWorkspace.selectedIDs.insert(person.instanceID).inserted { store.peopleWorkspace.selectedIDs.remove(person.instanceID) }
                } label: {
                  VStack {
                    if let image = scene.thumbnails[person.instanceID] { Image(decorative:image,scale:1).resizable().scaledToFit().frame(width:80,height:80) }
                    Label("Person \(index+1)",systemImage:store.peopleWorkspace.selectedIDs.contains(person.instanceID) ? "checkmark.circle.fill":"circle")
                  }.frame(width:96,height:110).background(store.peopleWorkspace.selectedIDs.contains(person.instanceID) ? Color.accentColor.opacity(0.25):Color.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius:6))
                }.buttonStyle(.plain).onHover { store.hoverPerson($0 ? person.instanceID:nil) }
              }
            }
          }.frame(height:240)
          HStack { Button("Select All"){store.peopleWorkspace.selectedIDs=Set(scene.people.map(\.instanceID))};Button("Clear"){store.peopleWorkspace.selectedIDs=[]} }
          LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading) {
            ForEach(PeopleFeature.allCases,id:\.self) { feature in
              Toggle(feature.label,isOn:Binding(get:{store.peopleWorkspace.selectedFeatures.contains(feature)},set:{_ in store.togglePeopleFeature(feature)}))
                .toggleStyle(.checkbox).disabled(!scene.availableFeatures.contains(feature))
                .onHover {store.hoverPerson($0 ? store.peopleWorkspace.selectedIDs.sorted().first:nil,feature:feature)}
            }
          }
          if scene.featureMap == nil { Text(scene.featureError ?? "The optional person feature model is not included in this build.").font(.caption).foregroundStyle(.secondary) }
          Text("Eyebrows, eyes, lips, teeth and beard masks are not available yet.").font(.caption).foregroundStyle(.secondary)
          Picker("Selection",selection:$store.selectionMode){ForEach(SelectionMode.allCases,id:\.self){Text($0.rawValue).tag($0)}}
          Toggle("Hard Edge",isOn:$store.objectFinderHardEdge)
          HStack {
            Button("Select and Mask…"){store.selectPeopleAndRefine()}.disabled(!store.canBeginSelectMask)
            Spacer()
            Button("Apply"){store.selectPeople(store.peopleWorkspace.selectedIDs.sorted())}.keyboardShortcut(.defaultAction)
          }.disabled(store.peopleWorkspace.selectedIDs.isEmpty || store.peopleWorkspace.selectedFeatures.isEmpty || !store.canSelectPeople)
        }
      } else if !store.peopleWorkspace.busy && store.peopleWorkspace.error == nil { Button("Detect People"){store.requestPeople()} }
    }.padding(16).frame(width:380).onDisappear { store.peopleWorkspace.close() }
  }
}
