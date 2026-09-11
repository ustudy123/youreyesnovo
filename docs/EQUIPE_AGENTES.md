# Equipe de Agentes GTM — YourEyes

Materializa o *Plano Estratégico YourEyes — Go-to-Market operado por Agentes Claude* (Set/2026)
como **subagentes do Claude Code**, versionados em `.claude/agents/`. Cada agente tem papel,
critérios inegociáveis e o *quality gate* embutido — os "prompts-mãe salvos" do plano.

## Como a equipe opera — o padrão trio

Cada área do negócio é um **trio**, e nada vai ao cliente/público sem os três passos + o "ok" humano:

```
Planejamento  →  Execução  →  Conferência  →  [ GATE HUMANO: Leiridiani ]
"o quê/p/quem"   "pronto p/uso"  "está correto,
                                  seguro, no padrão?"
```

A **Leiridiani (co-fundadora)** é a orquestradora e o ponto de aprovação humana. Autonomia total
só onde o risco é baixo; **contrato, preço e promessa comercial sempre passam por ela**.

## Núcleo do Sprint 1 (montado — 10 agentes)

| Área | Planejamento | Execução | Conferência |
|---|---|---|---|
| **Orquestrador (macro)** | `orquestrador-gtm` — recebe o objetivo da semana, quebra em briefs e distribui | | |
| **Marketing** | `marketing-planejamento` | `marketing-execucao` | `marketing-conferencia` |
| **Comercial** | `comercial-planejamento` | `comercial-execucao` | `comercial-conferencia` |
| **Customer Success** | `cs-planejamento` | `cs-execucao` | `cs-conferencia` |

## Como usar

- **No dia a dia:** peça pela função. Ex.: *"aciona o `orquestrador-gtm`: objetivo da semana é ativar cross-sell do módulo de Jornada na base"* — ele distribui para os trios.
- **Direto num trio:** *"`marketing-planejamento`, brief para uma campanha de expansão na base"* → depois `marketing-execucao` → depois `marketing-conferencia`.
- **O gate humano é você:** os agentes de Conferência marcam sempre o que **exige decisão humana** (preço, contrato, promessa, verba de mídia). Nada disso é publicado sem o seu "ok".

## Princípios inegociáveis (herdados do plano — valem para todos os agentes)

1. **Construir para o exit.** Métrica-rainha: **NRR > 100%**. Tudo medido em MRR/ARR, NRR, churn, CAC payback, LTV/CAC.
2. **Posicionamento amplo.** "A plataforma que deixa a empresa mais madura, da norma à evidência." A **NR-1/psicossocial é porta de entrada, nunca o teto**.
3. **Ordem dos motores.** Base instalada (1.100+ empresas) → canais/parceiros → conteúdo/inbound → tráfego pago (bisturi). Nunca acender mídia paga antes de o funil converter.
4. **Humano-no-loop** em contrato, preço e promessa.
5. **LGPD em tudo.** Dados de saúde são sensíveis (art. 11); nenhum dado pessoal real circula em briefs, peças, exemplos ou relatórios. Rastreabilidade em toda ação.
6. **Consolidar o comercial no CRM** (fora dos celulares pessoais) — o histórico é ativo da empresa.

## Próximos sprints (a montar quando você aprovar)

- **Sprint 2 — canais e inbound:** trios de **Canais/Parceiros** e reforço de **Conteúdo/Inbound**.
- **Sprint 3 — escala e instrumentação:** trios de **Onboarding/Implantação**, **RevOps/Financeiro** (o painel do dono: MRR, NRR, churn, CAC), **Produto/Requisitos**, **Jurídico/LGPD** e **Dados & Inteligência**.

> A equipe completa do plano tem 9 áreas. Começamos pelo núcleo do Sprint 1 (Marketing, Comercial, CS)
> porque é onde o retorno sobre capital é maior e mais rápido: expansão da base instalada.
