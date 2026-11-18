# Componentes de terceiros

## 7-Zip 26.06

Distribuição oficial macOS arm64, usada como processo separado em `Resources/Tools/7zz`.

- Projeto: https://www.7-zip.org/
- Licença e condições específicas: [7-Zip-LICENSE.txt](Resources/7-Zip-LICENSE.txt)
- Avisos da distribuição: [7-Zip-README.txt](Resources/7-Zip-README.txt)
- GNU LGPL 2.1: [LGPL-2.1.txt](Resources/LGPL-2.1.txt)
- Código-fonte correspondente: [7-Zip-26.06-source.tar.xz](Resources/7-Zip-26.06-source.tar.xz)

A licença MIT do código próprio do TabajaraZip não substitui as licenças destes componentes. As restrições específicas da parte unRAR estão descritas nos arquivos de licença do 7-Zip.

## RAR oficial (opcional e externo)

A criação de RAR/RAR5 usa o executável proprietário RAR, da RARLAB/win.rar GmbH, escolhido pelo usuário. O executável, seu pacote e chaves de registro não são incluídos no repositório nem no aplicativo distribuído. Download e licença: https://www.rarlab.com/download.htm. O usuário deve observar o período de avaliação e obter a licença correspondente para uso continuado.

O motor procura `TABAJARA_RAR`, o caminho escolhido nos ajustes, `~/Library/Application Support/TabajaraZip/RAR/rar`, `/opt/homebrew/bin/rar` e `/usr/local/bin/rar`. A opção `-cfg-` evita configurações de compressão externas; senhas são transmitidas pela entrada padrão, sem argumentos de processo.
