# Migração de vídeos sobrepostos

O formato continua **v14**. A leitura normaliza projetos antigos e arquivos
v14 criados antes desta correção. Nenhum arquivo é regravado ao carregar.

Vídeos da mesma pista são ordenados pelo início e distribuídos na primeira
camada que não tenha vídeo sobreposto. Camadas adicionais ficam acima da
original, recebem IDs únicos e preservam bloqueio, altura, volume e flags.
Os objetos de clipe mantêm ID, grupo vinculado, mídia, fonte, tempo, efeitos
e keyframes. Clipes de outros tipos e pistas de áudio não são redistribuídos.

Salvar usa v14 normalmente; reabrir é idempotente. Testes dos formatos 13 e 14
cobrem três vídeos simultâneos, colisão de ID de pista, vínculos e payload.
O teste anterior que esperava rejeição de exportação foi atualizado para
esperar camadas exportáveis, conforme a nova regra solicitada.

Ao salvar sobre o arquivo original, a versão anterior à migração fica em
`nome-do-projeto.json.bak`. Isso cobre formatos anteriores ao v14 e arquivos
v14 antigos que ainda precisem separar camadas ou normalizar grupos de
legendas. O backup é uma cópia dos bytes originais; não é outro JSON gerado.
Gravações posteriores, inclusive por outra instância do serviço, preservam
esse primeiro backup. Arquivos v14 canônicos não ganham backup permanente
sem necessidade. `Salvar como` deixa o arquivo de origem intacto.

O backup temporário para rollback usa uma área separada quando já existe um
`.bak` permanente. Falhas de gravação continuam preservando o original e
liberando a fila de saves. Nenhum campo foi acrescentado ao projeto.
