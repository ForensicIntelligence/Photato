import AppKit
import SwiftUI

extension WorkspacePanel {
  var dockSymbol: String {
    switch self {
    case .color: return "paintpalette"
    case .swatches: return "square.grid.3x3"
    case .gradients: return "rectangle.lefthalf.filled"
    case .patterns: return "checkerboard.rectangle"
    case .properties: return "slider.horizontal.3"
    case .adjustments: return "circle.lefthalf.filled"
    case .libraries: return "books.vertical"
    case .layers: return "square.3.layers.3d"
    case .channels: return "square.on.square"
    case .paths: return "point.topleft.down.curvedto.point.bottomright.up"
    case .history: return "clock.arrow.circlepath"
    case .cloneSource: return "seal"
    case .character: return "textformat"
    case .paragraph: return "text.alignleft"
    case .styles: return "square.stack.3d.up"
    }
  }
}

extension WorkspaceView {
  var workspaceColumns: some View {
    GeometryReader { geometry in
      let library = store.workspaceLibrary
      let toolWidth = store.workspace.tools ? (doubleTools ? 68.0 : 40.0) : 0
      let sizing = PanelDockColumnSizing(
        layout: library.layout,
        availableWidth: max(0, geometry.size.width - toolWidth - 240),
        preferredColumn: library.expandedDockColumnID)
      let left = sizing.columns.filter { $0.column.side == .left }
      let right = sizing.columns.filter { $0.column.side == .right }
      let dragging = workspace?.owner?.panelDragging.activePayload != nil
      HStack(spacing: 0) {
        if store.workspace.tools { toolRail }
        HStack(spacing: 0) {
          ForEach(Array(left.enumerated()), id: \.element.id) { index, column in
            dockColumnContent(column)
            dockColumnDivider(
              column,
              before: index + 1 < left.count ? left[index + 1].id : nil)
          }
        }.overlay(alignment: .leading) {
          if dragging && !left.isEmpty {
            newColumnTarget(.left, before: left.first?.id).frame(width: 6)
          }
        }
        documentColumn
          .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
          .overlay(alignment: .leading) {
            if dragging { newColumnTarget(.left, before: nil).frame(width: 6) }
          }
          .overlay(alignment: .trailing) {
            if dragging { newColumnTarget(.right, before: right.first?.id).frame(width: 6) }
          }
        if store.workspace.hasDock {
          if let first = right.first {
            dockColumnDivider(first, before: first.id)
          } else {
            Rectangle().fill(StudioTheme.line).frame(width: 4)
          }
          HStack(spacing: 0) {
            ForEach(Array(right.enumerated()), id: \.element.id) { index, column in
              if index > 0 { dockColumnDivider(column, before: column.id) }
              dockColumnContent(column)
            }
            if right.isEmpty && !store.workspace.collapsedDock && store.workspace.hasInspector {
              PanelDockDropZone(
                library: library, before: nil,
                canOrganize: canOrganizePanels, tearOff: workspace?.owner?.panelDragging,
                destination: .column(PanelDockColumn.primaryID, beforeGroup: nil)
              )
              .frame(width: 12).accessibilityLabel("Dock panels")
            }
          }.overlay(alignment: .trailing) {
            if dragging && !right.isEmpty { newColumnTarget(.right, before: nil).frame(width: 6) }
          }
        }
      }
      .onChange(of: library.layout) { old, new in
        guard let id = openDockGroup else { return }
        let previous = (old.panelDock ?? PanelDock(layout: old)).groups.first { $0.id == id }
        guard let group = library.panelDock.groups.first(where: { $0.id == id }),
          group.floatingFrame == nil, previous?.dockColumnID == group.dockColumnID,
          !library.panelDock.visiblePanels(in: group, visibility: new.visibility).isEmpty
        else {
          openDockGroup = nil
          return
        }
      }
    }
  }

  var documentColumn: some View {
    VStack(spacing: 0) {
      documentTabs
      if let workspace {
        if let document = workspace.activeDocument {
          DocumentSurfaceView(
            store: document.store,
            isActive: workspace.owner?.activeDocument === document
          ) {
            workspace.owner?.activate(document) ?? true
          }
        } else {
          StudioTheme.tab.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      } else {
        DocumentSurfaceView(store: store)
      }
    }
  }

  func newColumnTarget(_ side: PanelDockSide, before: String?) -> some View {
    PanelDockDropZone(
      library: store.workspaceLibrary, before: nil,
      canOrganize: canOrganizePanels, tearOff: workspace?.owner?.panelDragging,
      destination: .newColumn(side, before: before), accessibilityName: "New \(side.rawValue) dock")
  }

  func dockColumnDivider(_ column: PanelDockColumnSizing.Column, before: String?) -> some View {
    let library = store.workspaceLibrary
    return PanelDockDropZone(
      library: library, before: nil,
      canOrganize: canOrganizePanels, tearOff: workspace?.owner?.panelDragging,
      destination: .newColumn(column.column.side, before: before), horizontalResize: true,
      accessibilityName: "Resize \(column.column.side.rawValue) dock",
      beginResize: canOrganizePanels ? { columnStartingWidths[column.id] = column.width } : nil,
      resize: canOrganizePanels
        ? { delta in
          let direction = column.column.side == .left ? 1.0 : -1.0
          library.resizeColumn(
            column.id,
            width: (columnStartingWidths[column.id] ?? column.width) + Double(delta) * direction,
            icons: column.icons)
        } : nil,
      endResize: canOrganizePanels ? { columnStartingWidths[column.id] = nil } : nil
    ).frame(width: 4).background(StudioTheme.line)
  }

  @ViewBuilder func dockColumnContent(_ value: PanelDockColumnSizing.Column) -> some View {
    if value.icons {
      collapsedDockColumn(value.column, width: value.width)
    } else {
      inspector(columnID: value.id).frame(width: value.width)
        .disabled(store.geometryBusy || store.transformDraft != nil)
    }
  }

  func collapsedDockColumn(_ column: PanelDockColumn, width: Double) -> some View {
    let library = store.workspaceLibrary
    let groups = library.panelDock.groups(inColumn: column.id, visibility: store.workspace)
    return VStack(spacing: 0) {
      HStack {
        Spacer(minLength: 0)
        Button {
          openDockGroup = nil
          library.setColumnCollapsed(column.id, false)
        } label: {
          Image(systemName: column.side == .right ? "chevron.left.2" : "chevron.right.2")
            .font(.system(size: 7))
        }.buttonStyle(.plain).padding(.trailing, 7)
          .accessibilityLabel("Expand dock panels")
          .contextMenu { dockColumnMenu(column.id) }
      }.frame(height: 12)
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 0) {
          ForEach(groups) { group in
            VStack(spacing: 0) {
              PanelDockDropZone(
                library: library, before: group.id,
                canOrganize: canOrganizePanels, tearOff: workspace?.owner?.panelDragging,
                destination: .column(column.id, beforeGroup: group.id)
              ).frame(height: 3)
              ForEach(
                library.panelDock.visiblePanels(in: group, visibility: store.workspace), id: \.self
              ) { panel in
                PanelDockTab(
                  library: library, group: group, panel: panel,
                  selected: openDockGroup == group.id && group.selected == panel,
                  canOrganize: canOrganizePanels, tearOff: workspace?.owner?.panelDragging,
                  icon: panel.dockSymbol, showsLabel: width >= 100,
                  selectOverride: {
                    let close = openDockGroup == group.id && group.selected == panel
                    library.selectPanel(panel)
                    openDockGroup = close ? nil : group.id
                  }
                )
                .frame(width: width, height: 29)
              }
            }
            .popover(
              isPresented: Binding(
                get: { openDockGroup == group.id },
                set: { if !$0 { openDockGroup = nil } }),
              arrowEdge: column.side == .right ? .leading : .trailing
            ) {
              VStack(spacing: 0) {
                HStack(spacing: 0) {
                  dockHeader(group)
                  Button {
                    openDockGroup = nil
                  } label: {
                    Image(systemName: column.side == .right ? "chevron.right.2" : "chevron.left.2")
                  }.buttonStyle(.plain).padding(6).accessibilityLabel("Collapse panel to icon")
                }
                if let selected = library.panelDock.selectedPanel(
                  in: group, visibility: store.workspace)
                {
                  dockContent(selected).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
              }.frame(width: library.columnWidth(column.id), height: 360)
                .background(StudioTheme.panel).preferredColorScheme(.dark)
            }
          }
          PanelDockDropZone(
            library: library, before: nil, canOrganize: canOrganizePanels,
            tearOff: workspace?.owner?.panelDragging,
            destination: .column(column.id, beforeGroup: nil)
          ).frame(height: 12)
        }
      }
    }.frame(width: width).background(StudioTheme.chrome)
  }

  @ViewBuilder func dockColumnMenu(_ id: String) -> some View {
    let library = store.workspaceLibrary
    let movable = canOrganizePanels && !library.workspaceLocked
    Button("Dock on Left") { library.moveColumn(id, side: .left, before: nil) }.disabled(!movable)
    Button("Dock on Right") { library.moveColumn(id, side: .right, before: nil) }.disabled(!movable)
    Menu("Move Dock Before") {
      ForEach(library.panelDock.orderedColumns.filter { $0.id != id }) { column in
        Button(
          "\(column.side == .left ? "Left" : "Right") Dock \(library.panelDock.orderedColumns.firstIndex { $0.id == column.id }! + 1)"
        ) {
          library.moveColumn(id, side: column.side, before: column.id)
        }
      }
    }.disabled(!movable || library.panelDock.orderedColumns.count < 2)
  }
}
