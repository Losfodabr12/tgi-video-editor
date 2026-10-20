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
