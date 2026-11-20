# TabajaraZip

**Tecnologia de ponta. De estoque.**

Editor de arquivos compactados nativo para macOS, com interface em português e edição paródia das Organizações Tabajara.

<p align="center"><img src="Assets/Tabajara-AppIcon.png" width="160" alt="Ícone do TabajaraZip"></p>

## Download

Baixe o aplicativo pronto na página de [Releases](https://github.com/pessotti/TabajaraZip/releases/latest). A versão atual é **2.6.7**.

Requer **Mac com Apple Silicon e macOS 14 ou posterior**. O aplicativo distribuído usa assinatura local e não é notarizado pela Apple.

## Recursos

- Abrir ZIP, 7z, RAR, TAR e outros formatos reconhecidos pelo 7-Zip; gravar ZIP, 7z, RAR5, TAR, TGZ, TBZ2 e TXZ (RAR requer ferramenta oficial separada).
- Volumes nativos ZIP (`.z01` + `.zip`), 7z (`.7z.001`) e RAR (`.partNN.rar`), com tamanho configurável e verificação de integridade.
- Janelas independentes; abrir novamente o mesmo arquivo foca a janela existente.
- Visualizações de lista, pastas expansíveis, colunas e ícones, selecionadas na toolbar personalizável.
- Adicionar, remover, renomear, mover, editar e arrastar itens para o Finder.
- Alterações pendentes, desfazer/refazer, resumo antes de salvar, verificação e gravação segura.
- Extração seletiva, comparação de conflitos, progresso e cancelamento.
- Senhas ZIP com ZipCrypto para compatibilidade com unzip tradicional; 7z com AES-256.
- Prévia de imagens, PDF e texto; Quick Look, edição externa, Serviços do Finder, Atalhos e linha de comando.
- Sete abas de preferências, temas claro/escuro, recentes e limpeza opcional de metadados do macOS.

## Criar RAR e volumes

Em **Opções do arquivo**, escolha RAR (RAR5), ZIP ou 7z e ative **Dividir em volumes nativos**, definindo o tamanho em MB (1 MB = 1.048.576 bytes). Mantenha todas as partes juntas. Abra `.zip` para ZIP dividido, `.7z.001` para 7z ou a primeira `.partNN.rar` para RAR. Conjuntos existentes não são sobrescritos; salve alterações com outro nome.

Para criar RAR, baixe o [RAR oficial para macOS ARM64](https://www.rarlab.com/download.htm), extraia o pacote em uma pasta permanente e selecione o executável `rar` em **Ajustes → Avançado**. O motor é comercial, com avaliação; não é incluído no aplicativo. O formato de saída é RAR5, sem criação de RAR4 antigo. A abertura de RAR funciona com o motor livre incluído no app.

## Compilar

Instale o Xcode completo e selecione sua instalação como ferramenta de desenvolvimento. O projeto usa SwiftUI, AppKit e as ferramentas do Xcode; não depende de pacotes de terceiros baixados durante a compilação.

```bash
git clone https://github.com/pessotti/TabajaraZip.git
cd TabajaraZip
./build.sh
open TabajaraZip.app
```

O executável oficial 7-Zip para macOS arm64 e os arquivos de licença e código-fonte correspondentes estão em `Resources/`. O bundle e a extensão Quick Look são gerados e assinados localmente por `build.sh`.

## Testes

Após compilar:

```bash
./test.sh
./test-preferences.sh
./test-toolbar.sh
./test-drag.sh
./test-workspace.sh
./test-view-snapshots.sh
./test-native-volumes.sh  # requer RAR externo configurado ou TABAJARA_RAR
./test-diagnostics.sh
./test-bulk-extraction.sh
./test-large-edits.sh
./test-colon-names.sh
./test-audit.sh
./test-finder-permissions.sh
```

Os testes nativos exigem uma sessão gráfica do macOS. Os testes de visualização geram imagens em `/private/tmp/TabajaraViewModes`, sem criar um ícone extra no Dock.

## Documentação

- [Guia completo de uso e automação](LEIA-ME.md)
- [Recursos implementados](ROADMAP.md)
- [Validação das versões](VALIDACAO.md)
- [Licença do projeto](LICENSE)
- [Componentes de terceiros](THIRD-PARTY.md)

## Licenças e identidade

O código próprio do projeto segue a licença MIT incluída neste repositório. Os componentes do 7-Zip possuem suas próprias licenças, descritas em `Resources/7-Zip-LICENSE.txt`, `Resources/7-Zip-README.txt` e `Resources/LGPL-2.1.txt`; o código-fonte correspondente também está incluído.

Projeto independente, sem afiliação com Organizações Tabajara, WinRAR ou BetterZip.

## Logs de diagnóstico

Erros tratados pelo aplicativo, motores de compactação, prévias, processamento em lote, CLI e Atalhos ficam registrados em `~/Projetos/tabajarazip/logs/TabajaraZip.jsonl`. Cada linha contém data UTC, versão/build, operação, processo, código e detalhes do erro. Use **Ajuda → Abrir pasta de logs**. Há rotação em até cinco arquivos de aproximadamente 5 MB cada; os registros mais antigos são substituídos. Nomes e caminhos podem aparecer; senhas conhecidas são removidas e o conteúdo/saída padrão dos arquivos não é gravado. A pasta `logs/` não é versionada nem incluída no aplicativo distribuído.

Se o sistema impedir a gravação (por exemplo, em uma extensão Quick Look isolada pelo macOS), o aviso é enviado ao Console do macOS, sem interromper a operação. Falhas fatais do runtime e encerramentos forçados podem depender dos relatórios de falha do próprio macOS. Para testes isolados, `TABAJARA_LOG_DIRECTORY` altera o destino do processo.
