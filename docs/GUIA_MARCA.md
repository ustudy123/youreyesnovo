# Guia de Marca — YourEyes (v1)

Fonte única da identidade da marca. Definido uma vez; a equipe de agentes e a
Central de Comando GTM injetam este guia automaticamente em toda peça (texto e
arte) — ninguém precisa repetir cores/tom/posicionamento a cada pedido.

> **Nome.** A marca pública é **YourEyes**. **"Seguramente" é o nome antigo**
> (o projeto nasceu como Seguramente e foi renomeado) — **não usar em peças novas**.
> A produção ainda roda em `seguramente.lovable.app`, mas a comunicação é YourEyes.

## Essência
- **Assinatura:** *Da norma à evidência.*
- **Posicionamento (amplo):** a plataforma que deixa a empresa mais madura —
  governança contínua do trabalho humano (RH, DP, SST, jornada, folha,
  documentos, cultura, metas), da norma à evidência. **NR-1/psicossocial é porta
  de entrada, nunca o teto. Nunca estreitar à NR-1.**
- **Público:** decisores de RH/DP/SST em pequenas e médias empresas. **Mercado
  frio** — ainda não conhecem a YourEyes; tom de apresentação e prova de valor,
  nunca de continuidade.

## Mascote
- **Íris** — uma **robô** assistente, simpática e competente. O nome remete à
  íris do olho (**YourEyes** = visão, clareza).
- **Uso:** boa em redes sociais e materiais leves; em peças institucionais é
  opcional. Não forçar a presença dela.
- **Ativo:** para a Íris aparecer nas artes do Canva, o desenho dela precisa
  estar disponível como asset no Canva (Brand Kit ou upload). *(pendente: subir
  o arquivo da Íris ao Brand Kit YourEyes.)*

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
