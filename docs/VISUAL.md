# Interface do Frame Studio

Os valores de referência ficam em `source/lib/app/theme/design_tokens.dart`.
`app_theme.dart` aplica esses tokens aos controles do Material. Os nomes
antigos dos tokens são aliases para preservar os componentes existentes.

| Papel | Valor |
| --- | --- |
| Fundo / canvas | `#0E0F11` |
| Painéis / barras | `#15171A` |
| Controles / superfície elevada | `#1C1F23` |
| Hover | `#262A30` |
| Borda | `#2A2E34` |
| Texto / secundário | `#E6E8EB` / `#A0A7B1` |
| Destaque da interface | `#34C38F` |
| Espaçamento | 4, 8, 12, 16, 20, 24 px |
| Raios | 2, 4, 6 px |
| Fonte da interface | Lato, regular e bold, família `Editor UI` |
| Ícones | Material Icons, distribuídos pelo SDK Flutter |
| Densidade | `VisualDensity.compact` em todos os estilos salvos |

Os clipes usam fundos foscos: vídeo `#3B5B8C`, áudio `#2F7D6B`, texto
`#6B5BA8` e efeitos/transições `#A0653B`. Imagens compartilham o azul dos
visuais. A seleção mantém o fundo do tipo e acrescenta somente contorno
verde de 2 px. O verde de destaque fica para a ação principal, playhead e
seleção; toggles ligados, abas, botões auxiliares e slider de zoom usam
superfícies neutras elevadas, sem tingimento verde. Thumbnails vêm do arquivo/cache de mídia, e a waveform dos
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
exportação, atalhos, timeline com thumbnails/waveform/snapping e régua ampliada.
`visual_refinement_test.dart` cobre duração 04:53, três trilhas completas em
1440×900 e 1280×720, centralização do transporte, contorno de seleção e
legibilidade/densidade da régua em projetos de seis horas.
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
O antes mostra a versão anterior deste ajuste de paleta. O depois é o golden do
editor com propriedades. São capturas de widgets reais em ambiente headless.

| Antes | Depois |
| --- | --- |
| ![Editor antes](visual/editor-after.png) | ![Editor depois](visual/editor-refined.png) |

![Timeline com snapping, cores por tipo, thumbnails e waveform](../source/test/goldens/timeline_snapping.png)


## Layout, transporte e régua

O padrão reserva aproximadamente 45% da área de trabalho para a timeline.
A altura mínima considera cabeçalho, régua, alvo de nova camada, scrollbar e
as três primeiras trilhas com suas alturas reais. O preview conserva pelo
menos 124 px. Em janelas muito baixas, ou trilhas individualmente muito altas,
o espaço físico exige scroll; os testes de cinco resoluções anteriores
continuam verificando ausência de overflow. Proporções ajustadas pelo usuário
continuam salvas no arquivo de layout, sem alterar o projeto v14.

Sem seleção, o inspetor mostra o nome, resolução de saída, fps, duração e
quantidade de trilhas. Resolução/fps vêm da configuração atual de saída,
pois o projeto pode combinar mídias de formatos diferentes.

Play/voltar/avançar ficam exatamente no centro do preview, independentemente
da largura das ferramentas de cada lado. Corte/Excluir/Texto compartilham
o mesmo estilo e um grupo à esquerda; velocidade e proxy ficam à direita.
Ações de marcar início/fim permanecem na toolbar em ícones com tooltips
`I`/`O`; a linha extra de instruções foi removida.

O slider de zoom é logarítmico (0,5% a 3200%) e usa o mesmo caminho de zoom
que preserva o ponto de referência e suporta Ctrl + roda. A régua escolhe
intervalos conforme pixels por segundo, com no mínimo 96 px entre rótulos
principais. Em ampliação detalhada mostra milissegundos; em projetos longos,
horas. A grade usa as mesmas marcações. Só a região visível, com uma margem,
é gerada, evitando criar milhares de rótulos ao ampliar um projeto longo.

## Correção da diferença 04:53 / 04:58

A folga de cinco segundos adicionada por `_timelineExtent` serve para editar
e arrastar além do fim do conteúdo. O contador da timeline recebia essa
extensão do canvas, enquanto o preview recebia `project.timelineDuration`.
O contador agora usa a duração real, mantendo a folga somente no canvas.
O teste abre um projeto de 293 segundos e confere preview, contador e
propriedades em 04:53. Não houve modificação dos tempos dos clipes ou do export.

![Régua ampliada e duração real](../source/test/goldens/editor_zoomed.png)
