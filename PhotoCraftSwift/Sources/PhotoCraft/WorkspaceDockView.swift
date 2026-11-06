import AppKit
import SwiftUI

extension WorkspaceView {
  var canOrganizePanels: Bool {
    (workspace?.owner?.canChangeDocument
      ?? (!store.hasToneDraft && store.transformDraft == nil && !store.geometryBusy))
      && store.workspaceLibrary.error == nil
  }

  var inspector: some View { inspector(columnID: PanelDockColumn.primaryID) }

  func inspector(columnID: String) -> some View {
    GeometryReader { geometry in
      let library = store.workspaceLibrary
      let sizing = PanelDockSizing(
        layout: library.layout, height: geometry.size.height, columnID: columnID)
      VStack(spacing: 0) {
        PanelDockDropZone(
          library: library, before: sizing.rows.first?.id, canOrganize: canOrganizePanels,
          tearOff: workspace?.owner?.panelDragging,
          destination: .column(columnID, beforeGroup: sizing.rows.first?.id)
        )
        .frame(height: 12)
        .overlay(alignment: .trailing) {
          Button {
            library.setColumnCollapsed(columnID, true)
          } label: {
            Image(
              systemName: library.panelDock.orderedColumns.first { $0.id == columnID }?.side
                == .left
                ? "chevron.left.2" : "chevron.right.2"
            ).font(.system(size: 7))
          }.buttonStyle(.plain).padding(.trailing, 7).accessibilityLabel("Collapse panels")
            .contextMenu { dockColumnMenu(columnID) }
        }
        ForEach(Array(sizing.rows.enumerated()), id: \.element.id) { index, row in
          VStack(spacing: 0) {
            dockHeader(row.group)
            if !row.group.collapsed,
              let selected = library.panelDock.selectedPanel(
                in: row.group, visibility: store.workspace)
            {
              dockContent(selected).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }.frame(height: row.height).clipped()
          if row.gap > 0 {
            let resizable =
              !row.group.collapsed
              && sizing.rows.dropFirst(index + 1).contains { !$0.group.collapsed }
            PanelDockDropZone(
              library: library, before: sizing.rows[index + 1].id, canOrganize: canOrganizePanels,
              tearOff: workspace?.owner?.panelDragging,
              destination: .column(columnID, beforeGroup: sizing.rows[index + 1].id),
              beginResize: resizable ? { dividerStartingHeights = sizing.heights } : nil,
              resize: resizable
                ? { delta in
                  library.resizePanelGroup(
                    row.id, startingHeights: dividerStartingHeights ?? sizing.heights,
                    by: Double(delta))
                } : nil,
              endResize: resizable ? { dividerStartingHeights = nil } : nil
            ).frame(height: row.gap).background(StudioTheme.tab)
          }
        }
        PanelDockDropZone(
          library: library, before: nil, canOrganize: canOrganizePanels,
          tearOff: workspace?.owner?.panelDragging,
          destination: .column(columnID, beforeGroup: nil)
        )
        .frame(minHeight: 0, maxHeight: .infinity)
      }.background(StudioTheme.panel)
        .overlay(alignment: .bottom) {
          PanelDockDropZone(
            library: library, before: nil, canOrganize: canOrganizePanels,
            tearOff: workspace?.owner?.panelDragging,
            destination: .column(columnID, beforeGroup: nil)
          ).frame(
            height: 3)
        }
    }
  }

  func dockHeader(_ group: PanelDockGroup) -> some View {
    let library = store.workspaceLibrary
    let panels = library.panelDock.visiblePanels(in: group, visibility: store.workspace)
    let selected = library.panelDock.selectedPanel(in: group, visibility: store.workspace)
    return HStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 0) {
            ForEach(panels, id: \.self) { panel in
              PanelDockTab(
                library: library, group: group, panel: panel,
                selected: selected == panel, canOrganize: canOrganizePanels,
                tearOff: workspace?.owner?.panelDragging
              )
              .fixedSize(horizontal: true, vertical: false)
              .background(selected == panel ? StudioTheme.panel : StudioTheme.tab).id(panel)
            }
          }
        }.frame(minWidth: 0, maxWidth: .infinity)
          .onChange(of: selected) { _, panel in if let panel { proxy.scrollTo(panel) } }
      }
      PanelDockTab(
        library: library, group: group, panel: nil, selected: false, canOrganize: canOrganizePanels,
        tearOff: workspace?.owner?.panelDragging
      )
      .frame(width: 20)
      Menu {
        if selected == .layers {
          LayerEditingMenu(store: store)
          Divider()
          Menu("Panel Layout") { dockMenu(group, selected: selected) }
        } else if selected == .channels {
          ChannelsMenu(store: store)
          Divider()
          Button("Close") { library.closePanels([.channels]) }
          Button("Close Tab Group") { library.closePanels(group.panels) }
          Divider()
          Menu("Panel Layout") { dockMenu(group, selected: selected) }
        } else {
          dockMenu(group, selected: selected)
        }
      } label: {
        // The native menu reads NSImage's description again after a sheet closes.
        // SwiftUI's outer accessibility label alone is not retained through that rebuild.
        Image(nsImage: NSImage(
          systemSymbolName: "line.3.horizontal",
          accessibilityDescription: "\(selected?.rawValue ?? "Group") panel menu"
        )!).font(.system(size: 9))
      }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
        .accessibilityLabel("\(selected?.rawValue ?? "Group") panel menu")
    }.frame(height: 29).background(StudioTheme.tab)
  }

  @ViewBuilder func dockMenu(_ group: PanelDockGroup, selected: WorkspacePanel?) -> some View {
    let library = store.workspaceLibrary
    let allGroups = library.panelDock.visibleGroups(store.workspace)
    let groups = library.panelDock.groups(inColumn: group.dockColumnID, visibility: store.workspace)
    let index = groups.firstIndex { $0.id == group.id } ?? 0
    let movable = canOrganizePanels && !library.workspaceLocked
    Button(group.collapsed ? "Expand Panel Group" : "Collapse Panel Group") {
      library.togglePanelGroup(group.id)
    }
    if let selected {
      Menu("Move Panel to Group") {
        ForEach(allGroups.filter { $0.id != group.id }) { target in
          Button(target.panels.map(\.rawValue).joined(separator: " / ")) {
            library.movePanels(.panel(selected), to: .group(target.id, before: nil))
          }
        }
      }.disabled(!movable || allGroups.count < 2)
      Button("New Group from Panel") {
        library.movePanels(
          .panel(selected),
          to: .column(
            group.dockColumnID, beforeGroup: index + 1 < groups.count ? groups[index + 1].id : nil))
      }.disabled(!movable || group.panels.count < 2)
    }
    Menu("Move Group to Dock") {
      ForEach(library.panelDock.orderedColumns) { column in
        Button(
          "\(column.side == .left ? "Left" : "Right") Dock \(library.panelDock.orderedColumns.firstIndex { $0.id == column.id }! + 1)"
        ) {
          library.movePanels(.group(group.id), to: .column(column.id, beforeGroup: nil))
        }
      }
      Divider()
      Button("New Left Dock") {
        library.movePanels(.group(group.id), to: .newColumn(.left, before: nil))
      }
      Button("New Right Dock") {
        library.movePanels(.group(group.id), to: .newColumn(.right, before: nil))
      }
    }.disabled(!movable)
    if let selected, group.floatingFrame == nil || group.panels.count > 1 {
      Button("Float Panel") { floatPanelSource(.panel(selected)) }.disabled(!movable)
    }
    if group.floatingFrame != nil {
      Button("Dock Panel Group") { library.movePanels(.group(group.id), to: .beforeGroup(nil)) }
        .disabled(!movable)
    } else {
      Button("Float Panel Group") { floatPanelSource(.group(group.id)) }.disabled(!movable)
    }
    Menu("Stack Group Below") {
      ForEach(
        allGroups.filter { $0.floatingFrame != nil && $0.floatingHostID != group.floatingHostID }
      ) { target in
        Button(target.panels.map(\.rawValue).joined(separator: " / ")) {
          library.stackPanels(.group(group.id), hostID: target.floatingHostID, before: nil)
        }
      }
    }.disabled(
      !movable
        || !allGroups.contains {
          $0.floatingFrame != nil && $0.floatingHostID != group.floatingHostID
        })
    Button("Move Group Up") {
      if index > 0 { library.movePanels(.group(group.id), to: .beforeGroup(groups[index - 1].id)) }
    }.disabled(!movable || group.floatingFrame != nil || index == 0)
    Button("Move Group Down") {
      library.movePanels(
        .group(group.id), to: .beforeGroup(index + 2 < groups.count ? groups[index + 2].id : nil))
    }.disabled(!movable || group.floatingFrame != nil || index + 1 >= groups.count)
    Divider()
    if let selected { Button("Close") { library.closePanels([selected]) } }
    Button("Close Tab Group") { library.closePanels(group.panels) }
  }

  func floatPanelSource(_ source: PanelDockSource) {
    let library = store.workspaceLibrary
    let panel = library.panelDock.panels(for: source)?.first
    let column = library.panelDock.groups.first { panel.map($0.panels.contains) ?? false }?
      .dockColumnID
    let width = column.map { library.columnWidth($0) } ?? Double(dockWidth)
    let anchor =
      workspace?.owner?.applicationFrame?.window?.frame
      ?? NSRect(x: 100, y: 100, width: 1000, height: 700)
    store.workspaceLibrary.floatPanels(
      source,
      frame: FloatingPanelFrame(
        NSRect(x: anchor.maxX - width - 40, y: anchor.maxY - 400, width: width, height: 320)
      ))
  }

  @ViewBuilder func floatingPanelContent(_ id: String) -> some View {
    let library = store.workspaceLibrary
    GeometryReader { geometry in
      let dock = library.panelDock
      let groups = dock.floatingGroups(id)
      let expandedHeight = max(
        0,
        (groups.first?.floatingFrame?.height ?? geometry.size.height)
          - FloatingPanelWindow.titlebarHeight)
      let sizing = FloatingPanelStackSizing(
        dock: dock, hostID: id,
        visibility: store.workspace, expandedHeight: expandedHeight,
        visibleHeight: geometry.size.height)
      VStack(spacing: 0) {
        ForEach(Array(sizing.rows.enumerated()), id: \.element.id) { index, row in
          VStack(spacing: 0) {
            dockHeader(row.group)
            if !row.group.collapsed,
              let selected = dock.selectedPanel(in: row.group, visibility: store.workspace)
            {
              dockContent(selected).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }.frame(height: row.height).clipped()
          if row.gap > 0 {
            let resizable =
              !row.group.collapsed
              && sizing.rows.dropFirst(index + 1).contains { !$0.group.collapsed }
            PanelDockDropZone(
              library: library, before: sizing.rows[index + 1].id,
              canOrganize: canOrganizePanels, tearOff: workspace?.owner?.panelDragging,
              floatingHostID: id,
              beginResize: resizable ? { dividerStartingHeights = sizing.heights } : nil,
              resize: resizable
                ? { delta in
                  library.resizeFloatingGroup(
                    row.id, hostID: id,
                    startingHeights: dividerStartingHeights ?? sizing.heights, by: Double(delta))
                } : nil,
              endResize: resizable ? { dividerStartingHeights = nil } : nil
            ).frame(height: row.gap).background(StudioTheme.tab)
          }
        }
      }.overlay(alignment: .top) {
        PanelDockDropZone(
          library: library, before: sizing.rows.first?.id,
          canOrganize: canOrganizePanels, tearOff: workspace?.owner?.panelDragging,
          floatingHostID: id
        ).frame(height: 3)
      }.overlay(alignment: .bottom) {
        PanelDockDropZone(
          library: library, before: nil,
          canOrganize: canOrganizePanels, tearOff: workspace?.owner?.panelDragging,
          floatingHostID: id
        ).frame(height: 3)
      }.background(StudioTheme.panel)
    }
  }

  @ViewBuilder func dockContent(_ panel: WorkspacePanel) -> some View {
    if panel == .character || panel == .paragraph {
      TypographyPanel(store: store, panel: panel)
    } else {
      nonTypographyDockContent(panel)
        .disabled(floatingPanelGroup != nil && workspace?.owner?.canChangeDocument == false)
    }
  }

  @ViewBuilder private func nonTypographyDockContent(_ panel: WorkspacePanel) -> some View {
    if panel == .history {
      HistoryPanel(store: store)
    } else if panel == .cloneSource {
      ScrollView {
        CloneSourcePanel(state: store.cloneState, target: store, embedded: true)
      }
    } else if let tab = ColorPanelTab(rawValue: panel.rawValue) {
      colorPanelContent(tab)
    } else if let tab = PropertiesTab(rawValue: panel.rawValue) {
      propertiesPanelContent(tab)
    } else if let tab = LayersTab(rawValue: panel.rawValue) {
      layersPanelContent(tab)
    }
  }
}
