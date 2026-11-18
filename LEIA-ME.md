# TabajaraZip 2.5.0

“Se compactar, é tecnologia. Se sumir, é pegadinha.”

App nativo para Macs com Apple Silicon, macOS 14 ou superior. O aplicativo é instalado em `/Applications/TabajaraZip.app`. A atualização mantém as preferências e a personalização da barra de ferramentas.

## Uso

Abra um arquivo ou arraste-o para a tela inicial. ZIP e 7z são indexados sem extrair todo o conteúdo. TAR comprimido precisa descompactar seu TAR interno antes da navegação.

- Adicionar: botão +, arrastar arquivos/pastas para a janela ou ⌘⇧A.
- Nova pasta: botão Pasta ou ⌘⇧N.
- Navegar: dois cliques numa pasta, caminho clicável, voltar (⌘[), avançar (⌘]), subir (⌘↑), abrir seleção (⌘↓) e ir para a raiz. O histórico também restaura a busca anterior.
- Buscar: campo de busca; pesquisa nomes e caminhos em todo o arquivo.
- Ordenar: clique nos cabeçalhos Nome, Tamanho, Comprimido ou Data.
- Botão direito: abrir, editar texto, renomear, mover, extrair e remover.
- Remover: botão direito, menu Arquivo compactado ou tecla Delete. Pastas incluem seu conteúdo.
- Prévia: painel lateral para imagens, PDF e textos; espaço para Quick Look.
- Edição externa: dois cliques num arquivo abrem uma cópia no aplicativo padrão. Salve nesse aplicativo. As mudanças são verificadas a cada três segundos e antes de salvar o arquivo compactado.
- Edição interna: botão direito > Editar texto, para UTF-8 de até 5 MB.
- Salvar: ⌘S. Antes da gravação, um resumo mostra itens adicionados, alterados, renomeados, removidos e excluídos pela limpeza/filtros, além do destino, formato e proteção atual/final. Confirme em Salvar ou cancele para continuar editando. Pastas também contam como itens. As alterações ficam pendentes até confirmar; ⌘Z desfaz e ⌘⇧Z refaz antes do salvamento.
- Converter: escolha o formato em Opções e use Salvar como / Converter (⌘⇧S).
- Modo direto: ative pelo menu Arquivo compactado, depois de salvar. Cada alteração é gravada imediatamente; desfazer fica indisponível. Há cópia temporária e verificação de integridade antes da troca. O modo direto grava imediatamente, sem resumo de confirmação.

## Janelas e visualizações

Cada ZIP aberto pelo Finder ou pelo comando Abrir ganha uma janela independente. Uma tela inicial vazia pode ser aproveitada para o primeiro arquivo. Se o mesmo arquivo já estiver aberto ou carregando, sua janela é trazida para a frente; a identificação também reconhece atalhos simbólicos. Todas as janelas pertencem ao mesmo aplicativo e usam um único ícone no Dock.

Cada janela mantém sua seleção, navegação, alterações pendentes, modo de visualização e cópia de trabalho. Salvar e Desfazer atuam na janela ativa. Fechar uma janela com alterações pede confirmação; sair do aplicativo verifica todas as janelas antes de descartar qualquer alteração. Cancelar a saída preserva as sessões abertas.

O botão **Visualização** na toolbar oferece **Lista**, **Pastas expansíveis**, **Colunas** e **Ícones**. Pastas expansíveis abrem seus conteúdos na própria lista; Colunas mantém as pastas anteriores visíveis; Ícones mostra os tipos de arquivo em uma grade. A escolha é lembrada para novas janelas sem mudar as demais já abertas. A busca continua mostrando resultados de todo o arquivo em uma lista. A linha **Removidos ao salvar** pode ser expandida clicando tanto na seta quanto no texto.

## Preferências do aplicativo

Abra **Arquivo > Preferências do app…** ou use **⌘,**. As sete abas salvam suas escolhas automaticamente:

- **Geral:** tela inicial ou último arquivo salvo ao iniciar; limite de 5, 10, 15, 25 ou 50 recentes; limpar recentes; confirmar remoções.
- **Aparência:** Sistema/Claro/Escuro; nomes de 11, 13, 15 ou 17 pontos; linhas compactas/confortáveis; extensões visíveis; prévia aberta por padrão.
- **Navegação:** pastas primeiro; mostrar ocultos; lembrar ordenação e larguras das colunas entre aberturas. Ocultar itens afeta a visualização, não o conteúdo do arquivo nem o que é salvo ou extraído.
- **Extração:** perguntar sempre, mesma pasta do arquivo ou pasta específica; abrir o destino ao terminar; política padrão de conflitos. Os destinos explícitos de Extrair aqui e Extrair em pasta são mantidos. Em arquivo novo sem destino salvo, o app pergunta onde extrair. A opção de revelar o destino vale também para as ações rápidas.
- **Compactação:** formato e compressão padrão para novos arquivos; resumo antes de salvar; limpeza global de metadados. Um arquivo já aberto mantém suas opções. O modo direto continua salvando imediatamente, sem resumo.
- **Edição:** aplicativo preferido para abrir/editar cópias externas ou padrão do macOS; confirmação antes de incorporar revisões externas. Manter a versão atual não apaga a cópia externa e evita repetir a pergunta até uma nova revisão.
- **Avançado:** pasta temporária personalizada ou do sistema; limite da prévia automática de 5 a 250 MB. Mudar a pasta temporária não desloca cópias de trabalho ativas. Arquivos maiores que o limite ainda podem ser abertos e extraídos.

**Restaurar padrões…** pede confirmação, restaura as preferências, o tema, a ordenação e as larguras; preserva arquivos e a lista de recentes. A lista permanece sujeita ao limite escolhido. A abertura do último arquivo reabre apenas a cópia salva no disco: não há recuperação de sessões ou de alterações descartadas.

## Usabilidade na versão 2.3

- **Arrastar para fora:** arraste o nome ou ícone de um arquivo/pasta para uma janela do Finder ou para a Mesa. Uma seleção de vários itens é extraída em conjunto. Arquivos protegidos pedem senha antes do gesto. O Finder recebe promessas nativas de arquivos e escolhe os nomes de destino; o conteúdo é extraído sob demanda. Escape cancela o gesto.
- **Extração rápida:** o botão Extrair oferece Extrair para…, Extrair aqui e Extrair em pasta com o nome do arquivo. As mesmas ações estão no botão direito e no menu Arquivo compactado. Extrair aqui usa a pasta do arquivo compactado; ⌘⇧E é o atalho. Sem seleção, extrai tudo. Em arquivos novos ainda não salvos, escolha Extrair para…. O seletor lembra o último destino.
- **Conflitos:** compara tamanho (também em bytes) e última modificação dos itens novo e existente. Pastas exibem o tamanho total de seus arquivos. Escolha Manter ambos, Substituir, Pular ou Cancelar, com uma caixa opcional para aplicar aos demais conflitos da operação. Substituir uma pasta troca seu conteúdo inteiro. A política escolhida nas opções continua sendo respeitada.
- **Mudanças visíveis:** a coluna Alteração identifica adicionados, alterados e renomeados. O nome anterior aparece na ajuda do item renomeado. A seção Removidos ao salvar, abaixo da lista, mostra os originais removidos e permite restaurá-los. O resumo antes de salvar continua disponível.
- **Progresso e cancelamento:** operações mostram a etapa e o item atual; a extração também informa contagem e percentual. Etapas sem estimativa usam indicador de atividade. Cancelar interrompe os processos e as cópias grandes; a extração usa preparação temporária e restaura os destinos substituídos em caso de falha ou cancelamento. A troca final de um arquivo salvo continua indivisível.
- **Recentes:** abrir, revelar no Finder, localizar arquivo movido, remover uma entrada ou limpar a lista. Arquivos não encontrados são sinalizados. Remover da lista não apaga o arquivo no disco. Sem opção de fixar favoritos.

## Barra de ferramentas personalizável

Clique com o botão direito na toolbar para escolher Ícone e Texto, Somente Ícones ou Somente Texto. Escolha Personalizar Barra de Ferramentas para abrir a paleta nativa do macOS, arrastar os botões, inserir espaço/espaço flexível ou restaurar o conjunto padrão. A mesma paleta está no menu Visualizar > Personalizar Barra de Ferramentas. Os nomes podem aparecer no idioma do sistema.

A posição dos botões e o modo de exibição ficam salvos entre aberturas. Há botões opcionais de prévia, visualização rápida, renomeação, remoção, teste de integridade e subir pasta.

Opções do arquivo fica desabilitado na tela inicial e é habilitado ao abrir um arquivo ou criar um novo. As configurações gerais continuam disponíveis no menu TabajaraZip > Configurações… (⌘,). Recentes ficam na tela inicial e no menu Arquivo. Não há favoritos.

O novo ícone usa uma prensa vermelha compactando um pacote amarelo, sobre um fundo azul, com versões para os tamanhos e resoluções Retina do macOS.

## Aparência e indicador de proteção

Em **TabajaraZip > Configurações… > Aparência**, escolha **Sistema**, **Claro** ou **Escuro**. A preferência é do aplicativo e fica salva entre aberturas. Sistema acompanha o macOS. Nomes e opções usam cores semânticas nativas; a identidade vermelha fica na faixa da marca.

A barra de status mostra a proteção do arquivo salvo: Sem senha, ZipCrypto (proteção fraca), AES-256, Criptografado (método não identificado) ou Proteção mista. Para um arquivo novo, mostra Ainda não salvo. O resumo antes de salvar permite comparar a proteção atual com a futura.

## Compactação e extração

Grava ZIP, 7z, TAR, TGZ, TBZ2 e TXZ. Abre também RAR e outros formatos reconhecidos pelo 7-Zip. ZIP e 7z não criptografados aproveitam os membros comprimidos que não mudaram. A cópia de segurança para a gravação ainda precisa de espaço em disco; arquivos sólidos 7z podem exigir recompressão.

Opções do arquivo permitem nível de compressão, senha em ZIP/7z e filtros por nome/caminho. Separe padrões por ponto e vírgula, como `*.pdf;*.txt` ou `*.tmp;build/*`. Configurações salvas incluem essas opções e a política de conflitos, sem armazenar senhas.

Em **TabajaraZip > Configurações… (⌘,)**, a preferência geral **“Excluir .DS_Store e _MACOSX”** vem ligada por padrão. Ao salvar, remove todos os `.DS_Store` e as pastas `_MACOSX` / `__MACOSX`, inclusive em subpastas. A escolha vale para todos os arquivos, gravações em lote e ações de compactação do app; fica guardada entre aberturas. Essa preferência não faz parte do arquivo compactado nem das configurações salvas de compactação. Arquivos com prefixo `._` são preservados, salvo se excluídos por um filtro explícito.

ZIP com senha usa ZipCrypto e compressão Deflate (ou armazenamento sem compressão), para compatibilidade com unzip tradicional. ZipCrypto é uma proteção fraca, inferior a AES. Use senha com caracteres ASCII imprimíveis, sem acentos ou emojis. 7z continua usando AES-256, aceita Unicode e também oculta os nomes dos arquivos. Os campos de senha e confirmação exibem texto legível. Senhas são fornecidas ao motor pela entrada padrão e ficam somente na memória da sessão. Para um 7z com nomes criptografados, use Arquivo > Abrir com senha.

Ao adicionar ou extrair itens com nomes repetidos, escolha substituir, ignorar ou manter ambos. Substituir uma pasta troca a pasta inteira, sem mesclar seu conteúdo. A extração conserva a estrutura relativa dos itens selecionados e prepara o conteúdo antes de copiar para o destino.

## Ferramentas

O menu Arquivo compactado oferece teste de integridade do arquivo salvo, SHA-256, compactação e extração em lote, divisão em volumes e reunião de volumes. Na extração em lote, cada arquivo vai para uma pasta separada e o relatório mostra os sucessos e erros.

A divisão cria segmentos binários `.001`, `.002` etc. Selecione o primeiro ao reunir. Não são volumes RAR. Mantenha todas as partes juntas. A reunião detecta lacunas na sequência; não pode detectar que a última parte foi omitida sem informação externa de tamanho/hash.

“Tentar recuperar ZIP” tenta salvar membros íntegros de um ZIP danificado em outra cópia e testa o resultado. Confira os itens recuperados: esta função não recria dados perdidos. Criação/reparo de RAR e registros de recuperação RAR exigem outro motor e não estão incluídos.

## Salvamento e arquivos temporários

Não há recuperação de sessões nem sidebar de navegação. Durante a edição, o app mantém somente uma cópia de trabalho temporária; ela é apagada ao sair normalmente ou abrir outro arquivo. “Sair e perder mudanças” descarta as alterações não salvas e preserva o último arquivo gravado.

A gravação testa o novo arquivo e valida a lista de membros antes de substituir o original. Mudanças externas de tamanho/data no original interrompem a gravação. Cancelar antes dessa substituição preserva o original. A troca final é uma etapa curta e indivisível.

Links simbólicos, hard links e arquivos especiais são identificados na listagem, mas sua extração/conversão é bloqueada. Adicionar links também é bloqueado. Nomes com caminhos inseguros ou colisões que o disco do Mac não pode representar são rejeitados. Metadados extras proprietários e assinaturas de arquivos compactados não têm preservação garantida.

## Finder e Atalhos

O aplicativo declara os serviços “Compactar com TabajaraZip” e “Extrair com TabajaraZip”, acessíveis no Finder > Serviços para arquivos selecionados. Caso o macOS não os mostre, habilite-os nos ajustes de Teclado > Atalhos > Serviços.

Uma extensão de Quick Look está incluída para listar ZIP, 7z, RAR e TAR diretamente no Finder. A disponibilidade depende da aceitação/ativação da extensão pelo macOS; outra extensão instalada pode ter precedência. O Quick Look dentro do aplicativo funciona independentemente dessa extensão.

As ações nativas “Compactar com TabajaraZip” e “Extrair com TabajaraZip” são publicadas para o app Atalhos. Recebem arquivos e devolvem os resultados, que podem ser encaminhados a Salvar arquivo. Essas ações não solicitam senhas; use o app para arquivos protegidos. Há também a interface de linha de comando abaixo.

## Automação por linha de comando

Executável: `/Applications/TabajaraZip.app/Contents/MacOS/TabajaraZip`

```bash
"/Applications/TabajaraZip.app/Contents/MacOS/TabajaraZip" --cli list arquivo.zip
"/Applications/TabajaraZip.app/Contents/MacOS/TabajaraZip" --cli extract arquivo.zip destino
"/Applications/TabajaraZip.app/Contents/MacOS/TabajaraZip" --cli create novo.7z documentos --format 7z --level 9
"/Applications/TabajaraZip.app/Contents/MacOS/TabajaraZip" --cli convert novo.zip original.rar --format zip
"/Applications/TabajaraZip.app/Contents/MacOS/TabajaraZip" --cli test arquivo.zip
"/Applications/TabajaraZip.app/Contents/MacOS/TabajaraZip" --cli hash arquivo.zip
"/Applications/TabajaraZip.app/Contents/MacOS/TabajaraZip" --cli split arquivo.zip volumes 100
"/Applications/TabajaraZip.app/Contents/MacOS/TabajaraZip" --cli join volumes/arquivo.zip.001 reunido.zip
```

`list` devolve JSON. `extract` aceita caminhos internos adicionais para selecionar itens. As saídas da automação não sobrescrevem arquivos existentes. Para senha, defina `TABAJARA_PASSWORD_STDIN=1` e forneça a senha na primeira linha da entrada padrão, sem colocá-la nos argumentos. `create` e `convert` aceitam `--encrypt`, `--include` e `--exclude`.

## Código, compilação e licenças

Fontes em Sources, extensão em Extensions/QuickLook e testes em Tests. Execute `./build.sh` com Xcode e `./test.sh`, `bash test-toolbar.sh` e `bash test-drag.sh` e `bash test-preferences.sh` para verificar o motor, o modelo de documento e as ações nativas. O aplicativo usa assinatura local, sem notarização Apple.

O motor incluído é a distribuição oficial 7-Zip 26.06 para macOS arm64, executada como processo separado. Licenças, avisos e código-fonte correspondente estão incluídos em Contents/Resources. Site: https://www.7-zip.org/ . Nenhuma afiliação com Organizações Tabajara, WinRAR ou BetterZip é declarada.

O botão Extrair abre sempre o menu de opções, inclusive ao clicar no ícone. Para criar uma subpasta, use a ação explícita Extrair em pasta com o nome do arquivo; essa opção não faz parte das preferências gerais.

## RAR5 e volumes nativos (2.6.0)

Abra Opções do arquivo, selecione ZIP, 7z ou RAR (RAR5), ative Dividir em volumes nativos e informe o tamanho por parte em MB. O resumo antes de salvar mostra o formato e o tamanho escolhido. Mantenha todas as partes na mesma pasta: abra o `.zip` final de ZIP dividido, `.7z.001` ou a primeira `.partNN.rar`. Não use Reunir volumes binários para estes formatos. Para editar um conjunto, salve com outro nome: conjuntos existentes são preservados.

RAR exige o executável oficial separado, configurado em Ajustes → Avançado. O link nessa tela leva à RARLAB. RAR é comercial, com período de avaliação, e não é redistribuído dentro do TabajaraZip. A saída é RAR5; RAR4 antigo não é criado. Senhas RAR usam AES-256; ZIP mantém ZipCrypto compatível com unzip tradicional em arquivos únicos. ZIP dividido exige um extrator que suporte volumes, como TabajaraZip/7-Zip.

Automação: `--cli create pacote.rar pasta --format rar --volume-size 100`. `--volume-size MB` também aceita ZIP/7z. A saída é o caminho do arquivo a abrir. `TABAJARA_RAR` permite selecionar o motor na CLI; senhas continuam via `TABAJARA_PASSWORD_STDIN=1` e entrada padrão.
