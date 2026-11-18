import AppKit
import SwiftUI

/// Retain the native table's actual user-resized widths, independently from the toolbar.
struct ArchiveColumnPreferences: NSViewRepresentable {
    var remember: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.attach = { [weak coordinator = context.coordinator] window in coordinator?.attach(window:window) }
        return view
    }
    func updateNSView(_ view: Anchor, context: Context) {
        context.coordinator.remember = remember
        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
            if let window = view?.window { coordinator?.attach(window:window) }
        }
    }
    final class Anchor: NSView {
        var attach: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DispatchQueue.main.async { [weak self] in self?.attach?(window) } }
        }
    }
    @MainActor final class Coordinator {
        var remember = true
        weak var table: NSTableView?
        var observer: NSObjectProtocol?
        var resetObserver: NSObjectProtocol?
        var initialWidths: [CGFloat] = []
        var applying = false
        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let resetObserver { NotificationCenter.default.removeObserver(resetObserver) }
        }
        func findTable(_ view: NSView) -> NSTableView? {
            if let table = view as? NSTableView, table.numberOfColumns >= 6 { return table }
            return view.subviews.lazy.compactMap { self.findTable($0) }.first
        }
        func attach(window: NSWindow) {
            guard let content = window.contentView, let found = findTable(content), found !== table else { return }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            table = found; initialWidths = found.tableColumns.map(\.width)
            if resetObserver == nil {
                resetObserver = NotificationCenter.default.addObserver(forName:.archivePreferencesReset,object:nil,queue:.main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let table = self.table else { return }
                        self.applying = true
                        for (column,width) in zip(table.tableColumns,self.initialWidths) { column.width = width }
                        self.applying = false
                    }
                }
            }
            if remember, let widths = UserDefaults.standard.array(forKey:"archiveColumnWidths") as? [Double], widths.count == found.tableColumns.count {
                applying = true
                for (column,width) in zip(found.tableColumns,widths) { column.width = max(column.minWidth,min(column.maxWidth,width)) }
                applying = false
            }
            observer = NotificationCenter.default.addObserver(forName:NSTableView.columnDidResizeNotification,object:found,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.remember, !self.applying, let table = self.table else { return }
                    UserDefaults.standard.set(table.tableColumns.map { Double($0.width) },forKey:"archiveColumnWidths")
                }
            }
        }
    }
}
