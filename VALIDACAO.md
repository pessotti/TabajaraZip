# Validação — Tabajara ZIP 2.0

Verificado em 17/11/2026, macOS Apple Silicon.

- Compilação do aplicativo e da extensão Quick Look; verificação das assinaturas locais.
- Testes do motor: ZIP vazio, Unicode, nomes com curingas, pastas aninhadas/vazias, atualização incremental, renomeação/remoção, preservação do original em erro/cancelamento, ZIP/7z/TAR/TGZ/TBZ2/TXZ, leitura do TAR interno, AES-256, senha incorreta, caminhos inseguros, colisões de nomes, links bloqueados, conflitos de extração, volumes e SHA-256.
- Arquivos de teste adversariais: ZIP com caminho ../, nome com quebra de linha e link simbólico.
- RAR comprimido: listagem e extração de membro regular do arquivo de teste público do libarchive.
- Recuperação de ZIP com diretório final truncado, em cópia separada.
- Modelo de documento: adição pendente, renomeação, desfazer/refazer, registro/recuperação, edição interna, importação de edição externa, gravação e permanência do modo direto.
- App Intents: chamada das ações nativas de compactação e extração, comparando o conteúdo de entrada e saída.
- Interface instalada: abertura de ZIP, navegação em pasta, colunas e prévia do texto extraído sob demanda.
- Integração: duas declarações de serviços Finder e metadados das duas ações App Intents incluídos; extensão Quick Look registrada e habilitada no PlugInKit.

## Limite da verificação da extensão

A prévia de ZIP no Finder foi exibida pelo BetterZip já instalado (identificado pela própria interface da prévia). O sistema deu precedência a esse provedor. A extensão do Tabajara está incluída e registrada, mas sua renderização pelo Finder não foi confirmada neste ambiente. A prévia dentro do aplicativo foi confirmada.

Os testes do código das ações nativas passaram; a descoberta e execução dessas ações pela interface do aplicativo Atalhos não foram verificadas.

## Versão 2.1

- Testes de resumo: adições, alterações, renomeação, substituições, remoções, limpeza/filtros, totais e gravação sem mudanças.
- Testes do documento: resumo aparece antes de escrever no destino; cancelar mantém a sessão e não grava; confirmar grava; edição externa e modo direto continuam funcionais.
- Indicadores: sem senha, ZipCrypto, AES-256 em ZIP/7z, método desconhecido e proteção mista; detecção de ZipCrypto em ZIP real.
- Suite completa de testes do motor, documento, App Intents, limpeza e compatibilidade com unzip passou.
- Capturas nativas de teste em Preview para navegação, resumo e configurações, nos temas claro e escuro. A inspeção interativa inicialmente ficou indisponível com o Mac bloqueado; foi concluída após a retomada, conforme abaixo.

## Conferência interativa concluída

- Alternância real entre Claro e Escuro nas configurações do app, com textos legíveis; ao final, aparência restaurada para Sistema.
- ZIP temporário aberto na versão instalada: nomes e opções com cores nativas, indicador Sem senha.
- Resumo real: 1 pasta adicionada e 2 arquivos .DS_Store excluídos (raiz e subpasta).
- Cancelar retornou às alterações pendentes; nova confirmação gravou o arquivo e mostrou Salvo e verificado.
- Verificação independente do ZIP gravado: pasta adicionada, documento preservado, nenhum .DS_Store e CRC válido.
- ZIP protegido temporário: indicador real ZipCrypto · proteção fraca exibido ao abrir.
- Nenhum arquivo do usuário foi alterado durante a conferência; usados apenas arquivos em /tmp/TabajaraInteractiveValidation.

## Versão 2.2.1

- Toolbar AppKit nativa: menu com Ícones e Texto, Somente Ícones e Somente Texto; paleta em português com todos os botões permitidos, Espaço, Espaço Flexível e conjunto padrão.
- Inclusão do botão Prévia pela paleta; item e modo de exibição persistiram após reabrir.
- Ícone de prensa/pacote incluído no app, cabeçalho e tela inicial; arquivo ICNS validado com 11 representações padrão/Retina e leitura por NSImage.
- Sidebar e funcionalidade de recuperação de sessões removidas do código e da interface. Cópias de trabalho atuais ficam no diretório temporário e não geram recovery.json.
- Conferência real: Opções desabilitado na tela inicial, habilitado após criar arquivo novo e abertura do painel correspondente. Teste automatizado cobre também arquivo existente aberto.
- Suite completa de motor/documento/criptografia/limpeza/resumo/App Intents passou após as remoções. Teste específico da toolbar passou, incluindo fábricas de itens/visões independentes para a paleta e catálogo sem botão de sidebar.
- Ao fim da conferência, descartado somente o arquivo novo vazio criado para teste; nenhum arquivo do usuário foi modificado.

## Versão 2.2.2
- Tela inicial lista os arquivos recentes com nome e localização.
- Busca oculta sem documento, preservando a personalização da toolbar; disponível em arquivos abertos e novos.

## Versão 2.3.0 — TabajaraZip

- Motor: formatos, senha, integridade e preservação dos originais; testes novos de conflito por item e rollback após cancelamento durante substituição e após cancelar um conflito posterior.
- Documento: histórico incluindo busca, caminho hierárquico, renomeação, removidos/restauração, metadados de conflito e ações de recentes.
- Arraste: NSFilePromiseProvider nativo, conteúdo de pasta e Unicode, destino renomeado pelo Finder, gesto cancelado e escrita cancelada; teste nativo requer acesso aos tipos registrados pelo macOS.
- Interface: pasta por duplo clique, voltar, dropdown de extração, diálogo comparando tamanho/data, manter ambos, marca de renomeação, remover/restaurar e Escape no arraste conferidos no macOS.
- Toolbar, configurações, ZipCrypto/unzip e limpeza de metadados continuam nos testes existentes.

## Versão 2.4.0 — Preferências completas

- Teste isolado de persistência e restauração dos padrões; preferências anteriores de tema e limpeza preservadas.
- Padrões aplicados a novos arquivos, pastas primeiro, ocultos, extensões, ordenação persistente e desligada, limite de recentes, remoção sem confirmação com desfazer, salvar sem resumo, reabrir último salvo e pasta de trabalho personalizada.
- Extração automática para destino específico com subpasta e limite de prévia exercitados no documento.
- Diretório temporário do motor conferido; notificações nativas de redimensionamento persistem larguras, desativar memória impede novas gravações e restaurar padrões recupera larguras iniciais.
- Sete abas e confirmação de restauração conferidas visualmente no macOS.

## Versão 2.5.0 — Múltiplas janelas e modos

- Tests/WorkspaceTests.swift verifica arquivos independentes, sessões distintas, preservação de edição pendente, foco do mesmo arquivo aberto/carregando/atalho simbólico, fechamento de uma janela sem afetar a outra e navegação nos quatro modos.
- Tests/ViewModeSnapshots.swift renderiza os quatro modos em janelas transparentes com política sem Dock; imagens conferidas, incluindo árvore e colunas expandidas e grade de ícones.
- Toolbar testa catálogo de quatro modos e prioridade do seletor.
- Dois ZIPs fictícios foram abertos pela entrega de eventos do Launch Services em uma cópia isolada; a cópia foi encerrada para manter apenas o aplicativo original ativo no Dock.
- Fechamento encerra também o Quick Look pertencente à janela, sem interromper outras janelas.

## Versão 2.6.1 — RAR5 e volumes nativos

- Motor oficial RAR macOS ARM64 7.23 testado como ferramenta externa, sem inclusão no bundle/repositório.
- `test-native-volumes.sh`: RAR5 com assinatura binária correta, senha via stdin, Unicode, nomes com caracteres curingas literais, pastas vazias e 11 volumes com numeração preenchida com zero.
- Extração byte a byte de 11,1 MB aleatórios em RAR, ZIP e 7z protegidos; rejeição de partes intermediárias ausentes nos três formatos.
- Conflito de nomes preserva todos os volumes anteriores; cancelamento não publica saídas; configurações salvas antigas continuam decodificando.
- `test.sh`: motor, documentos, Atalhos, limpeza global, compatibilidade ZipCrypto/unzip e resumo antes de salvar sem regressões.
- Preferências e múltiplas janelas verificadas pelos testes específicos.

## Versão 2.6.2 — Diagnósticos persistentes

- `test-diagnostics.sh`: registros JSON concorrentes, permissões privadas, rotação limitada, falha do logger sem interromper a operação, persistência de erro do motor e das camadas externas.
- Senhas e saída padrão simulando conteúdo privado não aparecem nos arquivos de diagnóstico, inclusive ao registrar novamente um erro propagado.
- Logger compartilhado pela interface, CLI, Atalhos, Quick Look, prévias, lote, preferências e limpeza/rollback; aviso no Console se o destino não puder ser escrito.
- Logs locais excluídos explicitamente do Git e da distribuição.
