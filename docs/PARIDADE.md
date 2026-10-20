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

A etapa 1 corrigiu uma regress?o: a entrada gray de maskedmerge podia
dessaturar a imagem inteira. A m?scara agora fornece todos os planos em
yuva444p. O efeito escurecer usa lumin?ncia YUV no export; ele n?o equivale
a multiplicar canais RGB por preto no preview. O teste exige escurecimento
da regi?o correta e preserva??o da cor fora dela, n?o igualdade desse efeito.
