# Planejamento — Bancada de QA independente do sistema

Documento de planejamento (não é implementação). Nasce do pedido de tirar a tela
de QA do SuperAdmin de dentro do produto e transformá-la numa ferramenta à parte,
onde se escolhe o ambiente (desenvolvimento/teste, homologação, produção) e se
rodam as baterias — para que recriar a homologação a partir da produção não
apague o que a equipe montou de testes. Nada foi alterado em nenhum ambiente;
a produção segue intacta.

---

## 1. O que a tela de QA é hoje

### 1.1 As três telas

Ficam dentro do app, atrás de `SuperAdminRoute`, no caminho
Cabeçalho → **Super Admin** → botão **QA**. Vão para todos os ambientes porque
são código do produto: a esteira publica no teste e na homologação a cada merge,
e o Lovable publica na produção a cada Publicar.

| Tela | Rota | O que faz | Como fala com o banco |
|---|---|---|---|
| Painel (`QADashboard.tsx`, 866 linhas) | `/admin/qa` | Varredura de integridade (5 categorias) por IA | Edge Function `ai-qa-scan` (somente leitura, chave de serviço). Traz ainda um caminho **morto** (aba sem botão) para a `ai-qa-agent`, que loga com uma conta real fixa no código e escreve em tabelas de cliente |
| Documentação (`QADocs.tsx`, 444 linhas) | `/admin/qa/docs` | Árvore de módulos, lista de casos, editor (criar/editar/apagar caso) | Leitura e escrita **direta** nas tabelas `qa_modulos` e `qa_casos_teste`, protegidas por RLS "só superadmin" |
| Execução (`QARunner.tsx`, 844 linhas) | `/admin/qa/runner` | Motor (banco): escolher módulo, rodar bateria, agendar por dia, ver execuções, exportar PDF/planilha. Cypress: "Rodar testes", agendar, ver corridas com prints | 10 funções RPC (`qa_disparar_bateria`, `qa_listar_baterias`, `qa_resultados_da_bateria`, agendamentos…) e a Edge Function `qa-disparar-cypress` |

As telas **não sabem em que ambiente estão**. O ambiente é decidido na hora do
build pelo `.env.<modo>` (URL + chave pública do projeto Supabase). Elas não usam
layout, menu, empresa ativa nem tenant do app — só componentes shadcn, o cliente
Supabase compartilhado e o `useAuth` para saber se é superadmin. Ou seja: o
acoplamento com o produto é pequeno e está todo num ponto só, o cliente Supabase
fixo (`src/integrations/supabase/client.ts`).

### 1.2 Onde vivem os dados — e o que se perde no RECRIAR

Todas as tabelas `qa_*` moram no banco **de cada ambiente**, sem `tenant_id`
(são infraestrutura do produto, não dado de cliente). Elas se dividem em duas
naturezas, e é essa divisão que importa para o problema:

| Natureza | Tabelas | Quem escreve | Sobrevive ao RECRIAR? |
|---|---|---|---|
| **Documentação** (o que a equipe monta) | `qa_modulos`, `qa_casos_teste`, `qa_implementacoes` (caso ↔ rotina SQL), `qa_cobertura_e2e` (caso ↔ `it()` do Cypress), `qa_agendamento*` (3 tabelas), `qa_tabelas_protegidas`, `qa_mobiliario_fixo` | migrations/scripts de entrega e, no caso de `qa_casos_teste`, também a tela | **Não.** O RECRIAR copia essas 9 tabelas **da produção** (lista `PRESERVAR_TABELAS` em `scripts/homologacao/gerar_copia_mascarada.py`). "Preservar" ali significa "copiar sem máscara", não "manter o que a homologação tinha". O que foi montado só na homologação é sobrescrito pela versão mais antiga da produção |
| **Histórico** (o que as corridas geram) | `qa_execucoes`, `qa_resultados` (com os prints do Cypress) | o motor e a `qa-registrar-e2e` | Vem mascarado (texto vira `anon-…`), ou seja, ilegível. Corridas novas nascem limpas |

Detalhe que pesa: hoje não existe coluna que diga se um caso nasceu de migration
ou foi editado na tela. A única pista é `created_by` (nulo quando veio de
migration). Exportar "o que a tela mudou" é possível, mas por heurística.

### 1.3 Onde vive o motor — e por que ele não pode sair do banco

O motor é o que roda a bateria: `qa_rodar_bateria` → `qa_executar_descartavel`
→ cada rotina `qa_caso_<x>()`. Mais de 600 rotinas e uma centena de ferramentas
de fixture, tudo em PL/pgSQL **dentro do banco-alvo**, porque:

- cada bateria roda numa única transação que é **desfeita de propósito** no
  final (o veredito fica, o efeito some) — isso só existe dentro do PostgreSQL;
- as rotinas escrevem no **cercado** (tenants `qa-sandbox`/`qa-sandbox-2`,
  empresas `[QA] Alfa`/`[QA] Beta`), protegido por gatilhos `qa_guarda_cercado`
  em toda tabela com `tenant_id`, ligados só enquanto `app.qa_modo = on`
  (variável de transação — não vaza);
- boa parte das rotinas nem toca dado: lê o catálogo do próprio banco
  (`pg_proc`, `pg_policies`, `pg_trigger`) para provar que uma regra existe.
  De fora, essa prova não faz sentido;
- `qa_mobiliario_fixo` é uma **medição** do cercado em repouso, feita naquele
  banco; copiar de outro ambiente dispara alarme falso de vazamento.

Conclusão que orienta todo o resto: **a tela pode sair do produto; a
documentação pode ganhar um dono fora do banco recriável; o motor fica onde
está.** Uma ferramenta externa aciona o motor e lê o resultado, mas não o
hospeda.

### 1.4 A esteira do Cypress (teste de tela)

```
tela "Rodar testes" ──▶ Edge Function qa-disparar-cypress (JWT + superadmin ativo + GITHUB_DISPATCH_TOKEN)
                              │  escolhe o workflow pela URL do PRÓPRIO projeto:
                              │  ref da homologação → cypress-homologacao.yml, senão cypress.yml
                              ▼
                        GitHub Actions: guarda de cobertura → semeia conta-robô (seed-e2e-user)
                              → cypress run contra o site do ambiente
                              ▼
                        cypress.config.ts (after:run) ──▶ qa-registrar-e2e (x-qa-token)
                              → qa_registrar_bateria_e2e / qa_anexar_print_e2e
                              → qa_execucoes + qa_resultados do ambiente
                              ▼
                        a tela faz polling e mostra a corrida
```

Cada ambiente tem os próprios segredos (`QA_E2E_TOKEN`, `GITHUB_DISPATCH_TOKEN`
nas functions; `QA_E2E_TOKEN`/`QA_E2E_TOKEN_HOMOLOGACAO` no GitHub). O
agendamento do Cypress é um `pg_cron` do ambiente que lê `app_config`
(`github_dispatch_token`). Nada disso muda com a tela independente: a
ferramenta só precisa chamar a function **do ambiente escolhido**.

### 1.5 Travas de produção já existentes (ficam)

Build do Vite recusa modo não-produção apontando para o ref de produção;
`cypress.config.ts` só aceita hosts da lista e destrói chamadas ao ref de
produção; `seed-e2e-user` recusa o ref de produção antes da allowlist;
`qa-registrar-e2e`/`qa-cobertura-e2e` fecham sem token; `qa-disparar-cypress`
exige JWT + linha ativa em `superadmins`.

---

## 2. O diagnóstico

O pedido junta duas coisas que parecem uma só:

1. **"A tela deveria ser independente, onde eu escolho o ambiente"** — é a
   camada de apresentação. Resolve-se tirando as três telas do produto e dando a
   elas um seletor de ambiente. Custo baixo, sem mudança de banco.
2. **"Para não perder dados ao recriar a homologação"** — é a camada de
   documentação. A tela independente **sozinha não resolve isso**: ela não tem
   dado próprio, lê e escreve nas tabelas `qa_*` do ambiente escolhido. Se a
   homologação for recriada, a tela independente vai olhar para a homologação e
   ver os casos da produção, exatamente como hoje.

Há ainda uma terceira perda no RECRIAR que ninguém enxerga na tela: as
**rotinas** (funções `qa_caso_*`). A homologação anda à frente da produção
(fluxo forward-only), então tem rotinas que a produção ainda não tem. O RECRIAR
copia a estrutura da produção e essas rotinas somem também — preservar as
tabelas de documentação não as traz de volta. Só reaplicar os scripts de entrega
da bancada (idempotentes) restaura.

Então o plano tem duas metades independentes, que podem ser entregues em
ordem: **(A) a tela independente** e **(B) a documentação com dono fora do
banco recriável**. Só com as duas o RECRIAR volta a ser seguro.

---

## 3. As formas possíveis

| | Forma 1 — só a tela independente | Forma 2 — tela independente + repositório como fonte da verdade + RECRIAR que preserva | Forma 3 — Central de QA (4º projeto Supabase) |
|---|---|---|---|
| O que é | Uma tela fora do produto, com seletor de ambiente; login como superadmin **no ambiente escolhido**; dados continuam em cada ambiente | A Forma 1 mais: exportar catálogo da tela para script; RECRIAR guarda e devolve as tabelas de documentação **da própria homologação**; painel que mede o quanto cada ambiente está atrás do repositório | Um projeto Supabase só para QA, com documentação e histórico centralizados; a ferramenta manda cada ambiente executar via function com token de máquina e recolhe o resultado |
| Resolve "escolher o ambiente" | Sim | Sim | Sim (um login só) |
| Resolve "não perder no RECRIAR" | **Não** | **Sim** | Sim, para a documentação; as rotinas continuam dependendo dos scripts |
| Mudança de banco | Nenhuma | Pequena (opcional: coluna de origem em `qa_casos_teste`; function de leitura do catálogo) | Grande: motor precisa aceitar lista de casos de fora, histórico com FK relaxada, nova function `qa-executar` em **cada** projeto — inclusive produção |
| Segredos novos | Nenhum | Nenhum | Um token de máquina por ambiente guardado na central — um lugar só que alcança os três bancos, produção incluída |
| Aderência às regras da casa | Total | Total (produção só muda por script colado e Publicar) | Tensiona: cria um caminho automatizado que aciona a produção |
| Esforço | 1 a 2 sessões | + 2 a 3 sessões | + 4 a 6 sessões, e um projeto a mais para manter |

**Recomendação: Forma 2.** A Forma 1 é a metade visível do pedido e entra
primeiro, mas sem a metade B o motivo declarado (recriar sem perder) não é
atendido. A Forma 3 é a que soa mais "independente", mas o que ela centraliza
(documentação e histórico) a Forma 2 já resolve com o repositório — que é a
fonte da verdade que a casa já adotou para os testes de tela ("todo teste de
tela nasce de um caso documentado", guarda `qa:cobertura-e2e`). O preço da
Forma 3 é um quarto projeto com credenciais dos outros três, contra o
princípio de que a produção só muda por dois gestos manuais. Fica anotada como
evolução possível, não como ponto de partida.

---

## 4. Desenho da forma recomendada

### 4.1 Metade A — a Bancada de QA, tela independente

**Onde o código vive.** No mesmo repositório, numa pasta própria (`apps/qa/` —
ou `src/qa/`, a decidir na implementação) com **configuração Vite própria**
(`vite.qa.config.ts`, `npm run build:qa`). Isso importa por dois motivos:
o `vite build` padrão (o que o Lovable roda) não enxerga a bancada, então ela
**não vai para a produção**; e a configuração própria pode carregar os três
`.env.*` de uma vez, coisa que a trava do produto proíbe de propósito.

**Onde é publicada.** Na mesma página do GitHub Pages que já serve os dois
ambientes, numa terceira pasta:

- `.../youreyesnovo/teste/` → app de teste (já existe)
- `.../youreyesnovo/homologacao/` → app de homologação (já existe)
- `.../youreyesnovo/qa/` → **Bancada de QA** (nova; o `staging.yml` ganha um
  terceiro build e move para `dist/qa`)

A bancada usa uma rota só (ou roteamento por `#`), para não depender do truque
de `404.html` que hoje só distingue teste de homologação.

**Seletor de ambiente.** Uma lista fixa, montada no build a partir dos arquivos
`.env.staging`, `.env.homologacao` e `.env.production` (que só têm URL e chave
pública — valores que qualquer navegador já recebe):

| Rótulo | Projeto | Cor | Observação |
|---|---|---|---|
| Desenvolvimento/teste | `bmehdgthciuvdbvutsdv` | verde | espelho do repositório |
| Homologação | `fgsblefvdabgdouipigz` | amarelo | à frente da produção |
| Produção | `diayjpsrcerycycyaxst` | vermelho | ver decisão 6.1 |

A troca de ambiente troca o cliente Supabase inteiro (URL, chave, sessão). Cada
ambiente guarda a própria sessão em chave separada (`storageKey` por ref), então
dá para ficar logado nos três e alternar sem relogar. A tela mostra sempre
"conectado como <e-mail> em HOMOLOGAÇÃO", e no modo produção a moldura inteira
fica vermelha.

**Login.** Como superadmin **do ambiente escolhido** — cada projeto tem o
próprio `auth.users`. Consequência prática: para usar a bancada na homologação,
a pessoa precisa de conta superadmin utilizável lá (hoje só os e-mails do
secret `HOMOLOGACAO_TESTADORES` recebem senha utilizável; os demais superadmins
ficam com senha aleatória, por desenho). Na produção, é a conta real.

**O que muda no código das telas: quase nada.** As três telas, os hooks
(`useQaRunner`, `useQaDocs`), o gerador de relatórios (`qaRelatorio.ts`) e os
tipos vão para a pasta da bancada como estão. A única troca é o cliente Supabase
fixo por um cliente **do ambiente selecionado** (um provider `AmbienteQA` e um
hook `useSupabaseDoAmbiente()`). Tudo o que existe continua funcionando sem
tocar no banco, porque a autorização já é feita no servidor por sessão de
superadmin: as RPCs (`is_superadmin(auth.uid())`), a RLS das tabelas `qa_*`, a
`qa-disparar-cypress` (que passa a ser chamada na URL de functions do ambiente
escolhido e já escolhe a esteira certa sozinha) e os agendamentos (que são
`pg_cron` de cada ambiente — configurados ambiente a ambiente, como o pedido
quer: "desenvolvimento quando necessário, homologação com frequência").

**Segurança.** A bancada **nunca** carrega chave de serviço; só chaves públicas
e a sessão do superadmin. A página é pública no Pages, mas sem login de
superadmin no ambiente-alvo ela não lê nem escreve nada. Nenhum segredo novo em
lugar nenhum.

**Arrumações que vão junto, porque são o mesmo trecho de código:**
- o link "acompanhar na esteira" aponta sempre para `cypress.yml`, mesmo na
  homologação (a function já devolve a URL certa; a tela deve usá-la);
- o caminho morto da `ai-qa-agent` (aba sem botão, com e-mail e senha reais
  escritos no código e sem trava de ambiente) **não é portado** — a function
  entra na lista de remoção;
- a varredura de integridade (`ai-qa-scan`) é portada como está, sob o mesmo
  seletor.

**No produto.** Saem as três rotas `/admin/qa*` do `App.tsx` e da lista
`ROTAS_SUPERADMIN`; o botão **QA** do painel do SuperAdmin vira um link externo
para a bancada. Depois do merge, teste e homologação perdem a tela na hora; a
produção perde no próximo **Publicar no Lovable** (é o efeito desejado: hoje a
tela está nos três).

**Entrega.** Sem migration, sem script de produção. Só Publicar no Lovable,
quando aprovado, para tirar a tela do app de produção.

### 4.2 Metade B — a documentação com dono fora do banco recriável

Princípio: **o repositório é a fonte da verdade da bancada** (casos, módulos,
pontes caso↔rotina e caso↔`it()`, rotinas). A casa já faz isso em grande parte
— as migrations `qa_*_casos_*.sql` e os 16 scripts `script_qa_bancada_parte*`
são exatamente isso. O que falta é fechar três brechas:

**B1. Exportar o que a tela mudou.** A bancada ganha o botão **"Exportar
catálogo"**, que lê do ambiente escolhido `qa_modulos`, `qa_casos_teste`,
`qa_implementacoes` e `qa_cobertura_e2e` e gera um script idempotente
(`ON CONFLICT (codigo) DO UPDATE` / `ON CONFLICT (path) DO UPDATE`), pronto para
virar migration + script de entrega. Para o botão poder dizer "isto mudou na
tela e não está no repositório", vale acrescentar em `qa_casos_teste` uma coluna
`origem` (`migration` | `tela`), preenchida pela tela na escrita — hoje a única
pista é `created_by` nulo, que não pega edição de caso que nasceu em migration.
Regra de uso que acompanha: caso editado na tela **só vale** depois de exportado
e registrado no projeto; enquanto não for, é rascunho local daquele ambiente.

**B2. RECRIAR que devolve o que a homologação tinha.** No `homologacao.yml`,
antes de derrubar o schema: guardar (dump só de dados) as 9 tabelas de
documentação **da própria homologação**; depois da cópia da produção: truncar
essas 9 tabelas e restaurar o que foi guardado (é a opção A já anotada em
`docs/AMBIENTES.md`). Duas simplificações que vêm de graça:
- `qa_execucoes`/`qa_resultados` deixam de ser copiadas mascaradas (chegam
  ilegíveis e apontando para `caso_id` que não existem mais) — passam a ser
  truncadas: histórico da homologação começa limpo a cada RECRIAR, o que já
  é o comportamento efetivo hoje;
- a etapa final do workflow reaplica os scripts de entrega da bancada que a
  produção ainda não tem (são idempotentes; o painel B3 diz quais), devolvendo
  as **rotinas** que a cópia da produção não trouxe.

Com B1 + B2, a "Decisão 09/2026" pode ser revista: o RECRIAR deixa de estar
suspenso e a homologação volta a poder ser espelho da produção **sem apagar a
bancada**.

**B3. Painel "Situação da bancada" por ambiente.** Uma aba nova na bancada que
mede, para o ambiente escolhido: casos documentados, casos com rotina ligada,
rotinas cuja função **não existe** no banco (é o `nao_implementado` da bateria),
pontes órfãs, cobertura de tela — e compara com o ambiente de teste, que **é** o
repositório por construção (recebe todas as migrations). A diferença entre os
dois é a lista do que falta colar naquele ambiente. Isso transforma o fluxo
forward-only, que hoje depende de disciplina, em algo medido. A leitura do
ambiente de teste pode usar sessão de superadmin lá ou uma function de leitura
fechada por token, no padrão da `qa-cobertura-e2e` (que já devolve os casos
`e2e`; bastaria estendê-la para o catálogo inteiro).

### 4.3 Depois, se e quando fizer falta — Central de QA

O que ela acrescentaria à Forma 2: um login só; histórico dos três ambientes
lado a lado; agendamento central em vez de `pg_cron` em cada banco; produção sem
tabelas de documentação (só as funções do motor). O que custaria: um quarto
projeto Supabase; uma function `qa-executar` em cada ambiente, fechada por token
de máquina (padrão `x-qa-token` da `qa-registrar-e2e`), que roda
`qa_rodar_bateria` com chave de serviço e devolve o resultado; o motor aceitando
a lista de casos de fora (hoje ele lê `qa_casos_teste`/`qa_implementacoes`
locais); e a FK `qa_execucoes.disparada_por → usuarios_base` relaxada na
central. O ganho real aparece só quando comparar ambientes vira rotina; até lá,
o painel B3 cobre a necessidade sem o quarto projeto.

---

## 5. Etapas, esforço e riscos

| Etapa | Entrega | Esforço | Mexe no banco? | Passo de produção |
|---|---|---|---|---|
| A | Bancada em `/qa/` com seletor; telas portadas; rotas fora do produto; link no SuperAdmin; remoção da `ai-qa-agent` | 1 a 2 sessões | Não | Publicar no Lovable (tira a tela do app) |
| B1 | Exportar catálogo + coluna `origem` + regra de uso | 1 sessão | Sim, pequena (migration + script, idempotentes) | Script no SQL Editor |
| B3 | Painel "Situação da bancada" (extensão da `qa-cobertura-e2e`) | 1 sessão | Não (function) | Nenhum (function de leitura, publicada pelo Lovable) |
| B2 | RECRIAR preservando a homologação + truncar histórico + reaplicar bancada | 1 a 2 sessões, com ensaio em réplica local antes de tocar no workflow | Não (workflow) | Nenhum — o RECRIAR só lê a produção |

Riscos e como ficam cobertos:

- **Login na homologação.** Depende de conta superadmin utilizável lá. Quem
  for operar a bancada precisa estar em `HOMOLOGACAO_TESTADORES` (ou de conta
  criada à mão). Não é da bancada; é do RECRIAR.
- **Rodar bateria na produção.** Já é possível hoje pela tela do app; a bancada
  não amplia nem reduz isso, só torna visível. Cada bateria grava linhas em
  `qa_execucoes`/`qa_resultados` da produção e ocupa até 120 s de CPU do banco
  real. Ver decisão 6.1.
- **Roteamento no Pages.** Pasta nova `/qa/` com rota única; o `404.html` da
  raiz continua cuidando de teste e homologação. Um `grep` na esteira confirma
  que a pasta entrou no `dist`.
- **Produção mantém as tabelas `qa_*`.** Elas ficam (a trilha da bancada foi
  entregue lá de propósito, como prova do que foi entregue). A bancada
  independente não exige removê-las.

---

## 6. Decisões que ficam com o dono do produto

1. **Produção entra no seletor?** Proposta: entra, mas atrás de confirmação
   digitada ("PRODUCAO") antes de qualquer ação que escreva (rodar bateria,
   salvar agendamento, disparar Cypress — este último a `seed-e2e-user` já
   recusa por construção). Alternativa: começar sem produção e ligar depois.
2. **Editor de casos na tela: continua?** Proposta: continua, com o
   "Exportar catálogo" (B1) e a regra de que edição não exportada é rascunho.
   Alternativa mais rígida: editor somente leitura fora do ambiente de teste.
3. **Endereço da bancada.** Proposta: `https://ustudy123.github.io/youreyesnovo/qa/`
   (mesma esteira, sem custo). Alternativa: domínio próprio depois.
4. **Voltar a recriar a homologação.** Só depois de B1 + B2 prontos e ensaiados
   em réplica; aí a decisão 09/2026 é revista em `docs/AMBIENTES.md`.
5. **Central de QA (4.3).** Proposta: não agora.

---

## 7. Achados de passagem (fora do escopo, mas vale registrar)

- `qa_e2e_disparar_esteira()` tem repositório padrão desatualizado
  (`ustudy123/seguramente-0aed4f79`); só não dói porque `app_config` pode
  sobrescrever (`github_dispatch_repo`).
- A `ai-qa-agent` loga com uma conta real fixa no código, escreve em tabelas de
  cliente, não tem trava de ambiente e está publicada nos três projetos. A tela
  que a chamava já foi desligada (aba sem botão). Deve sair.
- `qa_cobertura_e2e` só tem política de leitura (e para `admin`, não
  superadmin): a ponte caso↔`it()` só entra por migration/script ou chave de
  serviço — coerente com "o repositório manda", e a bancada deve respeitar.
- Nenhuma coluna distingue caso semeado por migration de caso editado na tela
  (motivo da coluna `origem` em B1).

---

*Nada deste documento foi aplicado. Os três ambientes seguem exatamente como
estavam; a produção está intacta.*
