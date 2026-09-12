# MarketYE — Pacote de QA (agente QA Senior, 12/09/2026)

> Entregável do nó de QUALIDADE do trio (planejamento → execução → conferência).
> Este documento não aprova nada: entrega evidência, defeitos e recomendação. A
> decisão de liberar é humana. Regra de ouro aplicada: **sem prova reproduzível
> o status é "não provado", nunca "passou"**.

## Entendimento inicial

| Item | Valor |
|---|---|
| Feature | MarketYE — marketplace de serviços (antiga "Rede de Parceiros"), MVP conexão/lead sem pagamento intra-plataforma |
| Versão testada | `main` até o commit `abb452f` + este pacote de rotinas (PRs #481–#484, #487–#489 desta sessão; #485, #486 de outra sessão) |
| Requisito de referência | Documento de Requisitos v2.0 (11/09/2026): RN-001..037, RF-001..030, CA-001..023 |
| Ambiente de prova | Réplica local (997 migrations) para banco; ambiente de teste (`bmehdgthciuvdbvutsdv`, site https://ustudy123.github.io/youreyesnovo/teste/) para tela e esteira |
| Onde os casos vivem | Super Admin → QA e Testes → **Documentação de Teste** → módulo **MarketYE**: MKY-001..015 (api, com rotina), MKY-020..022 (e2e, com Cypress) e **MKY-030..161** (este pacote: 13 famílias, documentados, sem rotina ainda) |

**Premissas.** (1) A produção não recebeu o módulo; tudo abaixo vale para o ambiente de teste. (2) A chave da IA (`OPENAI_API_KEY`) pode não estar configurada no ambiente de teste: casos que dependem dela ficam "não provado". (3) O segredo `QA_E2E_TOKEN` não está no repositório: a esteira pula a guarda de cobertura e a semeadura da conta-robô (defeito D-08). (4) Os textos dos termos são placeholders (`2026-09-v1`) até a redação jurídica final.

## 1. Auditoria do requisito (shift-left)

| # | Achado | Tipo | Efeito no teste | Ação sugerida |
|---|---|---|---|---|
| A1 | Piso de nota 3,5 e pesos de relevância marcados `[SUPOSIÇÃO — validar]` | lacuna | os oráculos de CA-005/CA-010 usam os valores parametrizados em `marketplace_config`, não valores "corretos" | dono do produto valida os números; o teste só prova que o parâmetro é aplicado |
| A2 | Quais categorias exigem registro `[VALIDAÇÃO JURÍDICA]` | lacuna | MKY-035 prova o mecanismo (`exige_registro`), não a lista | jurídico entrega a lista; vira dado de taxonomia, não código |
| A3 | Prazos de retenção por tipo de dado (25) indefinidos | lacuna | MKY-091 fica `decisao_de_produto`; exclusão de documentos do Storage na saída não está construída | DPO/advogado define prazos; parametrizar |
| A4 | Grau de bloqueio de contato no MVP `[DECISÃO HUMANA]` | ambiguidade resolvida na prática (mascarar até liberação) | MKY-006/070/071 testam o que foi construído | registrar a decisão no requisito |
| A5 | RN-027 fala em SLA "opt-in", mas não existe a opção de o prestador ligar/desligar o sinal; a saúde recente é sempre calculada | conflito requisito × build | CA-018 só é provável na parte "sem penalização" (MKY-072/073) | decidir: opt-in real (campo no perfil) ou reescrever a RN como "sinal transparente" |
| A6 | CA-006 fala em "impressões de proteção"; o build protege por dias/avaliações, não conta impressões | divergência | MKY-062 testa dias/avaliações | aceitar a implementação ou construir contagem de impressões |
| A7 | RN-002 diz "visível a todos os clientes ativos"; a política herdada `Public can view active professionals` deixa a leitura de perfis ativos aberta a visitante (sem PII) | ambiguidade de escopo | MKY-094/114 tratam como "pública por desenho" até decisão | decidir se a vitrine é pública ou só logada; ajustar política e grants |
| A8 | RF-027 (moderação automática por IA) e 6.2 (OCR, fingerprint, cooldown) não estão no build | fora do build atual | MKY-039/046 documentam; 046 prova que a IA não decide sozinha | planejar a onda; manter human-in-the-loop |
| A9 | Seção 19 (notificações por e-mail/WhatsApp) não construída | fora do build | nenhum caso de notificação; "Novo lead" só aparece no portal | onda seguinte |
| A10 | 12.2 (benefícios concretos por nível) não definidos | lacuna | níveis testados só como visibilidade (MKY-085/106) | definir benefícios antes de prometer |
| A11 | 3.4 instrumentos contratuais são placeholders | bloqueador jurídico de produção | consentimento é testado pela mecânica (MKY-033/093), não pelo texto | redação final antes de expor perfis reais |
| A12 | Critério não testável: "IA gera anúncio a partir de ≤3 campos" (CA-002) sem definir qualidade mínima | não-testável como está | MKY-050 verifica forma (campos preenchidos, sem contato), não qualidade | definir rubrica mínima ou aceitar revisão humana amostral |

## 2. Análise de risco e estratégia

| Área | Risco | Por quê | Nível de teste | Profundidade | Casos |
|---|---|---|---|---|---|
| Isolamento multi-tenant e RLS | **Crítico** | 1.100+ empresas; herança de incidente de exposição | banco (rotinas SQL com claims) | matriz tabela × operação, lado negativo | 002, 012, 071, 094, 095, 110–116 |
| Escrita sensível só por função (RN-021) | **Crítico** | classe de vulnerabilidade conhecida | banco | por tabela | 001, 013, 116 |
| Busca e relevância | **Crítico** | é o produto; já quebrou em produção de teste (D-02) | banco + e2e | filtros um a um, relaxamento, pesos | 015, 021, 060–069 |
| Devido processo e moderação | **Alto** | dever legal pós-STF; léxico anti-vínculo | banco + e2e | fluxo completo com trilha | 007, 008, 040–047, 096 |
| Avaliação e anti-gaming | **Alto** | reputação é o ativo; gaming barato destrói confiança | banco | janelas, pares, autocompra, níveis | 003, 004, 010, 080–088 |
| LGPD do não-usuário | **Crítico** | dado pessoal exposto a 1.100 empresas; direitos do titular | banco | consentimento, exportação, exclusão, minimização | 009, 033, 090–096 |
| Cadastro, anúncio, portal | **Alto** | porta de entrada; já quebrou (D-01) | banco + e2e | caminho feliz + validações | 014, 030–039, 050–058 |
| Integrações e invariantes YE | **Alto** | regra global da casa | banco + e2e | presença e vínculo | 075, 076, 120–124 |
| IA | Médio | ajuda, não exigência; risco de leakage | integração (função) | saída filtrada, degradação | 130–135 |
| UX, linguagem, acessibilidade | Médio | leigo precisa entender; RN-028 | e2e | varredura de texto, axe | 044, 142–146 |
| Desempenho | Médio | volume de oferta cresce | banco (carga) | p95 com 500 anúncios | 069 |
| Pagamento (Evolução) | fora do escopo | GATE jurídico | — | — | 160, 161 |

Pirâmide aplicada: **banco** (rotinas `qa_caso_mky_*`, equivalente da casa ao pgTAP: rodam em transação descartada com claims reais) recebe a maior fatia; **integração** cobre as Edge Functions; **e2e** só jornadas críticas e recuperação de erro.

## 3. Casos de teste

Os casos completos (objetivo, pré-condições, passos com resultado esperado, oráculo, base legal, observações, disposição) estão na Documentação de Teste. Resumo por família:

| Família | Códigos | Qtde | Nível | Foco |
|---|---|---|---|---|
| Cadastro e verificação | MKY-030..039 | 10 | api/e2e | cadastro mínimo, DV, unicidade, consentimento, registro por categoria, anti-leakage na bio, recadastro, cooldown |
| Moderação e devido processo | MKY-040..047 | 8 | api/e2e | aprovar/recusar com motivo, acesso negado, takedown, suspensão, selos, transparência, human-in-the-loop, não-usuário |
| Anúncios, preço, promoção, cupom, destaque | MKY-050..058 | 9 | api/e2e | IA monta, contato no texto, preço, estados, promoção, cupom, destaque × piso/teto, trilha de autonomia, mídia × documentos |
| Busca, relevância, geo, demanda latente | MKY-060..069 | 10 | api/e2e | filtros, personalização, novato, geolocalização, busca vazia, agregação anônima, linguagem natural, alerta → vitrine, visibilidade, desempenho |
| Conversa e contato | MKY-070..077 | 8 | api/e2e | jornada, isolamento, recusa sem punição, sem resposta sem sanção, janela, documento, invariantes, cupom |
| Avaliação e reputação | MKY-080..088 | 9 | api | janela, par, autocompra, saúde 90 d, piso com mínimo, nível simultâneo, resposta, moderação, bidirecional |
| LGPD | MKY-090..096 | 7 | api | exportação, exclusão e retenção, lead aberto, nova versão de termos, minimização, dados do cliente, art. 20 |
| Governança e parâmetros | MKY-100..106 | 7 | api | versão de config, normalização, leitura × escrita, taxonomia, IA sugere, painel, níveis |
| Segurança, RLS e RPC | MKY-110..117 | 8 | api | matriz negativa por tabela (especialista e empresa), estrutura de RLS, falha silenciosa, grants, injeção, guardas, Edge Function |
| Integrações e invariantes | MKY-120..124 | 5 | api/e2e | alerta → especialista, ação 5W2H, Documentos, dado único, parceiro sem privilégio |
| IA | MKY-130..135 | 6 | api/e2e | indisponível, anti-leakage, preço, resumo fiel, injeção de prompt, tempo |
| Jornadas e UX | MKY-140..146 | 7 | e2e | prestador, empresa, papéis, Meu caminho, recuperação de erro, linguagem, acessibilidade |
| Evolução | MKY-160..161 | 2 | api | pagamento e take rate (fora de escopo, para fechar a matriz) |
| **Total novo** | | **96** | 77 api / 19 e2e | 36 críticos, 41 altos, 19 médios |
| Já existentes com prova | MKY-001..015, 020..022 | 18 | 15 api / 3 e2e | todos **passou** na última corrida (bateria 15/15; Cypress 3/3 na corrida #429) |

Casos de borda gerados pela IA que um roteiro humano tende a pular: MKY-032 (formatação do CNPJ), MKY-038 (recadastro pós-exclusão), MKY-052 (faixa invertida), MKY-064 (uma linha por dia), MKY-081 (4ª avaliação do par), MKY-082 (autocompra por identidade dupla), MKY-092 (exclusão com conversa aberta), MKY-101 (soma ≠ 100%), MKY-113 (falha silenciosa), MKY-115 (curingas na busca), MKY-134 (injeção de prompt), MKY-135 (tempo da IA).

## 4. Testes de banco (equivalente pgTAP da casa)

A casa não usa pgTAP; usa rotinas `qa_caso_<x>()` que devolvem `qa_retorno`, executadas por `qa_rodar_bateria` **em transação descartada**, com `set_config('request.jwt.claims', ...)` + `SET LOCAL ROLE authenticated` para provar o lado positivo e o **negativo** do RLS. É o mesmo desenho do pgTAP, sem a extensão.

**Rotinas existentes (22, todas passando):** 001 cadastro pendente e guarda; 002 perfil global cross-tenant; 003 avaliação só com transação; 004 piso × destaque; 005 célula mínima; 006 mascaramento; 007 léxico; 008 contestação; 009 exclusão LGPD; 010 ajuste de nível com aviso; 011 trilha de autonomia; 012 colunas sensíveis fechadas; 013 guarda de status/selo; 014 portal após cadastro mínimo (regressão D-01); 015 relaxamento sem erro (regressão D-02); **110–116 família de segurança** (migration 20260912030000): matriz negativa especialista × especialista (110) e empresa × empresa (111) com controles positivos, estrutura do RLS e colunas sensíveis (112), escrita silenciosa (113), superfície de EXECUTE (114), entrada hostil (115) e escrita direta nas tabelas expostas (116). Todas montam o cenário compartilhado `qa_mky_cenario_seguranca()` (dois especialistas, duas empresas, conversas, mensagens, cupom, contestação, ocorrência, destaque, documento, denúncia, contratação, demanda latente).

**Erros clássicos de RLS verificados neste pacote (a escrever como rotinas):**

| Erro clássico | Caso | O que prova | Resultado |
|---|---|---|---|
| Política permissiva demais (`USING true`) em tabela sensível | MKY-112 | nenhuma em leads, mensagens, consentimentos, documentos | **passou** |
| `WITH CHECK` ausente | MKY-110/111/116 | INSERT com id de terceiro recusado | **passou** |
| UPDATE sem SELECT correspondente (falha silenciosa) | MKY-113 | negado ou 0 linhas, valor inalterado | **passou** |
| Tabela com RLS e zero políticas (inacessível por engano) | MKY-112 | toda tabela `marketplace_*` com RLS tem ≥ 1 política | **passou** |
| RPC com `EXECUTE` a `anon`/`authenticated` expondo capacidade sensível | MKY-114, MKY-041 | anon só na vitrine pública, vagas de demanda e consulta do próprio id; internas só service_role | **passou** (após D-05) |
| Política com subconsulta em coluna fechada para o papel | MKY-110 | leitura direta de anúncios/pacotes/contratações e upload no Storage não podem dar "permission denied" | **passou** (após D-17) |

O que a família encontrou ao ser executada pela primeira vez (12/09): D-16 (anon com SELECT de tabela inteira em avaliações) e **D-17 (13 políticas quebradas por lerem `user_id` fechado)** — as duas corrigidas na mesma migration das rotinas.

Levantamento estrutural feito na réplica (12/09): 23 tabelas `marketplace_*` com RLS, todas com ≥ 1 política; 51 funções `marketye_*`, das quais 47 com EXECUTE a `anon` (herança do `PUBLIC` padrão do Postgres) e apenas 4 restritas a `service_role` (`buscar_interno`, `cadastrar_especialista_para`, `recalcular_reputacao`, `semear_ilha_teste`). As 8 funções administrativas checam `is_superadmin(auth.uid())` por dentro (conferido: moderacao_fila, contestacoes_fila, painel_liquidez, transparencia, destaque_criar, especialista_situacao, denuncia_decidir, contestacao_decidir).

## 5. Conformidade legal

| Norma | O que o módulo faz | Aplicada? | Parametrizada? | Versionada? | Casos | Status |
|---|---|---|---|---|---|---|
| LGPD art. 7º I e art. 8º (consentimento destacado, por versão, revogável) | 3 consentimentos por versão com IP/UA; nova versão exige novo aceite | sim | sim (`termos_versoes`) | sim | 001, 033, 093 | 001 passou; 033/093 não provado |
| LGPD art. 18 (acesso, portabilidade, eliminação) | exportação JSON; exclusão anonimiza e retém transações | sim | retenção **não** (prazos indefinidos) | — | 009, 090, 091, 092 | 009 passou; demais não provado; 091 pende decisão |
| LGPD art. 20 (revisão de decisão automatizada) | contestação por canal único com decisão humana | sim | — | trilha | 008, 096 | 008 passou; 096 não provado |
| LGPD art. 6º III/VII e art. 46 (minimização, segurança) | colunas sensíveis fechadas; leads privados | sim | — | — | 012, 094, 095, 110, 111 | 012 passou; demais não provado |
| CDC arts. 36–37 (publicidade identificada, não enganosa) | "Patrocinado" rotulado; destaque não passa o piso | sim | sim (`destaque`) | sim | 004, 056 | 004 passou; 056 não provado |
| CDC arts. 30/35 (teoria da aparência; selo ≠ garantia) | textos de selo falam em dados conferidos | sim (texto) | — | — | 044 | não provado (varredura a montar) |
| Marco Civil art. 19 (pós-STF: notice-and-takedown, devido processo, transparência) | denúncia → decisão humana; contestação; relatório | sim | — | trilha | 042, 045, 046, 047 | não provado |
| CLT arts. 2º e 3º (autonomia; anti-vínculo) | preço/horário/política do prestador; recusa sem punição; léxico | sim | — | eventos | 007, 011, 057, 072, 073 | 007/011 passou; demais não provado |
| Conselhos profissionais (registro por categoria) | `exige_registro` por subárea | sim | sim (taxonomia) | sim (`versao`) | 035 | não provado; lista de categorias pende jurídico |
| Lei 13.146/2015 art. 63 + WCAG 2.1 AA | tema escuro, teclado, rótulos | parcial | — | — | 146 | não provado (axe não instalado) |
| LC 116/2003, BCB (pagamento, NF da taxa) | fora do MVP | — | — | — | 160, 161 | fora de escopo |

Regra legal fixada em código encontrada: o limite anti-gaming "3 avaliações por par em 30 dias" e o mínimo de 3 resultados que dispara o relaxamento estão escritos na função, não em `marketplace_config` (D-10). Não são regras de lei, mas são regras vivas e deveriam ser parâmetro.

## 6. Verificação das invariantes globais do YourEyes

| Invariante | Onde está | Situação | Caso |
|---|---|---|---|
| "Analisar com IA" + "Criar ação no Plano de Ação" em alerta relevante | conversa do lead: **presente**; alertas de compliance/psicossocial: link "Encontrar especialista" **não ligado** | parcial (D-07) | 076, 120, 121 |
| Documento gerado/importado vai ao módulo Documentos com metadados/versão/vigência | vínculo lead ↔ documento existe (`marketplace_lead_documentos`); metadados de origem/versão no módulo Documentos **a provar** | não provado | 075, 122 |
| Dado cadastrado uma única vez | busca usa `empresa_cadastro` (endereço/UF) sem redigitar | sim | 123 |
| Isolamento multi-tenant | colunas sensíveis fechadas (012 passou); linhas por tenant e por especialista **a provar tabela a tabela** | parcial | 002, 012, 071, 110, 111 |

## 7. Caça às classes de bug do YE

| Classe | Resultado da caça | Evidência |
|---|---|---|
| (i) Regra cadastrada e não aplicada | As 11 chaves de `marketplace_config` são lidas por alguma função (`relevancia_pesos`, `piso_nota`, `protecao_novato`, `niveis`, `saude_recente`, `demanda_latente`, `mascaramento_contato`, `janela_avaliacao_dias`, `termos_versoes`, `localizacao`, `destaque`). `localizacao` é lida mas ainda não muda comportamento (preparação América do Sul) — aceitável, documentado. | grep nas funções (12/09) |
| (ii) Zero/nulo que propaga em silêncio | **Encontrado e corrigido**: `especialidades` nulo derrubava o portal (D-01). Verificados sem problema: `nota_media` 0 aparece como "sem avaliações"; sem linha de reputação a saúde vira "cinza" (60) e não zero; sem `empresa_cadastro` a busca não injeta UF. | MKY-014; leitura de `marketye_buscar_interno` |
| (iii) Vazamento entre tenants | Colunas sensíveis fechadas (passou). Matriz negativa especialista × especialista e empresa × empresa provada (110/111 passou). Perfis ativos legíveis por visitante (sem PII) por política herdada — decisão de produto (A7). Grants de EXECUTE a `anon` (D-05) e SELECT de anon em avaliações (D-16) corrigidos; aviso de nível fechado (D-15). Storage: documentos privados, fotos públicas; políticas reescritas (D-17). | MKY-012, 110, 111, 112, 114 |
| (iv) Invariantes ausentes | "Encontrar especialista" não ligado aos alertas (D-07); metadados no módulo Documentos a provar. | MKY-120/122 |
| (v) Regra fixada em código | "3 por par em 30 dias" e "mínimo 3 resultados para relaxar" (D-10). Ordem de relaxamento fixa (aceitável: é algoritmo, não regra de negócio). | `marketye_avaliar`, `marketye_buscar` |

## 8. Defeitos encontrados

| ID | Descrição | Reprodução | Severidade | Prioridade | Evidência | Área/risco | Causa provável | Situação |
|---|---|---|---|---|---|---|---|---|
| D-01 | Portal preso no carregamento após cadastro mínimo | cadastro sem área → `/marketye/portal` | Crítica | Crítica | `cannot get array length of a scalar`; MKY-014 | Cadastro/Alto | `jsonb_array_length` sobre `null` | **Corrigido** (PR #483) |
| D-02 | Busca quebra ao relaxar filtros quando a empresa tem estado cadastrado e há < 3 resultados | vitrine filtrada por Segurança do Trabalho no teste | Crítica | Crítica | `malformed array literal: "uf"`; MKY-015; corrida #429 verde | Busca/Crítico | `text[] || 'uf'` resolvido como array literal | **Corrigido** (PR #488) |
| D-03 | Vitrine mostrava "sem resultados" quando a RPC falhava | interceptar `marketye_buscar` com 500 | Alta | Alta | DIAG do Cypress (corrida #428) | UX/recuperação | erro do react-query não tratado | **Corrigido** (PR #487) |
| D-04 | Semente do mobiliário de teste falhava em silêncio | migration 223000 com bloco de exceção | Média | Média | ausência de anúncio no teste | Ambiente | erro engolido em NOTICE | **Corrigido** (PRs #484/#487: função com diagnóstico) |
| D-05 | 47 funções `marketye_*` com EXECUTE a `anon` (padrão PUBLIC), incluindo moderação, config e decisões | `has_function_privilege('anon', ...)` | Média (guarda interna nega) | Alta (defesa em profundidade; herança de risco) | MKY-114 | Segurança/Crítico | ausência de `REVOKE ... FROM PUBLIC` | **Corrigido** (migration 20260912030000: anon só em `vitrine_publica`, `vagas_demanda` e `meu_id`; internas só `service_role`) |
| D-15 | `marketplace_reputacao` expunha a qualquer usuário autenticado `nivel_aviso_motivo`/`nivel_aviso_em` de todos os especialistas | `column_privileges` | Baixa | Média | MKY-112 | LGPD/privacidade do prestador | política `USING true` + SELECT de tabela inteira | **Corrigido** (leitura por coluna, sem as de aviso) |
| D-16 | Visitante anônimo com SELECT de tabela inteira em `marketplace_avaliacoes` (inclusive `tenant_id`, `avaliador_id`); a política é só para authenticated, então devolvia zero linhas, mas a concessão ficava | MKY-112 (1ª execução) | Baixa | Média | rotina 112 falhou antes da correção | Segurança | grant padrão da plataforma | **Corrigido** (REVOKE SELECT de anon) |
| D-17 | **13 políticas** (8 em `public`, 5 em `storage.objects`) liam `marketplace_profissionais.user_id` como o próprio usuário; com a coluna fechada (MKY-012), toda leitura direta de anúncios, pacotes, contratações, comissões e documentos por usuário logado e o upload/leitura de foto e documento do especialista davam `permission denied for table marketplace_profissionais` | `SELECT count(*) FROM marketplace_servicos` como authenticated | **Crítica** | **Crítica** | rotina 110 quebrou na 2ª execução; prova empírica na réplica | Cadastro/Portal/Storage; herança de risco | subconsulta em coluna sem grant, introduzida ao fechar as colunas na fundação e repetida nas políticas de Storage do #486 | **Corrigido** (políticas reescritas com `marketye_meu_id()`; sem tocar a coluna) — regressão coberta por MKY-110 |
| D-06 | Autocompra não bloqueada: `marketye_abrir_lead` não impede usuário abrir lead com o próprio cadastro de especialista | MKY-082 | Alta | Média | leitura da função (sem verificação de identidade dupla) | Anti-gaming/Alto | verificação não construída | **Provável, não provado** — executar MKY-082 |
| D-07 | Alertas de compliance/psicossocial sem "Encontrar especialista" (invariante RN-015/RF-015) | abrir um alerta de NR-1 | Alta | Alta | componente existe e não é usado fora da vitrine | Integração/Alto | ligação não feita | **Aberto** (MKY-120 `aguardando_construcao`) |
| D-08 | Esteira pula a guarda de cobertura e a semeadura da conta-robô | log da corrida: `QA_E2E_TOKEN ausente` | Média | Alta | corridas #420–#429 | Esteira | segredo não configurado no repositório | **Aberto** — configurar o segredo (ação do dono do repositório) |
| D-09 | `console.error: Error fetching user data` em toda tela na suíte Cypress | DIAG de qualquer falha | Baixa | Média | corridas #420–#429 | Autenticação | não investigado (pré-existente ou consulta de `profiles`/`user_roles` falhando na primeira carga) | **Aberto, não investigado** |
| D-10 | Limite por par (3/30 d) e mínimo de resultados para relaxar (3) fixos em código | leitura das funções | Baixa | Baixa | §7 (v) | Governança | falta de chave em `marketplace_config` | **Aberto** |
| D-11 | Normalização dos pesos para 100% possivelmente só na tela | MKY-101 | Média | Média | tela Ajustes promete; `marketye_config_salvar` grava o JSON recebido | Governança | validação só no cliente | **Não provado** — executar MKY-101 |
| D-12 | Exclusão LGPD não remove documentos de verificação/foto do Storage | MKY-091 | Alta (dado pessoal retido sem prazo) | Média (pende prazos) | leitura de `marketye_excluir_meu_perfil` (só anonimiza tabela) | LGPD/Crítico | escopo da função | **Aberto** — pende decisão de prazos (A3) |
| D-13 | Textos dos termos/política são placeholders | `termos_versoes` = `2026-09-v1` | Bloqueador jurídico | Crítica para produção | 3.4 do requisito | Jurídico | redação pendente | **Aberto** — fora do código |
| D-14 | Sem limite de tentativas na Edge Function de cadastro público | MKY-117 | Baixa | Baixa | leitura de `marketye-cadastro` | Segurança | rate limit não construído | **Aberto** (melhoria) |

Aprendizado de processo (para o próprio QA): D-02 escapou da réplica porque a empresa de teste local não tinha endereço. A partir deste pacote, a réplica de QA deve ter `empresa_cadastro` com latitude/longitude/UF para a empresa do cercado (recomendação de fixture).

## 9. Matriz de cobertura (CA × casos × status)

Status: **passou** = rotina/spec verde na última corrida; **não provado** = documentado, sem rotina ainda; **bloqueado** = depende de decisão/chave; **fora** = Evolução.

| CA | Casos | Status |
|---|---|---|
| CA-001 cadastro e 1 anúncio sem contrato | 001, 030, 031, 032, 033, 036, 117 | 001 passou; demais não provado |
| CA-002 IA gera anúncio de ≤3 campos | 050, 130, 131 | bloqueado (chave da IA) / não provado |
| CA-003 perfil cross-tenant sem vazar | 002, 012, 068, 071, 094, 095, 110, 111 | 002/012/110/111 passou; demais não provado |
| CA-004 filtros corretos; busca vazia relaxa e capta | 015, 021, 060, 063, 064, 066 | 015/021 passou; demais não provado |
| CA-005 ordem personalizada e piso | 004, 061, 084 | 004 passou; demais não provado |
| CA-006 proteção ao novato | 062 | não provado (ver A6) |
| CA-007 só transação verificada; dois eixos | 003, 074, 080, 083, 088 | 003 passou; demais não provado |
| CA-008 nível com métricas simultâneas | 085, 106 | não provado |
| CA-009 ajuste após aviso e recuperação | 010, 096 | 010 passou; 096 não provado |
| CA-010 destaque rotulado, não passa o piso | 004, 056 | 004 passou; 056 não provado |
| CA-011 alerta com IA e ação | 076, 120, 121 | não provado; 120 aguardando construção (D-07) |
| CA-012 documento no módulo Documentos | 075, 122 | não provado |
| CA-013 ação sensível só por função | 001, 013, 116 | 001/013/116 passou |
| CA-014 exclusão LGPD com retenção | 009, 091, 092 | 009 passou; 091 decisão de produto; 092 não provado |
| CA-015 parâmetros versionados sem deploy | 100, 101, 102, 106 | não provado (D-11 a verificar) |
| CA-016 split/escrow (Evolução) | 160 | fora |
| CA-017 selo ≠ garantia | 044 | não provado |
| CA-018 sem penalização automática; SLA opt-in; sem léxico disciplinar | 007, 072, 073, 145 | 007 passou; demais não provado; opt-in pende (A5) |
| CA-019 ajuste só na visibilidade | 010 | passou |
| CA-020 contestação por canal único com humano | 008, 040, 047, 096 | 008 passou; demais não provado |
| CA-021 vagas de demanda com célula mínima | 005, 065 | 005 passou; 065 não provado |
| CA-022 eventos de autonomia | 011, 057 | 011 passou; 057 não provado |
| CA-023 pagamento só após GATE (Evolução) | 160 | fora |

Cobertura por área de risco (casos documentados que já têm prova / total): Isolamento e RLS 9/13 (69%); RN-021 3/3; Busca 2/12; Devido processo 2/9; Avaliação 3/12; LGPD 2/9; Cadastro/portal 2/20; Integrações 0/7; IA 0/6; UX 1/7 (MKY-022). **Lacuna principal agora: minimização por anon (094/095) e a família de busca/reputação (lote 2).**

## 10. Recomendação

**Ambiente de teste: go-com-ressalvas** para continuar a validação humana (as três correções desta sessão estão provadas: D-01, D-02, D-03; bateria 15/15; Cypress 37/37 na corrida #429).

**Produção: no-go por enquanto.** Bloqueadores explícitos, em ordem:
1. Validação humana no ambiente de teste (regra da casa: só depois do "aprovado").
2. D-13 — textos dos termos e da política de privacidade do não-usuário em versão final (jurídico); sem isso, o consentimento colhido é sobre placeholder.
3. ~~Executar as rotinas da família de segurança (MKY-110–116)~~ **feito (7/7 passou, com D-16 e D-17 corrigidos)**; falta a minimização por anon (094, 095) antes de expor qualquer perfil real.
4. ~~D-05 — REVOKE de `anon`~~ **feito**.
5. D-06 — provar (MKY-082) e, se confirmado, bloquear autocompra em `marketye_abrir_lead`.
6. D-07 — ligar "Encontrar especialista" aos alertas (invariante global) ou registrar como onda seguinte com aceite do dono do produto.
7. Novo: o ambiente de teste precisa de uma passada manual em upload de foto/documento do especialista e leitura direta de anúncios depois de D-17 (o defeito estava em produção de teste desde a fundação).

Reverificar após correções: bateria completa (`qa_rodar_bateria('manual','rede-parceiros')`), Cypress e a conferência do script de entrega.

## 11. Plano de automação e monitoramento

**Regressão em CI/CD (já existe):** `qa_rodar_bateria` no staging (15 rotinas) e Cypress (3 specs MKY) a cada merge. **A adicionar, nesta ordem:**

| Lote | Casos | Forma | Esforço manual que elimina por ciclo |
|---|---|---|---|
| 1 — Segurança/RLS | 110, 111, 112, 113, 114, 115, 116 | **feito**: sete rotinas sobre um cenário compartilhado, na bateria do staging | ~3 h de checagem manual impossível de fazer bem à mão |
| 2 — Busca e reputação | 060, 061, 062, 063, 064, 065, 068, 080, 081, 082, 083, 084, 085 | rotinas `qa_caso_mky_*` | ~4 h |
| 3 — LGPD e governança | 090, 092, 093, 094, 095, 096, 100, 101, 102, 103, 106 | rotinas | ~2 h |
| 4 — Estruturais auto-regeneráveis | 044, 046, 112, 114, 145 | SQL sobre catálogos + varredura de texto (não dependem de layout) | ~1 h |
| 5 — Tela | 030, 040, 070, 140, 141, 142, 143, 144 | Cypress com `data-testid` semânticos já existentes (auto-regeneráveis a mudanças de layout) | ~2 h |
| 6 — IA e desempenho | 130–135, 069 | Edge Function com chave de teste; rotina de carga | ~1 h |

Estimativa: os 96 casos, a ~12 min cada em execução manual, custam ~19 h por ciclo de regressão; automatizados, custam minutos de esteira e liberam a pessoa para o teste exploratório.

**Shift-right (monitorar em produção quando entrar):** erros das RPCs `marketye_buscar` e `marketye_meu_portal` (logs do Supabase); taxa de "Não conseguimos buscar agora"; leads sem resposta > 48 h; contestações abertas > 7 dias; crescimento de demanda latente por célula; cadastros pendentes > 3 dias; console errors recorrentes (D-09). Cada anomalia realimenta um caso novo.

## Avaliação crítica do agente

1. **Qual área crítica ficou subtestada?** Isolamento entre tenants foi de 2 para 9 casos com rotina; falta a minimização por visitante (094/095). E a primeira execução da família achou um defeito crítico (D-17) que estava no ambiente de teste desde a fundação: a matriz negativa paga o próprio custo.
2. **Onde estou assumindo que "a tela funciona" logo "o cálculo está certo"?** Em relevância (pesos) e em níveis: provei que os parâmetros são lidos, não que a ordem resultante é a que o produto quer. A1 pede validação humana dos números.
3. **Testei o lado negativo do RLS?** Sim: linhas por tenant e por especialista (110/111), escrita silenciosa (113) e escrita direta (116), com controles positivos para a rotina não passar à toa.
4. **O oráculo do meu teste é a norma ou só o spec?** Nos casos de LGPD, CDC e CLT citei artigos; mas a lista de categorias reguladas e os prazos de retenção vêm do jurídico, e sem eles o oráculo é incompleto (A2, A3).
5. **Que borda a IA gerou que eu teria ignorado?** Autocompra por identidade dupla (MKY-082): o requisito prevê, o build não bloqueia, ninguém tinha olhado.
6. **Onde emiti "passou" sem prova suficiente?** Em nenhum caso novo. Os 18 "passou" têm rotina ou spec verde na corrida #429. Mas o "passou" de MKY-021 depende do mobiliário do ambiente de teste, que já falhou em silêncio antes.
7. **O que o teste de hoje não pega que o de produção pegaria?** Volume (069 não existe), latência do pooler, e-mails/notificações (não construídos), comportamento com dados reais heterogêneos (acentos, CNPJ com filiais).
8. **Que defeito já corrigido pode voltar?** D-02: qualquer nova etapa de relaxamento escrita com `||` reincide; MKY-015 cobre as cinco atuais, não uma sexta.
9. **Estou testando a regra ou a implementação?** Em 062/084/106 uso os valores da configuração como oráculo. Se a configuração estiver errada, o teste passa e o produto erra — por isso A1.
10. **O que falta para um "go" honesto de produção?** Os seis bloqueadores da seção 10; nenhum deles é de tela, todos são de segurança, jurídico ou invariante.
