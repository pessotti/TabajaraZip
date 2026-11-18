# Implementação do roadmap — TabajaraZip 2.5.0

| Etapa proposta | Implementado |
| --- | --- |
| 1.2 Base | Trabalho em segundo plano, progresso por fases/percentual do motor, cancelamento, cópia de trabalho temporária, teste antes da substituição do original |
| 1.3 Navegação | Arrastar para dentro/fora, renomear, criar pastas, mover, buscar, ordenar, tamanho/data/comprimido/taxa, atalhos e menu de contexto |
| 1.4 Prévia e edição | Imagens/PDF/texto, Quick Look no app, edição externa com importação das mudanças, editor UTF-8 |
| 1.5 Documento | Salvar/Salvar como, alterações pendentes, desfazer/refazer até salvar, políticas de conflito |
| 2.0 Motor | Índice sob demanda, extração seletiva, atualização incremental de ZIP/7z não criptografados, ZIP64, níveis de compressão |
| 2.1 Formatos | Leitura RAR/7z/TAR/ZIP e formatos adicionais do 7-Zip; gravação ZIP/7z/TAR/TGZ/TBZ2/TXZ; ZipCrypto em ZIP e AES-256 em 7z |
| 2.2 Integração | Serviços do Finder, extensão Quick Look incluída, recentes, compactar/extrair em lote, configurações salvas |
| 3.0 Avançado | Segmentos binários e reunião, conversão, filtros, App Intents para Atalhos, CLI e recuperação de ZIP |

## Limites explícitos

- Não cria RAR e não gera/repara registros ou volumes de recuperação RAR. A recuperação implementada é de ZIP e não reconstrói dados perdidos.
- A extensão Quick Look e a descoberta das ações no sistema dependem do registro/ativação pelo macOS. Os testes das ações verificam também a execução do código, independentemente da interface do Atalhos.
- O modo direto mantém a cópia temporária de segurança. Não há promessa de edição sem espaço adicional em disco.
- Arquivos 7z sólidos e conversões podem exigir recompressão. Criptografia reconstrói o arquivo completo.
- Desfazer é mantido na sessão até salvar. A recuperação de sessões foi removida a pedido do usuário; alterações não salvas são descartadas ao sair.

## Atualizações de interface

- Toolbar AppKit com paleta nativa, três modos de exibição, espaçadores, restauração do padrão e persistência.
- Ícone novo com prensa e pacote, incluindo representações Retina.
- Sidebar removida; recentes acessíveis pelo menu Arquivo.
- Opções do arquivo disponível somente para um arquivo aberto ou novo em criação.

## Usabilidade 2.3

- Nome TabajaraZip no aplicativo, executável, menus e instalação.
- Promessas nativas para arrastar arquivos, pastas e seleção múltipla ao Finder.
- Histórico voltar/avançar, breadcrumbs e atalhos de navegação.
- Extração rápida e memória do último destino escolhido.
- Comparação de conflitos com tamanho/data, escolha por item e aplicar aos demais.
- Coluna de alterações e lista de removidos com restauração.
- Cópias em blocos canceláveis e rollback de extrações.
- Ações úteis nos recentes e identificação dos indisponíveis, sem favoritos.

## Preferências 2.4

- Sete abas nativas: Geral, Aparência, Navegação, Extração, Compactação, Edição e Avançado.
- Preferências persistentes com efeitos no documento, na lista, na extração e na edição externa.
- Memória de ordenação e larguras; reabertura do último arquivo salvo.
- Pasta temporária e limites de prévia configuráveis.
- Restaurar padrões com confirmação, preservando arquivos e recentes.

## Janelas e visualização 2.5

- Gerenciador de janelas nativas, documentos independentes, comandos direcionados à janela ativa.
- Eventos de abertura do Finder abrem novas janelas; arquivo já aberto é focado sem duplicação.
- Lista, árvore expansível, colunas e grade de ícones no seletor da toolbar.
- Resumo de removidos com toda a linha clicável.
- Cópia de teste isolada encerrada; testes posteriores não geram ícone no Dock.
