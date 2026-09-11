# MarketYE — entrega da fundação (MVP conexão/lead)

Módulo que substitui a antiga "Rede de Parceiros" (`/marketplace`) pelo
**MarketYE**, o marketplace de serviços do YourEyes, seguindo o Documento de
Requisitos v2.0 (11/09/2026). Esta página resume o que entrou, o que ficou de
fora de propósito e como conferir no ambiente de teste.

## O que entrou

**Nomenclatura (0.5).** Botão do cabeçalho, menu, busca global, perfis de
acesso e painel de QA passam a dizer **MarketYE**. "Parceiros" fica só para o
Programa de Parceiros (canal de vendas).

**Banco (migrations 20260911220000 / 221000 / 222000; script de entrega
`docs/script_marketye_fundacao.sql`).**

| Requisito | Como ficou |
|---|---|
| Especialista global, sem tenant (RN-001/002) | `marketplace_profissionais` continua a tabela; `tenant_id` vira só "empresa de origem do cadastro". Novo cadastro nasce `pendente`. |
| Escrita sensível só por função (RN-021 / CA-013) | Guardas por trigger: status, selo, reputação, documento e consentimento não mudam por UPDATE direto; anúncio só publica por `marketye_anuncio_publicar`. |
| Contato mascarado (RN-020) | Leitura direta de e-mail/telefone/CPF pelo papel `authenticated` retirada; mensagens do lead mascaram telefone/e-mail/link até a empresa liberar; contato sai por `marketye_lead_contato`. |
| Leads (RF-012) | `marketplace_leads` + `marketplace_lead_mensagens`; funções abrir/mensagem/liberar/status; recusar não pesa (RN-030). |
| Avaliação verificada e bidirecional (RN-004/022) | `marketye_avaliar('lead' ou 'contratacao', ...)` só com lead ganho ou contratação concluída, dentro da janela; 1 por lado; direito de resposta; limite por par (anti-gaming). |
| Reputação em dois eixos (RN-005) | `marketplace_reputacao`: saúde recente (90 d) + nível (novo → bronze → prata → ouro → top) com requisitos simultâneos, aviso e amortecedor antes do ajuste (RN-009/010/029). |
| Relevância personalizada (RF-008) | `marketye_buscar(jsonb)`: fit por obrigação legal × reputação × saúde × proximidade × exploração (boost de novato) × preço × destaque, com pesos em `marketplace_config`; piso de nota rebaixa e o destaque não passa por cima (RN-006/007). |
| Busca nunca vazia (RN-023) | Relaxamento progressivo (raio → cidade → modalidade → UF → nota) e categorias adjacentes; busca rala vira demanda latente. |
| Vagas de demanda (6.3 / RN-034) | `marketye_vagas_demanda()` só devolve células com ≥ 5 empresas distintas. |
| Parametrização versionada (RN-016) | `marketplace_config` (pesos, piso, níveis, proteção ao novato, célula mínima, mascaramento, janela de avaliação, versões dos termos, localização, destaque). |
| LGPD do não-usuário (RN-018/019) | `marketplace_consentimentos` por versão; exportação e exclusão (anonimiza e retém transações). |
| Devido processo (RN-032/033) | `marketplace_contestacoes`: canal único; só superadmin decide, com trilha; relatório de transparência. |
| Trilha de autonomia (RN-031) | `marketplace_autonomia_eventos` por trigger em preço/política/horário. |
| Léxico (RN-028) | Ocorrência, reflexo na visibilidade, ajuste de nível. Auditado pela rotina MKY-007. |
| Taxonomia (7.1) | Categorias com slug, árvore, aliases, obrigação legal, exige registro, jurisdição. 20 subcategorias do beachhead SST/RH. |
| Localização (0.3) | `pais`/`moeda`/`jurisdicao` em especialista, anúncio, categorias e config. Nada de Brasil fixado em código; i18n ainda não. |

**Telas.**

- `/marketplace` — vitrine MarketYE (busca em linguagem natural com IA, filtros, ordenação por relevância, cards com selo "dados verificados", nível, saúde recente, Patrocinado rotulado, busca vazia com Avise-me); Minhas conversas (chat com mascaramento, liberar contato, serviço combinado, avaliar, Analisar com IA, Criar ação no Plano de Ação, arquivar proposta no módulo Documentos); Contratações e Pacotes (legado). Para superadmin: Moderação, Denúncias, Contestações, Destaques, Parâmetros, Liquidez.
- `/marketye` — página pública de captação com "vagas de demanda" anonimizadas.
- `/marketye/cadastro` — cadastro sem acesso ao sistema (Edge Function `marketye-cadastro`) ou com conta existente (papéis sobrepostos com o Programa de Parceiros).
- `/marketye/entrar` e `/marketye/portal` — portal restrito do especialista: anúncios com geração por IA (`ai-marketye`), conversas, reputação e nível, perfil, cupons, termos/contestação/dados.
- `EncontrarEspecialistaLink` — componente para alertas: leva à vitrine já filtrada pela obrigação (`/marketplace?obrigacao=NR-1&origem=...`).

**QA.** Casos MKY-001 a MKY-013 (api, com rotinas) e MKY-020 a MKY-022 (e2e,
`cypress/e2e/marketye.cy.ts`); módulo `rede-parceiros` renomeado para MarketYE
na Documentação de testes. Casos PARC-001/002/004/024 atualizados.

## O que NÃO entrou (de propósito)

- **Pagamento intra-plataforma, split, escrow, take rate, NF da taxa** —
  GATE jurídico pré-build (seção 14). Nenhuma linha de código.
- **Cobrança do destaque pago** — só o registro do período e o reflexo no
  ranking; o dinheiro fica para a onda com meio de pagamento.
- **Verificação por OCR / antecedentes** — a moderação continua humana com
  os documentos enviados.
- **Notificações por e-mail/WhatsApp de lead** — o portal mostra "aguardando
  sua resposta"; disparo automático é onda seguinte.
- **i18n / moeda estrangeira ativa** — só o modelo de dados está preparado.
- **Redação final dos instrumentos (3.4)** e **prazos de retenção** —
  exigem advogado; as versões vigentes são placeholders (`2026-09-v1`).

## Como conferir no ambiente de teste

1. Site de teste: https://ustudy123.github.io/youreyesnovo/teste/
2. Logado como empresa: botão **MarketYE** no cabeçalho → vitrine; filtre
   "Segurança do Trabalho" (aparece "Especialista Staging (QA)"); busque
   "xyz" (aviso de oferta insuficiente + Avise-me); abra uma conversa.
3. Sem login: `/marketye` (página pública) → "Quero me cadastrar".
4. Superadmin: abas Moderação, Contestações, Parâmetros, Liquidez.
5. SQL Editor do projeto de TESTE: `SELECT * FROM public.qa_rodar_bateria('manual','rede-parceiros');`
   e depois `SELECT codigo, situacao, obtido FROM public.qa_execucao_itens ... ` (ou a
   conferência final do `docs/script_marketye_fundacao.sql`).

A produção segue intacta: nada aqui toca o projeto de produção.
