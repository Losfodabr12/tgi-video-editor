# Interface do Frame Studio

Os valores de referência ficam em `source/lib/app/theme/design_tokens.dart`.
`app_theme.dart` aplica esses tokens aos controles do Material. Os nomes
antigos dos tokens são aliases para preservar os componentes existentes.

| Papel | Valor |
| --- | --- |
| Fundo / canvas | `#101216` |
| Painéis / barras | `#20242B` |
| Controles / superfície elevada | `#343B46` |
| Destaque da interface | `#82D9B0` |
| Espaçamento | 4, 8, 12, 16, 20, 24 px |
| Raios | 2, 4, 6 px |
| Fonte da interface | Lato, regular e bold, família `Editor UI` |
| Ícones | Material Icons, distribuídos pelo SDK Flutter |
| Densidade | `VisualDensity.compact` em todos os estilos salvos |

Os clipes usam cores semânticas: vídeo azul, áudio verde, imagem violeta,
texto ocre. Essas cores identificam conteúdo; o destaque de seleção e ações
continua único. Thumbnails vêm do arquivo/cache de mídia, e a waveform dos
samples calculados pelo serviço de áudio. O teste visual fornece samples
determinísticos; ele não mede a qualidade da extração de áudio.

O playhead usa uma linha de 2 px sem blur. Ao arrastar ou redimensionar até um
ponto de snapping, a borda correspondente mostra `SNAP`. Os divisores entre
biblioteca, preview, propriedades e timeline têm cursor de resize; duplo clique
restaura o layout. As proporções são salvas em `editor_layout.json` nos dados
locais do aplicativo, separadas do projeto v14.

Sombras foram retiradas da interface do editor, e bordas definem os controles.
O gradiente do efeito de vídeo *light leak* permanece: é conteúdo renderizado
no preview, não decoração da interface. Fontes escolhidas pelo usuário para
títulos/legendas também são conteúdo do vídeo e continuam disponíveis.
Preferências antigas de aparência são lidas, mas usam a mesma paleta compacta.

## Regressão visual

`source/test/visual_golden_test.dart` cobre editor vazio, propriedades de texto,
exportação, atalhos e timeline com thumbnails, waveform e snapping ativo.
Carrega os bytes da fonte do repositório e os ícones do SDK, sem depender da
pasta `aplicativo/` ou de fontes instaladas no Windows. Os goldens de referência
foram gerados em Windows com Flutter 3.44.4, viewport 1440×900, escala 1.

Execute pelo caminho curto usado no build:

```powershell
./tool/test_editor.ps1
```

Para atualizar referências intencionalmente, dentro de `source/` pelo mesmo
drive curto: `flutter test --no-pub test/visual_golden_test.dart --update-goldens`.
A comparação padrão é exata, sem tolerância de pixels. Não substitui avaliação
da janela nativa, DPI, drivers, playback ou desempenho.

A fonte regular foi obtida de [Google Fonts / Lato](https://github.com/google/fonts/blob/main/ofl/lato/Lato-Regular.ttf),
sob SIL OFL 1.1 (`source/assets/fonts/lato-OFL.txt`). SHA-256 do arquivo incluído:
`d636e4683231f931eda222d588e944d082bfd3bdba02f928bee461c0f185b251`.

## Comparação capturada

Mesma cena e viewport. O título "TGI VIDEO EDITOR" é texto do projeto de teste
histórico, mantido nas duas imagens para comparação; a marca da interface é FRAME.
O antes foi renderizado antes da alteração dos tokens. O depois é o golden do
editor com propriedades. São capturas de widgets reais em ambiente headless.

| Antes | Depois |
| --- | --- |
| ![Editor antes](visual/editor-before.png) | ![Editor depois](visual/editor-after.png) |

![Timeline com snapping, cores por tipo, thumbnails e waveform](../source/test/goldens/timeline_snapping.png)
