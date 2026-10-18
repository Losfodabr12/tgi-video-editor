# Editor de vídeo — 1.4.26

Abra **TGI APP - Editor atualizado** na Área de Trabalho.

## Fontes de texto

Selecione um texto na timeline e abra suas propriedades, ou use **Texto** para
criar um novo. A lista de fontes também aparece nas legendas automáticas.

Foram incluídas **13 fontes**, disponíveis sem instalar nada no Windows:
Anton, Bebas Neue, Poppins, Lato, Lobster, Pacifico, Righteous, Bangers, Bungee,
Audiowide, Caveat Brush, Rajdhani e Russo One. As seis opções anteriores continuam
disponíveis. As fontes incluídas acompanham o app e a exportação.

## Exportar um trecho e usar a GPU

Posicione a agulha e use **I** para marcar o início e **O** para marcar o fim.
Os mesmos comandos aparecem acima da timeline. Na exportação, ative
**Exportar somente um trecho** e ajuste os segundos, se necessário.

Em **Processamento**, escolha **GPU automática** ou o fabricante da placa.
A disponibilidade é verificada com uma pequena codificação real. Se a GPU não
estiver disponível ou falhar, a exportação tenta novamente pela CPU e informa
isso ao terminar. Cancelar mantém intacto um arquivo anterior no destino.

## Histórico, modelos e projeto transportável

No topo do editor, abra **Projeto e modelos**:

- **Guardar versão agora** cria um ponto de retorno. O app também guarda
  versões no salvamento manual e, enquanto há alterações, a cada cinco minutos.
- **Histórico de versões** mostra até 30 versões por projeto. Restaurar carrega
  a versão no editor; salve para atualizar o arquivo principal.
- **Modelos pessoais** permite guardar e aplicar estilos de texto, cor e
  animação. O conteúdo e o tempo do clipe são preservados.
- **Reunir projeto e mídias** cria uma pasta com `projeto.json`, as mídias
  importadas, as transições externas e a marca-d'água utilizada. Transporte a
  pasta inteira e abra o JSON na nova localização.
- **Usar textos como legendas** inclui os textos selecionados na exportação
  SRT/VTT. Isso serve para projetos antigos que perderam essa identificação.

## Voz, música e níveis

Abra **Áudio → Níveis, voz e música**:

- **Analisar níveis** prepara o medidor de pico estimado para acompanhar a
  reprodução. A indicação vermelha ajuda a identificar possível saturação.
- Selecione a voz e use **Ajustar voz**. O ganho busca −18 dB RMS, limitado pelo
  pico medido e pelo volume máximo do editor. A automação de volume anterior é
  substituída; a operação aceita desfazer.
- Selecione a música, escolha outra trilha como **Trilha de voz**, ajuste a
  redução e use **Aplicar na música**. A música baixa durante a atividade de voz
  detectada. Você pode editar os pontos de volume e desfazer a operação.

O medidor é estimado; a análise não é uma medição LUFS/true-peak da mixagem final.
Ruídos ou música presentes na trilha escolhida como voz podem acionar a redução.

## Correções

- Legendas mantêm a exportação SRT/VTT depois de salvar e reabrir o projeto.
- O chroma key do preview calcula a transparência por pixel, inclusive para
  cores neutras, usando a mesma lógica de distância de cor da exportação.
- O preview de compatibilidade reduz a imagem antes de transferir os pixels
  e ajusta a frequência de captura ao tempo necessário para processar os quadros.

Esta é uma atualização local. A publicação na Microsoft Store é independente.
