import Foundation
import AppKit
import SwiftUI

@main struct ToolbarTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let fm = FileManager.default, root = try ArchiveEngine.workspace()
        defer { try? fm.removeItem(at:root) }
        let document = ArchiveDocument(storage:root)
        defer { document.timer?.invalidate() }
        let coordinator = NativeArchiveToolbar.Coordinator(document:document)
        let toolbar = NSToolbar(identifier:"TabajaraToolbarTest-" + UUID().uuidString)
        let allowed = coordinator.toolbarAllowedItemIdentifiers(toolbar)
        let defaults = coordinator.toolbarDefaultItemIdentifiers(toolbar)
        precondition(Set(defaults).isSubset(of:Set(allowed)))
        precondition(allowed.contains(.space) && allowed.contains(.flexibleSpace))
        precondition(!allowed.contains(.init("sidebar")))
        var firstItems: [String:NSToolbarItem] = [:]
        for spec in ArchiveToolbarItem.catalog {
            let id = NSToolbarItem.Identifier(spec.id)
            let first = coordinator.toolbar(toolbar,itemForItemIdentifier:id,willBeInsertedIntoToolbar:false)!
            let second = coordinator.toolbar(toolbar,itemForItemIdentifier:id,willBeInsertedIntoToolbar:false)!
            precondition(first !== second && first.label == spec.title)
            if let first = first as? NSSearchToolbarItem, let second = second as? NSSearchToolbarItem { precondition(first.searchField !== second.searchField) }
            firstItems[spec.id] = first
        }
        toolbar.delegate = coordinator
        coordinator.toolbar = toolbar
        toolbar.insertItem(withItemIdentifier:.init("search"),at:0)
        toolbar.insertItem(withItemIdentifier:.init("extract"),at:0)
        coordinator.refresh()
        precondition(!toolbar.items.first!.isEnabled)
        if #available(macOS 15.0, *) { precondition(toolbar.items.last!.isHidden) }
        else { precondition(toolbar.items.count == 1) }
        precondition(!coordinator.validateToolbarItem(firstItems["search"]!))
        let viewMenu = firstItems["view"] as! NSMenuToolbarItem
        precondition(viewMenu.action == nil && viewMenu.menu.items.count == 4 && viewMenu.visibilityPriority == .high)
        let extractMenu = firstItems["extract"] as! NSMenuToolbarItem
        precondition(extractMenu.action == nil && extractMenu.target == nil && extractMenu.menu.items.count == 3)
        let options = firstItems["options"]!
        precondition(!coordinator.validateToolbarItem(options))
        document.showFileOptions(); precondition(!document.optionsVisible)
        document.create()
        coordinator.refresh()
        precondition(coordinator.validateToolbarItem(firstItems["search"]!))
        if #available(macOS 15.0, *) { precondition(!toolbar.items.last!.isHidden) }
        else { precondition(toolbar.items.contains { $0.itemIdentifier.rawValue == "search" }) }
        precondition(coordinator.validateToolbarItem(options))
        document.busy = true; precondition(!coordinator.validateToolbarItem(options)); document.busy = false
        precondition(!fm.fileExists(atPath:document.session!.appendingPathComponent("recovery.json").path))
        try document.discardSessionForExit()
        let zip = root.appendingPathComponent("empty.zip")
        try (Data([0x50,0x4b,0x05,0x06]) + Data(repeating:0,count:18)).write(to:zip)
        document.open(zip)
        for _ in 0..<100 { if !document.busy { break }; try await Task.sleep(nanoseconds:50_000_000) }
        precondition(document.error == nil && coordinator.validateToolbarItem(options))
        document.showFileOptions(); precondition(document.optionsVisible)
        for mode in [NSToolbar.DisplayMode.iconOnly,.iconAndLabel,.labelOnly] { toolbar.displayMode = mode; precondition(toolbar.displayMode == mode) }
        // Native width notifications persist user resizing; disabling memory stops writes.
        UserDefaults.standard.removeObject(forKey:"archiveColumnWidths")
        let tableWindow = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:300),styleMask:[.titled],backing:.buffered,defer:false)
        let nativeTable = NSTableView(frame:NSRect(x:0,y:0,width:1000,height:300))
        for index in 0..<7 { let column = NSTableColumn(identifier:.init("col\(index)")); column.minWidth = 40; column.maxWidth = 500; column.width = 100; nativeTable.addTableColumn(column) }
        tableWindow.contentView = nativeTable
        let widths = ArchiveColumnPreferences.Coordinator(); widths.attach(window:tableWindow)
        nativeTable.tableColumns[0].width = 240
        NotificationCenter.default.post(name:NSTableView.columnDidResizeNotification,object:nativeTable)
        precondition((UserDefaults.standard.array(forKey:"archiveColumnWidths") as? [Double])?.first == 240)
        widths.remember = false; nativeTable.tableColumns[0].width = 300
        NotificationCenter.default.post(name:NSTableView.columnDidResizeNotification,object:nativeTable)
        precondition((UserDefaults.standard.array(forKey:"archiveColumnWidths") as? [Double])?.first == 240)
        NotificationCenter.default.post(name:.archivePreferencesReset,object:nil)
        precondition(nativeTable.tableColumns[0].width == 100)
        let titles = ["Arquivo.zip","Primeira pasta","Segunda pasta","Terceira pasta","Pasta atual"]
        precondition(BreadcrumbFit.indices(titles:titles,width:2000) == [0,1,2,3,4])
        let compact = BreadcrumbFit.indices(titles:titles,width:320)
        precondition(compact.first == 0 && compact.last == 4 && compact.contains(-1))
        precondition(BreadcrumbFit.indices(titles:titles,width:10) == [0,-1,4])
        precondition(BreadcrumbFit.indices(titles:["Arquivo.zip"],width:10) == [0])
        precondition(BreadcrumbFit.indices(titles:[],width:100).isEmpty)
        let path = CommandLine.arguments[1]
        let icon = NSImage(contentsOfFile:path)
        precondition(icon?.isValid == true)
        precondition(icon!.size.width > 0 && icon!.size.height > 0)
        print("PASS: native toolbar catalog and spacers; independent palette items/views; three display modes; options disabled empty and enabled for new/open archives; no recovery journal; valid app icon")
    }
}
