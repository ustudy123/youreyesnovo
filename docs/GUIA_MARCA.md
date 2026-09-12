# Guia de Marca — YourEyes (v1)

Fonte única da identidade da marca. Definido uma vez; a equipe de agentes e a
Central de Comando GTM injetam este guia automaticamente em toda peça (texto e
arte) — ninguém precisa repetir cores/tom/posicionamento a cada pedido.

> **Nome.** A marca pública é **YourEyes**. **"Seguramente" é o nome antigo**
> (o projeto nasceu como Seguramente e foi renomeado) — **não usar em peças novas**.
> A produção ainda roda em `seguramente.lovable.app`, mas a comunicação é YourEyes.

> **Referência viva:** o feed real **@youreyes.oficial** é a fonte de estilo
> (voz + arte). Em dúvida, olhar o feed.

## Essência
- **Assinatura/campanha:** *Enxergue o que sua gestão ainda não vê.*
- **O que é:** *inteligência organizacional aplicada à gestão preventiva* — uma
  plataforma que conecta **Pessoas · Saúde · Segurança · Gestão** num só lugar.
- **Ideia central do conteúdo:** do **dado** ao **contexto** — um dado pode estar
  certo, mas sem contexto leva à conclusão errada; a YourEyes ajuda a enxergar o
  *porquê*, não só o *quê*.
- **Posicionamento (amplo):** a plataforma que deixa a empresa mais madura —
  governança contínua do trabalho humano (RH, DP, SST, jornada, folha,
  documentos, cultura, metas), da norma à evidência. **NR-1/psicossocial é porta
  de entrada, nunca o teto. Nunca estreitar à NR-1.**
- **Público:** decisores de RH/DP/SST em pequenas e médias empresas.

## Mascote
- **Íris** — uma **robô branca e azul**, simpática e competente. O nome remete à
  íris do olho (**YourEyes** = visão, clareza). Já aparece no feed.
- **Uso:** boa em redes sociais e materiais leves; em peças institucionais é
  opcional. Não forçar.

## Estilo de conteúdo (o feed é a referência)
- **Formato-assinatura:** carrossel narrativo — abre com um **dado isolado** que
  induz a conclusão apressada → hipóteses → falta de **contexto** → a YourEyes
  ajuda a enxergar o porquê (ex.: *"Ele chegou atrasado 4 vezes"*).
- **Arte:** fundo navy/azul em degradê, foto cinematográfica de trabalho **ou**
  mockup do sistema; título branco encorpado com palavras-chave em **azul/laranja**;
  laranja como destaque/carimbo de tensão.
- **A arte final de qualidade sai do processo de vocês (designer/templates), não
  do gerador de IA "do zero"** — que não atinge esse nível. Papel dos agentes:
  **copy + roteiro de carrossel + briefing de arte** e preencher os **templates**
  (autofill).

## Cores
| Papel | Hex |
|---|---|
| Azul (principal) | `#0A6DBC` |
| Verde | `#22A06B` |
| Laranja (destaque/CTA) | `#FF8C00` |
| Navy (fundo escuro/autoridade) | `#0E2038` |
| Texto | `#15242F` |
| Fundo claro | `#F5F8F9` |

(São as cores do próprio sistema — `src/index.css` — em HSL.)

## Tipografia
- **Inter** (ou uma sem serifa limpa e profissional). Títulos com peso, corpo
  legível. Sem serifa decorativa.

## Tom de voz
Profissional, claro e **humano**. Confiança **sem juridiquês**. Direto ao ponto.
Sem exagero. **Nunca prometer conformidade ou resultado automático.**

## Pilares de mensagem
1. **Maturidade organizacional** — sair do improviso para a gestão com evidência.
2. **Conformidade sem sofrimento** — atende a lei/ISOs com experiência simples.
3. **Um dado, uma vez, para tudo** — integração real entre RH, DP e SST.
4. **Da norma à evidência** — cada ação gera rastreabilidade e documento.

## O que evitar
- Estreitar a promessa à NR-1.
- "Você já usa / já começou" (o mercado é frio; ninguém conhece a marca ainda).
- Nome antigo "Seguramente" em peça nova.
- Dado pessoal real (CPF, nome, atestado); promessa de resultado/conformidade automática.

## Como isto é reutilizado (para nunca repetir)
1. **Canva Brand Kit "YourEyes"** = o visual (cores, fontes, logo, Íris). Toda
   arte gerada com esse Brand Kit já sai on-brand. **`brand_kit_id = kAHU8P-jQu4`**
   (URL: https://www.canva.com/brand/kAHU8P-jQu4). É o padrão embutido no botão
   "Gerar no Canva" da Central de Comando GTM.
2. **Este guia** = o resto (nome, tom, público, pilares, do/don't). Injetado
   automaticamente pela Central de Comando GTM (constante `BRAND_PROMPT`) e pelos
   subagentes em `.claude/agents/`.
