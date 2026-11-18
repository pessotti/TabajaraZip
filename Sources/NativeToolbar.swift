import AppKit
import SwiftUI

struct ArchiveToolbarItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    static let catalog: [Self] = [
        .init(id:"open",title:"Abrir",symbol:"folder"),
        .init(id:"new",title:"Novo",symbol:"plus.rectangle"),
        .init(id:"add",title:"Adicionar",symbol:"plus"),
        .init(id:"new-folder",title:"Nova pasta",symbol:"folder.badge.plus"),
        .init(id:"extract",title:"Extrair",symbol:"square.and.arrow.down"),
        .init(id:"save",title:"Salvar",symbol:"square.and.arrow.up"),
        .init(id:"options",title:"Opções",symbol:"slider.horizontal.3"),
        .init(id:"view",title:"Visualização",symbol:"list.bullet"),
        .init(id:"preview",title:"Prévia",symbol:"sidebar.right"),
        .init(id:"quick-look",title:"Visualização rápida",symbol:"eye"),
        .init(id:"rename",title:"Renomear",symbol:"pencil"),
        .init(id:"remove",title:"Remover",symbol:"trash"),
        .init(id:"test",title:"Testar integridade",symbol:"checkmark.shield"),
        .init(id:"back",title:"Voltar",symbol:"chevron.left"),
        .init(id:"forward",title:"Avançar",symbol:"chevron.right"),
        .init(id:"up",title:"Subir",symbol:"arrow.up"),
        .init(id:"search",title:"Buscar",symbol:"magnifyingglass")
    ]
}

/// Standard AppKit items provide all display modes, the native customization palette and saved layouts.
struct NativeArchiveToolbar: NSViewRepresentable {
    @ObservedObject var document: ArchiveDocument
    func makeCoordinator() -> Coordinator { Coordinator(document:document) }
    func makeNSView(context: Context) -> ToolbarAnchor {
        let anchor = ToolbarAnchor()
        anchor.attach = { [weak coordinator = context.coordinator] window in coordinator?.install(on:window) }
        return anchor
    }
    func updateNSView(_ view: ToolbarAnchor, context: Context) {
        context.coordinator.document = document
        context.coordinator.refresh()
    }
    final class ToolbarAnchor: NSView {
        var attach: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in if let window { self?.attach?(window) } }
        }
    }
    @MainActor final class Coordinator: NSObject, NSToolbarDelegate, NSToolbarItemValidation, NSSearchFieldDelegate {
        static let identifier = NSToolbar.Identifier("br.local.zipdesk.native-toolbar")
        var document: ArchiveDocument
        weak var window: NSWindow?
        var toolbar: NSToolbar?
        private var suspendedSearchIndex: Int?
        init(document: ArchiveDocument) { self.document = document }
        var locked: Bool { document.busy || document.saveReview != nil }
        func install(on window: NSWindow) {
            if let toolbar, window.toolbar === toolbar { return }
            self.window = window
            let toolbar = NSToolbar(identifier:Self.identifier)
            self.toolbar = toolbar
            toolbar.delegate = self
            toolbar.allowsUserCustomization = true
            toolbar.autosavesConfiguration = true
            if #available(macOS 15.0, *) { toolbar.allowsDisplayModeCustomization = true }
            if UserDefaults.standard.object(forKey:"NSToolbar Configuration " + Self.identifier) == nil { toolbar.displayMode = .iconOnly }
            window.toolbar = toolbar
            for index in toolbar.items.indices.reversed() where toolbar.items[index].itemIdentifier.rawValue == "sidebar" { toolbar.removeItem(at:index) }
            if !UserDefaults.standard.bool(forKey:"viewModeToolbarInstalled") {
                if !toolbar.items.contains(where:{ $0.itemIdentifier.rawValue == "view" }) { toolbar.insertItem(withItemIdentifier:.init("view"),at:min(2,toolbar.items.count)) }
                UserDefaults.standard.set(true,forKey:"viewModeToolbarInstalled")
            }
            window.toolbarStyle = .unified
            refresh()
        }
        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [.init("open"),.init("new"),.init("view"),.flexibleSpace,.init("add"),.init("new-folder"),.init("extract"),.init("save"),.init("options"),.init("search")]
        }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            ArchiveToolbarItem.catalog.map { NSToolbarItem.Identifier($0.id) } + [.space,.flexibleSpace]
        }
        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar inserted: Bool) -> NSToolbarItem? {
            guard let spec = ArchiveToolbarItem.catalog.first(where:{ $0.id == identifier.rawValue }) else { return nil }
            // Never reuse a toolbar item or its view: AppKit also calls this factory for the palette.
            let item: NSToolbarItem
            if spec.id == "search" {
                let search = NSSearchToolbarItem(itemIdentifier:identifier)
                let field = NSSearchField(frame:NSRect(x:0,y:0,width:220,height:28))
                field.placeholderString = "Buscar dentro do arquivo"
                field.stringValue = inserted ? document.search : ""
                field.sendsSearchStringImmediately = true
                if inserted { field.delegate = self }
                search.searchField = field
                search.preferredWidthForSearchField = 220
                item = search
            } else {
                if spec.id == "extract" {
                    let menuItem = NSMenuToolbarItem(itemIdentifier:identifier)
                    let menu = NSMenu()
                    for (title,tag) in [("Extrair para…",0),("Extrair aqui",1),("Extrair em pasta com o nome do arquivo",2)] {
                        let action = NSMenuItem(title:title,action:#selector(extractAction(_:)),keyEquivalent:"")
                        action.target = self; action.tag = tag; menu.addItem(action)
                    }
                    menu.autoenablesItems = false; menuItem.menu = menu; item = menuItem
                } else if spec.id == "view" {
                    let menuItem = NSMenuToolbarItem(itemIdentifier:identifier)
                    let menu = NSMenu(); menu.autoenablesItems = false
                    for mode in ArchiveViewMode.allCases {
                        let action = NSMenuItem(title:mode.title,action:#selector(viewAction(_:)),keyEquivalent:"")
                        action.target = self; action.representedObject = mode.rawValue
                        action.image = NSImage(systemSymbolName:mode.symbol,accessibilityDescription:mode.title)
                        menu.addItem(action)
                    }
                    menuItem.menu = menu; item = menuItem
                } else { item = NSToolbarItem(itemIdentifier:identifier) }
                item.image = NSImage(systemSymbolName:spec.symbol,accessibilityDescription:spec.title)
                // A menu-only toolbar item opens its menu from the entire button.
                item.target = ["extract","view"].contains(spec.id) ? nil : self
                item.action = ["extract","view"].contains(spec.id) ? nil : #selector(performAction(_:))
            }
            if spec.id == "view" { item.visibilityPriority = .high }
            item.label = spec.title; item.paletteLabel = spec.title; item.toolTip = spec.title
            return item
        }
        func refresh() {
            guard let toolbar else { return }
            // Hiding preserves the user's chosen placement and autosaved layout.
            if #available(macOS 15.0, *) {
                for item in toolbar.items where item.itemIdentifier.rawValue == "search" { item.isHidden = !document.opened }
            } else {
                let autosaves = toolbar.autosavesConfiguration
                toolbar.autosavesConfiguration = false
                if !document.opened, let index = toolbar.items.firstIndex(where:{ $0.itemIdentifier.rawValue == "search" }) {
                    suspendedSearchIndex = index
                    toolbar.removeItem(at:index)
                } else if document.opened, let index = suspendedSearchIndex {
                    suspendedSearchIndex = nil
                    toolbar.insertItem(withItemIdentifier:.init("search"),at:min(index,toolbar.items.count))
                }
                toolbar.autosavesConfiguration = autosaves
            }
            for case let item as NSMenuToolbarItem in toolbar.items {
                if item.itemIdentifier.rawValue == "view" {
                    item.image = NSImage(systemSymbolName:document.viewMode.symbol,accessibilityDescription:"Visualização")
                    for action in item.menu.items { action.isEnabled = !locked && document.opened; action.state = action.representedObject as? String == document.viewMode.rawValue ? .on : .off }
                } else {
                    for action in item.menu.items { action.isEnabled = !locked && document.opened && (action.tag == 0 || document.archiveURL != nil) }
                }
            }
            toolbar.validateVisibleItems()
            for item in toolbar.items { item.isEnabled = validateToolbarItem(item) }
            for case let search as NSSearchToolbarItem in toolbar.items {
                search.searchField.isEnabled = document.opened && !locked
                if search.searchField.stringValue != document.search { search.searchField.stringValue = document.search }
            }
        }
        func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
            guard !locked || ["open","new"].contains(item.itemIdentifier.rawValue) else { return false }
            switch item.itemIdentifier.rawValue {
            case "open","new","preview": return true
            case "search","view": return document.opened
            case "add","new-folder","extract","options": return document.opened
            case "save": return document.canSave
            case "rename": return document.selection.count == 1
            case "remove": return !document.selection.isEmpty
            case "test": return document.archiveURL != nil
            case "quick-look": return document.selectedEntry?.directory == false
            case "back": return document.canNavigateBack
            case "forward": return document.canNavigateForward
            case "up": return !document.folder.isEmpty
            default: return false
            }
        }
        @objc func performAction(_ sender: NSToolbarItem) {
            guard validateToolbarItem(sender) else { return }
            switch sender.itemIdentifier.rawValue {
            case "open": document.openPanel()
            case "new": document.newArchive()
            case "add": document.addPanel()
            case "new-folder": document.newFolder()
            case "extract": document.extract(document.selection)
            case "save": document.save()
            case "options": document.showFileOptions()
            case "preview": document.previewVisible.toggle(); document.updatePreview()
            case "quick-look": document.quickLook()
            case "rename": document.rename(document.selection)
            case "remove": document.remove(document.selection)
            case "test": document.testArchive()
            case "up": document.navigateUp()
            case "back": document.navigateBack()
            case "forward": document.navigateForward()
            default: break
            }
        }
        @objc func viewAction(_ sender: NSMenuItem) {
            guard !locked, let raw = sender.representedObject as? String, let mode = ArchiveViewMode(rawValue:raw) else { return }
            document.setViewMode(mode)
        }
        @objc func extractAction(_ sender: NSMenuItem) {
            guard !locked else { return }
            if sender.tag == 0 { document.extract(document.selection) }
            else { document.quickExtract(inFolder:sender.tag == 2) }
        }
        func controlTextDidChange(_ notification: Notification) {
            guard document.opened, !locked, let field = notification.object as? NSSearchField else { return }
            document.search = field.stringValue
        }
    }
}

struct ApplicationIcon: View {
    var size: CGFloat
    private static let artwork: NSImage? = {
        guard let url = Bundle.main.url(forResource:"AppIconPreview",withExtension:"png") else { return nil }
        return NSImage(contentsOf:url)
    }()
    var body: some View {
        Group {
            if let image = Self.artwork { Image(nsImage:image).resizable().interpolation(.high).scaledToFit() }
            else { Image(systemName:"archivebox.fill").resizable().scaledToFit().foregroundStyle(.orange) }
        }.frame(width:size,height:size).accessibilityLabel("TabajaraZip")
    }
}
