# Paridade de preview e exportação

Os testes `preview_export_parity_test.dart` executam FFmpeg, exportam arquivos
160×90 a 20 fps e leem RGB24 em instantes fixos. Não são capturas da janela
nativa. Exigem FFmpeg/ffprobe locais mesmo sem dart-define.

| Recurso | Contrato | Precisão do preview |
| --- | --- | --- |
| Camadas | Ordem inferior → superior; seleção não altera composição | Exata na ordem do modelo |
| Transparência | Composição alfa sobre camada inferior | Mesma operação; RGB tolera 18 níveis por compressão/YUV |
| Fade | Rampa linear no começo/fim do clipe | Mesma curva temporal; exibição depende do frame decodificado |
| Keyframes de opacidade | Interpolação linear normalizada | Mesmo modelo; teste compara RGB com tolerância de 20 níveis |
| Chroma | Remover cor sólida e preservar outra cor | Aproximada: shader RGB versus chromakey YUV do FFmpeg; bordas/spill diferem |
| Máscara | Retângulo/elipse, região e inversão | Geometria equivalente; feather, blur, pixelização e espaço de cor aproximados |
| Texto | Conteúdo, ordem, tamanho e posição | Rasterização/font fallback Flutter versus drawtext: aproximada |
| Transformações | Parâmetros e keyframes do modelo | Escala/amostragem e arredondamento de pixels podem diferir |
| Estabilização | Pós-processamento na exportação | Não aparece com o mesmo processamento no preview |

Os pixels verificados ficam no interior de regiões uniformes; não provam
equivalência de bordas, todas as máscaras ou filtros combinados. A precisão
temporal da reprodução nativa, cor/GPU e sincronismo percebido precisam de
sessão manual. Não há alegação de igualdade de pixels da janela nativa.

Comandos: em `source`, `flutter analyze --no-pub` e `flutter test --no-pub`.
A suíte adicional histórica com `TGI_RUN_FFMPEG_INTEGRATION_TESTS=true` cobre
texto, fontes e mais composições; não confundir execução padrão com essa suíte.

A etapa 1 corrigiu uma regressão: a entrada gray de maskedmerge podia
dessaturar a imagem inteira. A máscara agora fornece todos os planos em
yuva444p. O efeito escurecer usa luminância YUV no export; ele não equivale
a multiplicar canais RGB por preto no preview. O teste exige escurecimento
da região correta e preservação da cor fora dela, não igualdade desse efeito.

## Dissolve A/B

Um preset `dissolve` numa emenda entre vídeos adjacentes da mesma pista agora
gera `xfade` e `acrossfade` sobre a timeline composta, antes da codificação.
Como as transições v14 são globais, a mistura afeta a composição inteira na
emenda, inclusive outras camadas. Não há novo campo ou alteração de formato.

A duração da timeline é preservada: frames de borda são segurados nos handles
visuais e pequenos trechos de áudio de borda são repetidos para o crossfade,
sem preencher o centro com silêncio. Isso não é um editor de handles externos
ao trim. A duração é limitada pelos clipes adjacentes e por janelas anteriores.
Transições sem par adjacente mantêm o comportamento sintético anterior.

O preview mistura duas superfícies media_kit dos arquivos A/B, com a mesma
rampa linear, sem áudio adicional. É aproximado: não recompõe todos os efeitos
dessas superfícies, não mistura todo o áudio e depende do seek/decodificador.
O teste executado checa pixels, duração e presença simultânea de tons de
220/880 Hz no export. Não foi validado visualmente na janela nativa.
