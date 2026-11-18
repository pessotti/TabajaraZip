import SwiftUI
import AppKit

struct AppSettingsView: View {
    @ObservedObject var preferences = AppPreferences.shared
    @AppStorage("excludeArchiveMetadata") private var excludeMetadata = true
    @AppStorage("appAppearance") private var appearance = "system"
    @State private var resetVisible = false
    @AppStorage("rarExecutable") private var rarExecutable = ""
    var body: some View {
        VStack(spacing:0) {
            TabView {
                general.tabItem { Label("Geral",systemImage:"gearshape") }
                appearanceTab.tabItem { Label("Aparência",systemImage:"paintpalette") }
                navigation.tabItem { Label("Navegação",systemImage:"folder") }
                extraction.tabItem { Label("Extração",systemImage:"square.and.arrow.down") }
                compression.tabItem { Label("Compactação",systemImage:"archivebox") }
                editing.tabItem { Label("Edição",systemImage:"pencil") }
                advanced.tabItem { Label("Avançado",systemImage:"slider.horizontal.3") }
            }.padding(16)
            Divider()
            HStack {
                Text("As preferências são salvas automaticamente.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restaurar padrões…") { resetVisible = true }
            }.padding(16)
        }.frame(width:760,height:560).foregroundStyle(.primary)
        .confirmationDialog("Restaurar as preferências padrão?",isPresented:$resetVisible,titleVisibility:.visible) {
            Button("Restaurar padrões") { preferences.reset() }
            Button("Cancelar",role:.cancel) {}
        } message: { Text("Os arquivos e a lista de recentes serão preservados. Aparência, destinos e demais preferências voltarão aos padrões.") }
    }
    var general: some View {
        Form {
            Section("Ao iniciar") {
                Picker("Abrir",selection:$preferences.values.startup) { Text("Tela inicial").tag("welcome"); Text("Último arquivo").tag("last") }
                Text("Reabre apenas o arquivo salvo; alterações descartadas não são recuperadas.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Recentes") {
                Picker("Quantidade de arquivos",selection:$preferences.values.recentLimit) { ForEach([5,10,15,25,50],id:\.self) { Text("\($0)").tag($0) } }
                Button("Limpar recentes") { NotificationCenter.default.post(name:.clearArchiveRecents,object:nil) }
            }
            Section("Remoção") { Toggle("Confirmar antes de remover itens",isOn:$preferences.values.confirmRemoval) }
        }.formStyle(.grouped)
    }
    var appearanceTab: some View {
        Form {
            Section("Tema") {
                Picker("Tema do app",selection:$appearance) { ForEach(AppTheme.allCases,id:\.self) { Text($0.label).tag($0.rawValue) } }.pickerStyle(.segmented)
                Text("Sistema acompanha a aparência do macOS.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Lista de arquivos") {
                Picker("Tamanho dos nomes",selection:$preferences.values.nameSize) { Text("Pequeno").tag(11); Text("Padrão").tag(13); Text("Grande").tag(15); Text("Muito grande").tag(17) }
                Picker("Espaçamento das linhas",selection:$preferences.values.comfortableRows) { Text("Compacto").tag(false); Text("Confortável").tag(true) }
                Toggle("Mostrar extensões dos arquivos",isOn:$preferences.values.showExtensions)
                Toggle("Abrir painel de prévia por padrão",isOn:$preferences.values.previewByDefault)
            }
        }.formStyle(.grouped)
    }
    var navigation: some View {
        Form {
            Section("Organização") {
                Toggle("Mostrar pastas primeiro",isOn:$preferences.values.foldersFirst)
                Toggle("Mostrar arquivos e pastas ocultos",isOn:$preferences.values.showHidden)
                Text("Ocultar itens afeta apenas a lista; eles continuam no arquivo compactado.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Lembrar entre aberturas") {
                Toggle("Ordenação das colunas",isOn:$preferences.values.rememberSort)
                Toggle("Largura das colunas",isOn:$preferences.values.rememberColumns)
            }
        }.formStyle(.grouped)
    }
    var extraction: some View {
        Form {
            Section("Destino padrão") {
                Picker("Extrair para",selection:$preferences.values.extractionDestination) {
                    Text("Perguntar sempre").tag("ask"); Text("Mesma pasta do arquivo").tag("same"); Text("Pasta específica").tag("custom")
                }
                if preferences.values.extractionDestination == "custom" {
                    directoryRow(preferences.values.extractionDirectory) { if let path = preferences.chooseDirectory("Destino padrão de extração",current:preferences.values.extractionDirectory) { preferences.values.extractionDirectory = path } }
                }
                Toggle("Abrir pasta de destino ao terminar",isOn:$preferences.values.revealExtraction)
                Text("As ações explícitas Extrair aqui e Extrair em pasta mantêm seus destinos.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Arquivos existentes") {
                Picker("Em caso de conflito",selection:$preferences.values.conflict) { ForEach(ArchiveEngine.Conflict.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                Text("Padrão para arquivos abertos ou criados a partir de agora. Pode ser alterado nas opções de cada arquivo.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    var compression: some View {
        Form {
            Section("Padrões para novos arquivos") {
                Picker("Formato",selection:$preferences.values.format) { ForEach(["zip","7z","rar","tar","tgz","tbz2","txz"],id:\.self) { Text($0.uppercased()).tag($0) } }
                Picker("Compressão",selection:$preferences.values.compression) { Text("Sem compressão").tag(0); Text("Rápida").tag(1); Text("Normal").tag(5); Text("Máxima").tag(9) }
                Text("As opções do arquivo aberto continuam independentes destes padrões.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Ao salvar") {
                Toggle("Mostrar resumo antes de salvar",isOn:$preferences.values.reviewSave)
                Toggle("Excluir .DS_Store e _MACOSX",isOn:$excludeMetadata)
                Text(verbatim:"A limpeza inclui .DS_Store e pastas _MACOSX / __MACOSX de todas as subpastas. Arquivos ._ são preservados.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    var editing: some View {
        Form {
            Section("Editor externo") {
                HStack {
                    Text(preferences.values.editorApplication.isEmpty ? "Aplicativo padrão do macOS" : URL(fileURLWithPath:preferences.values.editorApplication).deletingPathExtension().lastPathComponent).lineLimit(1)
                    Spacer(); Button("Escolher…") { if let path = preferences.chooseEditor() { preferences.values.editorApplication = path } }
                    if !preferences.values.editorApplication.isEmpty { Button("Usar padrão") { preferences.values.editorApplication = "" } }
                }
                Toggle("Perguntar antes de incorporar alterações externas",isOn:$preferences.values.confirmExternalEdits)
                Text("Ao recusar uma alteração, a cópia externa continua intacta e o conteúdo do arquivo compactado é mantido.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    var advanced: some View {
        Form {
            Section("Criação de RAR / RAR5") {
                Text(ArchiveEngine.rarTool == nil ? "Motor RAR não configurado" : "Motor RAR disponível").font(.headline)
                if !rarExecutable.isEmpty { Text(rarExecutable).font(.caption).textSelection(.enabled) }
                HStack {
                    Button("Selecionar executável RAR…") {
                        let panel = NSOpenPanel(); panel.message = "Selecione o arquivo rar extraído do pacote oficial para macOS."; panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url, FileManager.default.isExecutableFile(atPath:url.path) { rarExecutable = url.path }
                    }
                    Link("Baixar RAR oficial",destination:URL(string:"https://www.rarlab.com/download.htm")!)
                }
                Text("RAR é uma ferramenta comercial separada, com período de avaliação. Baixe e extraia o pacote para uma pasta permanente e selecione o executável rar. O formato criado é RAR5; a abertura de RAR não exige esta ferramenta.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Arquivos temporários") {
                directoryRow(preferences.values.temporaryDirectory) { if let path = preferences.chooseDirectory("Pasta para arquivos temporários",current:preferences.values.temporaryDirectory) { preferences.values.temporaryDirectory = path } }
                if !preferences.values.temporaryDirectory.isEmpty { Button("Usar pasta temporária do sistema") { preferences.values.temporaryDirectory = "" } }
                Text("Usada nas próximas operações. Cópias de trabalho abertas permanecem no local atual até serem fechadas.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Prévia automática") {
                Picker("Tamanho máximo por arquivo",selection:$preferences.values.previewLimitMB) { ForEach([5,10,25,50,100,250],id:\.self) { Text("\($0) MB").tag($0) } }
                Text("Arquivos maiores continuam disponíveis para abrir e extrair.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    func directoryRow(_ path: String, choose: @escaping () -> Void) -> some View {
        HStack {
            Text(path.isEmpty ? "Não definida (padrão do sistema)" : path).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            Spacer(); Button("Escolher…",action:choose)
        }
    }
}
