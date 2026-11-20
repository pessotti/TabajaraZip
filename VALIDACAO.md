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

## Versão 2.6.3 — Extração de ZIPs com muitos arquivos

- Extração ZIP em um único fluxo, separando os membros por tamanho e verificando CRC individual, sem delegar caminhos de saída ao motor.
- Ancestrais selecionados identificados por percurso de pais, evitando a comparação de todos os caminhos entre si.
- ZIP real com 7.255 itens/6.506 arquivos extraído em aproximadamente 6 segundos; conteúdo comparado byte a byte em pasta temporária. Nenhum conteúdo privado foi incluído no repositório.
- Teste de regressão sintético com muitos arquivos, seleção parcial, ordem do ZIP, nomes especiais, renomeação, edição em staging, senha e cancelamento.
- Seleção de membros em listas UTF-8 preserva a normalização Unicode original, evitando conversão automática dos argumentos pelo macOS.
- Fluxo corrompido de mesmo tamanho é rejeitado pelo CRC antes de modificar o destino; colisões de nomes na extração parcial produzem erro com rollback, sem forçar um resolvedor ausente.

## Versão 2.6.4 — Edição de pastas grandes

- Remoção, desfazer/restaurar e indicadores de alterações reutilizam o resumo até a lista ser modificada; painel de removidos renderizado sob demanda.
- Seleção de milhares de itens percorre ancestrais, sem comparar todos os caminhos entre si.
- Gravação incremental usa lista UTF-8 para remoções, sem limite de argumentos, agrupando subpastas completamente removidas e preservando descendentes mantidos.
- Preparação em fluxo único também usada ao renomear/converter/recriar ZIPs, incluindo gravação e edição com ZipCrypto.
- Testes com pasta de 4.000 arquivos, seleção individual grande, lista de exclusão acima do limite de argumentos, conteúdo mantido, caches após desfazer/restaurar e cancelamento antes/durante gravação.
- Em cópia temporária de um ZIP real, remover 1.823 itens atualizou o resumo em 0,1 s; salvar e verificar levou aproximadamente 2,1 s. SHA-256 confirmou o original preservado.
- Exclusão pura de ZIP ZipCrypto com senha mantida preserva os membros comprimidos, sem extração; troca de senha reconstrói por um único fluxo e a senha nova é verificada.

## Versão 2.6.5 — Nomes com dois-pontos

- Corrigida a rejeição indevida de nomes POSIX contendo `:`, incluindo logs IPv6 como `php_errors_::1.log`.
- Prefixos de unidade Windows, caminhos absolutos, travessia `..`, barras invertidas e caracteres de controle continuam bloqueados.
- `test-colon-names.sh`: compactação, extração em lote/individual e exclusão preservam nomes com dois-pontos em arquivos e pastas; testes usam somente conteúdo sintético.

## Versão 2.6.6 — Varredura de compactação e extração

Problemas reproduzidos e corrigidos:

- TARs com a raiz `.` e membros `./...` eram recusados. A leitura agora separa o caminho seguro de destino do nome original usado pelo motor.
- ZIPs DOS/Windows com separadores invertidos eram recusados. A normalização aplica-se aos formatos Windows reconhecidos, mantendo a proteção contra caminhos absolutos, unidades, travessia e colisões de nomes.
- Links simbólicos quebrados no destino não eram considerados conflitos e podiam ser seguidos na escrita. A cópia agora cria arquivos de forma exclusiva, o tratamento de conflitos reconhece o link e a publicação do resultado não escreve através dele.
- Cancelamento após substituições repetidas do mesmo nome podia restaurar a cópia intermediária e perder o original. O controle identifica saídas da própria operação e mantém a cópia real anterior.
- Falha na restauração podia apagar a cópia de segurança durante a limpeza. O journal fica no sistema de arquivos do destino; se a restauração falhar, as cópias originais permanecem e seu endereço é informado.
- Falhas ao abrir arquivos deixavam pastas de trabalho órfãs. A pasta recém-criada agora é removida sem afetar a sessão anterior.
- Extração por arrastar para o Finder também publica a saída preparada, sem apagar um arquivo preexistente caso a cópia/publicação falhe.

Validação:

- `test-audit.sh`: TAR/ZIP com `./`, ZIP Windows, extração e regravação, resumo sem alterações falsas, rejeição de travessia/unidades/aliases, arquivos especiais, links quebrados, conflitos, publicação sem sobrescrita, cancelamento com nomes repetidos, preservação do backup quando há falha de restauração e limpeza de abertura falha.
- Matriz manual de ZIP, 7z, TAR, TGZ, TBZ2 e TXZ nos níveis 0/1/9, além do nível 5 coberto na suíte do motor: todos passaram.
- Suítes completas de motor/documentos/Atalhos, compatibilidade ZIP, resumo, preferências, extração em lote, edição grande, nomes com dois-pontos, volumes ZIP/7z/RAR, diagnóstico, arrastar e múltiplas janelas passaram.
- Testes de falha e compatibilidade utilizam exclusivamente dados sintéticos em pastas temporárias; nenhum arquivo original do usuário foi modificado.

## Versão 2.6.7 — Permissões e metadado Icon do Finder

- Preserva bits POSIX de leitura/escrita/execução na cópia, staging, gravação e extração. Bits especiais de privilégio não são restaurados.
- Permite exclusivamente os componentes `Icon\r` e `._Icon\r` entre nomes com caracteres de controle; outros controles, travessia e caminhos absolutos continuam bloqueados.
- Leitura em fluxo completo quando o nome especial não pode ser representado na lista de seleção do motor, com verificação de tamanho/integridade antes de publicar.
- Testes sintéticos de permissões 755, compactação, extração, prévia e exclusão em ZIP/7z/TAR/TGZ e leitura em RAR; senha ZipCrypto/7z AES/RAR e ZIP AES.

- Corrigida a identificação de pastas somente leitura em 7z (`RD`), antes confundidas com arquivos. Testes preservam também o modo 555 dessas pastas.

- Preserva também `._Icon\r`, inclusive quando a enumeração padrão do macOS oculta o arquivo AppleDouble associado.
