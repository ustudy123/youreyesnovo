-- =====================================================================
-- SCRIPT DE ENTREGA · MARKETYE · FUNDAÇÃO DO MARKETPLACE DE SERVIÇOS
-- (antiga "Rede de Parceiros"): entidade global do especialista, leads com
-- contato mascarado, avaliação bidirecional verificada, reputação em dois
-- eixos e níveis, relevância personalizada parametrizada, demanda latente,
-- consentimento LGPD, contestação com decisão humana, trilha de autonomia,
-- painel de liquidez e QA (MKY-001 a MKY-013).
--
-- Cole no SQL Editor do projeto. Roda em UMA transação; pode ser executado
-- mais de uma vez (colunas IF NOT EXISTS, políticas recriadas, funções
-- CREATE OR REPLACE, seeds com ON CONFLICT). É o mesmo conteúdo das
-- migrations 20260911220000, 20260911221000 e 20260911222000 (a de
-- mobiliário da ilha de teste NÃO entra: é dado fictício do ambiente de teste).
--
-- O QUE MUDA EM DADO EXISTENTE (sem apagar nada): serviços ativos ganham
-- status 'publicado'; categorias ganham slug; novos cadastros nascem
-- 'pendente' (o default era 'ativo'); a leitura direta de e-mail/telefone/
-- CPF do especialista pelo papel authenticated é retirada (sai pelo lead
-- liberado); a política "Admins manage all professionals" (admin de qualquer
-- empresa gerenciando todos os prestadores) é substituída por superadmin;
-- a inserção direta de avaliação é substituída pela função marketye_avaliar;
-- a função buscar_profissionais_proximos (devolvia e-mail/telefone) é
-- removida — a tela usa a variante _publico.
--
-- Não altera nem apaga cadastro, contratação, avaliação ou denúncia
-- existente. Não há UPDATE/DELETE de dado de cliente: por isso não há
-- tabela de backup (regra da casa: só para script que altera dado).
--
-- Pré-requisito: scripts do Programa de Parceiros já aplicados
-- (script_parceiros_onda1.sql em diante) — a FK parceiro_id é opcional e
-- se adapta se a tabela parceiros não existir.
-- =====================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) FUNDAÇÃO: colunas, tabelas novas, RLS e guardas
-- ---------------------------------------------------------------------
-- =====================================================================
-- MARKETYE · FUNDAÇÃO DO MARKETPLACE DE SERVIÇOS (antiga "Rede de Parceiros")
--
-- POR QUE ESTA MIGRATION EXISTE
-- O módulo /marketplace já tinha profissionais, serviços, contratações,
-- avaliações e denúncias, mas nascia com quatro lacunas apontadas no
-- documento de requisitos do MarketYE (v2.0, 11/09/2026):
--   1. Todo dado sensível do prestador (status, selo, nota) mudava por
--      UPDATE direto de tabela exposta — a mesma classe de brecha da
--      assinatura por anônimo. Agora há uma GUARDA por trigger: essas
--      colunas só mudam por função do sistema (RN-021 / CA-013).
--   2. E-mail, telefone e CPF/CNPJ do prestador eram lidos por qualquer
--      usuário autenticado de qualquer empresa. Agora a leitura direta fica
--      restrita às colunas públicas; o contato sai só pelo lead liberado
--      (RN-020, LGPD).
--   3. nota_media / total_avaliacoes nunca eram recalculados por ninguém, e
--      qualquer membro de empresa podia avaliar sem contratação. Agora a
--      avaliação passa pela função marketye_avaliar (só transação
--      verificada, RN-004) e a reputação é apurada em dois eixos (RN-005).
--   4. Não existia lead, parametrização versionada, consentimento LGPD do
--      não-usuário, contestação com pessoa decidindo, trilha de autonomia
--      nem demanda latente — tudo isso entra aqui.
--
-- LÉXICO (RN-028): nada aqui se chama infração, punição, sanção ou demoção.
-- Os nomes são ocorrência, reflexo na visibilidade e ajuste de nível. Nenhum
-- ajuste bloqueia o prestador de trabalhar ou de definir preço (RN-029).
--
-- ESCOPO DESTA ONDA (MVP conexão/lead): nada de pagamento intra-plataforma,
-- split ou escrow — é GATE jurídico pré-build (seção 14). O destaque pago
-- entra só como camada rotulada e parametrizada; a cobrança fica para depois.
--
-- Idempotente: colunas com IF NOT EXISTS, políticas recriadas, funções
-- CREATE OR REPLACE, seeds com ON CONFLICT. Rodar de novo não duplica.
-- Não altera nem apaga dado existente: só cria estrutura e preenche colunas
-- novas com o valor neutro (slug das categorias, status 'publicado' nos
-- serviços que já estavam ativos).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0) Utilitários
-- ---------------------------------------------------------------------

-- Só dígitos (CPF/CNPJ/telefone).
CREATE OR REPLACE FUNCTION public.marketye_so_digitos(p_texto text)
RETURNS text LANGUAGE sql IMMUTABLE AS $marketye_so_digitos$
  SELECT regexp_replace(COALESCE(p_texto, ''), '\D', '', 'g');
$marketye_so_digitos$;

-- Dígito verificador do CNPJ (o CPF já tem public.cpf_valido).
CREATE OR REPLACE FUNCTION public.marketye_cnpj_valido(p_cnpj text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $marketye_cnpj_valido$
DECLARE d text := public.marketye_so_digitos(p_cnpj); s int; i int; p1 int[] := ARRAY[5,4,3,2,9,8,7,6,5,4,3,2]; p2 int[] := ARRAY[6,5,4,3,2,9,8,7,6,5,4,3,2]; dv1 int; dv2 int;
BEGIN
  IF length(d) <> 14 OR d ~ '^(\d)\1{13}$' THEN RETURN false; END IF;
  s := 0; FOR i IN 1..12 LOOP s := s + substr(d, i, 1)::int * p1[i]; END LOOP;
  dv1 := CASE WHEN s % 11 < 2 THEN 0 ELSE 11 - (s % 11) END;
  s := 0; FOR i IN 1..13 LOOP s := s + substr(d, i, 1)::int * p2[i]; END LOOP;
  dv2 := CASE WHEN s % 11 < 2 THEN 0 ELSE 11 - (s % 11) END;
  RETURN substr(d, 13, 1)::int = dv1 AND substr(d, 14, 1)::int = dv2;
END $marketye_cnpj_valido$;

-- CPF ou CNPJ válido (aceita formatado ou só dígitos).
CREATE OR REPLACE FUNCTION public.marketye_documento_valido(p_doc text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $marketye_documento_valido$
  SELECT CASE length(public.marketye_so_digitos(p_doc))
           WHEN 11 THEN public.cpf_valido(public.marketye_so_digitos(p_doc))
           WHEN 14 THEN public.marketye_cnpj_valido(p_doc)
           ELSE false END;
$marketye_documento_valido$;

-- O texto traz contato direto (telefone, e-mail, link, "me chama no zap")?
CREATE OR REPLACE FUNCTION public.marketye_texto_tem_contato(p_texto text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $marketye_texto_tem_contato$
  SELECT COALESCE(p_texto, '') ~* '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}'
      OR COALESCE(p_texto, '') ~* '(https?://|www\.)[^\s]+'
      OR COALESCE(p_texto, '') ~ '(\(?\d{2}\)?[\s.-]?)?\d{4,5}[\s.-]?\d{4}'
      OR COALESCE(p_texto, '') ~* '\m(whats(app)?|zap|telegram|me liga|meu (fone|celular|telefone))\M';
$marketye_texto_tem_contato$;

-- Mascara contato direto até a liberação (RN-020).
CREATE OR REPLACE FUNCTION public.marketye_mascarar_contato(p_texto text)
RETURNS text LANGUAGE sql IMMUTABLE AS $marketye_mascarar_contato$
  SELECT regexp_replace(
           regexp_replace(
             regexp_replace(COALESCE(p_texto, ''), '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[contato oculto até a liberação]', 'g'),
             '(https?://|www\.)[^\s]+', '[link oculto até a liberação]', 'g'),
           '(\(?\d{2}\)?[\s.-]?)?\d{4,5}[\s.-]?\d{4}', '[telefone oculto até a liberação]', 'g');
$marketye_mascarar_contato$;

-- "Esta escrita veio por função do sistema?" Dentro das funções marketye_*
-- (SECURITY DEFINER, dono postgres) o usuário corrente é o dono; pela API o
-- usuário corrente é 'authenticated'. Sem marcador de sessão de propósito:
-- um marcador transação-local vazaria para escritas diretas feitas na mesma
-- transação.
CREATE OR REPLACE FUNCTION public.marketye_via_funcao()
RETURNS boolean LANGUAGE sql STABLE AS $marketye_via_funcao$
  SELECT current_user IN ('postgres', 'supabase_admin', 'service_role');
$marketye_via_funcao$;
DROP FUNCTION IF EXISTS public.marketye_marcar_via_funcao();

-- Quem sou eu como especialista (NULL se a conta não tem cadastro).
CREATE OR REPLACE FUNCTION public.marketye_meu_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_meu_id$
  SELECT id FROM public.marketplace_profissionais WHERE user_id = auth.uid() ORDER BY created_at LIMIT 1;
$marketye_meu_id$;
GRANT EXECUTE ON FUNCTION public.marketye_meu_id() TO authenticated;

-- ---------------------------------------------------------------------
-- 1) Parametrização versionada (RN-016 / CA-015)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marketplace_config (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chave       text NOT NULL,
  versao      int  NOT NULL DEFAULT 1,
  valor       jsonb NOT NULL,
  descricao   text,
  vigente     boolean NOT NULL DEFAULT true,
  jurisdicao  text NOT NULL DEFAULT 'BR',
  criado_por  uuid,
  criado_em   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (chave, jurisdicao, versao)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_config_vigente ON public.marketplace_config (chave, jurisdicao) WHERE vigente;
ALTER TABLE public.marketplace_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.marketplace_config FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.marketplace_config TO authenticated;
DROP POLICY IF EXISTS marketplace_config_leitura ON public.marketplace_config;
CREATE POLICY marketplace_config_leitura ON public.marketplace_config FOR SELECT TO authenticated USING (true);

CREATE OR REPLACE FUNCTION public.marketye_config(p_chave text, p_jurisdicao text DEFAULT 'BR')
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_config$
  SELECT valor FROM public.marketplace_config WHERE chave = p_chave AND jurisdicao = p_jurisdicao AND vigente LIMIT 1;
$marketye_config$;
GRANT EXECUTE ON FUNCTION public.marketye_config(text, text) TO anon, authenticated;

-- Nova versão de um parâmetro (superadmin). A anterior deixa de ser vigente,
-- mas fica no histórico — é config, não deploy.
CREATE OR REPLACE FUNCTION public.marketye_config_salvar(p_chave text, p_valor jsonb, p_descricao text DEFAULT NULL, p_jurisdicao text DEFAULT 'BR')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_config_salvar$
DECLARE v_versao int; v_id uuid;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_chave IS NULL OR p_valor IS NULL THEN RAISE EXCEPTION 'Informe chave e valor'; END IF;
  UPDATE public.marketplace_config SET vigente = false WHERE chave = p_chave AND jurisdicao = p_jurisdicao AND vigente;
  SELECT COALESCE(max(versao), 0) + 1 INTO v_versao FROM public.marketplace_config WHERE chave = p_chave AND jurisdicao = p_jurisdicao;
  INSERT INTO public.marketplace_config (chave, versao, valor, descricao, vigente, jurisdicao, criado_por)
  VALUES (p_chave, v_versao, p_valor, p_descricao, true, p_jurisdicao, auth.uid()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'chave', p_chave, 'versao', v_versao);
END $marketye_config_salvar$;
GRANT EXECUTE ON FUNCTION public.marketye_config_salvar(text, jsonb, text, text) TO authenticated;

INSERT INTO public.marketplace_config (chave, valor, descricao) VALUES
  ('relevancia_pesos', '{"fit":0.25,"reputacao":0.20,"saude":0.20,"proximidade":0.15,"exploracao":0.10,"preco":0.05,"destaque":0.05}',
   'Pesos do motor de relevância (seção 10.2). Somam 1. Destaque pago é camada aditiva com teto.'),
  ('piso_nota', '{"nota":3.5,"minimo_avaliacoes":3}',
   'Abaixo deste piso (com pelo menos N avaliações) a visibilidade orgânica é rebaixada e o destaque não se aplica (RN-006/RN-007).'),
  ('protecao_novato', '{"dias":30,"ate_avaliacoes":3}',
   'Boost de exploração para prestador novo: por N dias ou até acumular N avaliações (RN-008).'),
  ('niveis', '{"ordem":["novo","bronze","prata","ouro","top"],"requisitos":{"bronze":{"servicos":3,"clientes_unicos":2,"media":4.0,"taxa_resposta":0.6,"ocorrencias":0},"prata":{"servicos":10,"clientes_unicos":5,"media":4.5,"taxa_resposta":0.8,"ocorrencias":0},"ouro":{"servicos":25,"clientes_unicos":10,"media":4.7,"taxa_resposta":0.9,"ocorrencias":0},"top":{"servicos":50,"clientes_unicos":20,"media":4.8,"taxa_resposta":0.95,"ocorrencias":0}},"amortecedor_dias":14}',
   'Requisitos simultâneos por nível (RN-009) e amortecedor: aviso + período de recuperação antes do ajuste de nível (RN-010). Só afeta visibilidade (RN-029).'),
  ('saude_recente', '{"janela_dias":90,"verde":75,"amarelo":50}',
   'Eixo A da reputação: janela móvel e cortes de cor do termômetro de saúde recente (RN-005).'),
  ('demanda_latente', '{"piso_celula":5,"janela_dias":30}',
   'Célula mínima das "vagas de demanda": contagens abaixo do piso não aparecem (RN-034 / CA-021).'),
  ('mascaramento_contato', '{"ate":"contato_qualificado"}',
   'Contatos mascarados até o cliente liberar o contato no lead (RN-020). Só incentivo, sem penalização por sinal de saída.'),
  ('janela_avaliacao_dias', '{"dias":14}',
   'Prazo para avaliar após a conclusão ou o lead ganho (11.3).'),
  ('termos_versoes', '{"termos_especialista":"2026-09-v1","privacidade_nao_usuario":"2026-09-v1","codigo_etica":"2026-02-v1","termos_cliente":"2026-09-v1"}',
   'Versões vigentes dos instrumentos (3.4). Redação final exige advogado; o consentimento é registrado por versão (RN-018).'),
  ('localizacao', '{"pais":"BR","moeda":"BRL","idioma":"pt-BR"}',
   'Padrões de país/moeda/idioma. Preparação para expansão América do Sul: nada de Brasil fixado em código (0.3).'),
  ('destaque', '{"teto_slots_por_categoria":2,"exige_acima_do_piso":true}',
   'Destaque pago: camada rotulada "Patrocinado", com teto por categoria e piso de nota (8.2).')
ON CONFLICT (chave, jurisdicao, versao) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2) Taxonomia: árvore parametrizável, versionada por jurisdição (7.1)
-- ---------------------------------------------------------------------
ALTER TABLE public.marketplace_categorias
  ADD COLUMN IF NOT EXISTS slug              text,
  ADD COLUMN IF NOT EXISTS pai_id            uuid REFERENCES public.marketplace_categorias(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS aliases           text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS obrigacao_legal   text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS exige_registro    boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS conselhos_aceitos text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS jurisdicao        text NOT NULL DEFAULT 'BR',
  ADD COLUMN IF NOT EXISTS versao            int NOT NULL DEFAULT 1;

UPDATE public.marketplace_categorias SET slug = CASE nome
  WHEN 'Segurança do Trabalho' THEN 'seguranca-trabalho'
  WHEN 'Ergonomia' THEN 'ergonomia'
  WHEN 'Saúde Ocupacional' THEN 'saude-ocupacional'
  WHEN 'Saúde Mental' THEN 'saude-mental'
  WHEN 'Fisioterapia' THEN 'fisioterapia'
  WHEN 'Treinamentos' THEN 'treinamentos'
  WHEN 'Jurídico Trabalhista' THEN 'juridico-trabalhista'
  WHEN 'RH Estratégico' THEN 'rh-estrategico'
  ELSE lower(regexp_replace(translate(nome, 'áàâãéêíóôõúçÁÀÂÃÉÊÍÓÔÕÚÇ', 'aaaaeeiooouc' || 'AAAAEEIOOOUC'), '[^A-Za-z0-9]+', '-', 'g')) END
WHERE slug IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_categorias_slug ON public.marketplace_categorias (jurisdicao, slug) WHERE slug IS NOT NULL;

-- Raízes que faltam (a árvore antiga só tinha 8 raízes) + subcategorias do
-- beachhead SST/RH (2.3). Cada subcategoria já nasce amarrada à obrigação
-- legal que atende (7.3) e diz se exige registro profissional (RN-011 —
-- a lista fechada ainda passa por advogado).
INSERT INTO public.marketplace_categorias (nome, descricao, icone, ordem, ativo, slug, obrigacao_legal, exige_registro, conselhos_aceitos, aliases) VALUES
  ('Contábil e Fiscal', 'Contabilidade, folha, eSocial e obrigações fiscais', 'Calculator', 20, true, 'contabil-fiscal', '{}', false, '{CRC}', '{contador,contabilidade,esocial}'),
  ('Tecnologia', 'TI, sistemas e segurança da informação', 'Cpu', 21, true, 'tecnologia', '{}', false, '{}', '{ti,software,sistemas}')
ON CONFLICT DO NOTHING;

WITH raiz AS (SELECT id, slug FROM public.marketplace_categorias WHERE pai_id IS NULL AND slug IS NOT NULL)
INSERT INTO public.marketplace_categorias (nome, descricao, icone, ordem, ativo, slug, pai_id, obrigacao_legal, exige_registro, conselhos_aceitos, aliases)
SELECT v.nome, v.descricao, v.icone, v.ordem, true, v.slug, r.id, v.obrigacao, v.exige_registro, v.conselhos, v.aliases
FROM (VALUES
  ('seguranca-trabalho', 'PGR — Programa de Gerenciamento de Riscos', 'Elaboração e revisão do PGR e inventário de riscos', 'ShieldCheck', 1, 'pgr', '{NR-1}'::text[], true, '{CREA,MTE}'::text[], '{pgr,gerenciamento de riscos,inventario de riscos,ppra}'::text[]),
  ('seguranca-trabalho', 'LTCAT, insalubridade e periculosidade', 'Laudos técnicos das condições ambientais e adicionais', 'FileText', 2, 'ltcat-laudos', '{NR-15,NR-16}', true, '{CREA,CRM}', '{ltcat,laudo,insalubridade,periculosidade,ruido}'),
  ('seguranca-trabalho', 'Técnico de Segurança do Trabalho', 'Atuação in loco, inspeções, DDS e ordens de serviço', 'HardHat', 3, 'tecnico-seguranca', '{NR-1,NR-4}', true, '{MTE}', '{tst,tecnico de seguranca,sesmt}'),
  ('seguranca-trabalho', 'CIPA e Brigada de Incêndio', 'Implantação e treinamento de CIPA e brigada', 'Flame', 4, 'cipa-brigada', '{NR-5,NR-23}', false, '{}', '{cipa,brigada,incendio}'),
  ('seguranca-trabalho', 'EPI e gestão de riscos operacionais', 'Especificação de EPI, matriz de riscos, APR', 'Shield', 5, 'epi-riscos', '{NR-6}', false, '{}', '{epi,apr,matriz de risco}'),
  ('saude-ocupacional', 'Médico do Trabalho / PCMSO', 'Coordenação do PCMSO e exames ocupacionais', 'Stethoscope', 1, 'pcmso', '{NR-7}', true, '{CRM}', '{pcmso,medico do trabalho,aso,exame admissional}'),
  ('saude-ocupacional', 'Exames complementares e audiometria', 'Audiometria, espirometria e exames complementares', 'Activity', 2, 'exames-complementares', '{NR-7}', true, '{CRM,CFFa}', '{audiometria,espirometria,exames}'),
  ('saude-ocupacional', 'Enfermagem do trabalho', 'Enfermagem ocupacional e campanhas de saúde', 'HeartPulse', 3, 'enfermagem-trabalho', '{NR-7}', true, '{COREN}', '{enfermagem,enfermeiro do trabalho}'),
  ('ergonomia', 'AEP e AET — Análise Ergonômica', 'Avaliação ergonômica preliminar e do trabalho', 'Ruler', 1, 'aep-aet', '{NR-17}', true, '{CREFITO,CREA,CRM}', '{aep,aet,laudo ergonomico,ergonomista}'),
  ('ergonomia', 'Ginástica laboral', 'Programas de ginástica laboral e pausas ativas', 'Dumbbell', 2, 'ginastica-laboral', '{NR-17}', true, '{CREF,CREFITO}', '{ginastica laboral,pausa ativa}'),
  ('saude-mental', 'Gestão de riscos psicossociais (NR-1)', 'Diagnóstico, plano e acompanhamento dos fatores psicossociais', 'Brain', 1, 'psicossocial-nr1', '{NR-1}', true, '{CRP}', '{psicossocial,nr-1,riscos psicossociais,burnout}'),
  ('saude-mental', 'Psicologia organizacional', 'Clima, escuta e apoio psicológico organizacional', 'Users', 2, 'psicologia-organizacional', '{NR-1}', true, '{CRP}', '{psicologo,clima,escuta}'),
  ('treinamentos', 'Treinamentos NR (10, 12, 33, 35)', 'Capacitações obrigatórias por norma regulamentadora', 'GraduationCap', 1, 'treinamentos-nr', '{NR-10,NR-12,NR-33,NR-35}', false, '{}', '{nr-10,nr-35,nr-33,nr-12,treinamento,capacitacao}'),
  ('treinamentos', 'Primeiros socorros e emergências', 'Treinamento de primeiros socorros e plano de emergência', 'Siren', 2, 'primeiros-socorros', '{NR-7}', false, '{}', '{primeiros socorros,emergencia}'),
  ('juridico-trabalhista', 'Consultoria trabalhista e sindical', 'Assessoria trabalhista, acordos e convenções', 'Scale', 1, 'consultoria-trabalhista', '{}', true, '{OAB}', '{advogado,trabalhista,sindicato,convencao}'),
  ('rh-estrategico', 'Recrutamento e seleção', 'Atração, triagem e seleção de pessoas', 'UserSearch', 1, 'recrutamento', '{}', false, '{}', '{recrutamento,selecao,vagas}'),
  ('rh-estrategico', 'Treinamento e desenvolvimento', 'Trilhas, liderança e desenvolvimento de equipes', 'BookOpen', 2, 'treinamento-desenvolvimento', '{}', false, '{}', '{t&d,desenvolvimento,lideranca}'),
  ('rh-estrategico', 'Cargos, salários e departamento pessoal', 'Estrutura de cargos, folha e rotinas de DP', 'Briefcase', 3, 'cargos-salarios-dp', '{}', false, '{}', '{cargos,salarios,dp,departamento pessoal}'),
  ('fisioterapia', 'Fisioterapia ocupacional', 'Reabilitação e prevenção de lesões no trabalho', 'Accessibility', 1, 'fisioterapia-ocupacional', '{NR-17}', true, '{CREFITO}', '{fisioterapia,ler,dort,reabilitacao}'),
  ('contabil-fiscal', 'eSocial e obrigações acessórias', 'Eventos de SST no eSocial (S-2210, S-2220, S-2240)', 'FileSpreadsheet', 1, 'esocial-sst', '{eSocial}', false, '{CRC}', '{esocial,s-2240,s-2220,s-2210}')
) AS v(raiz_slug, nome, descricao, icone, ordem, slug, obrigacao, exige_registro, conselhos, aliases)
JOIN raiz r ON r.slug = v.raiz_slug
WHERE NOT EXISTS (SELECT 1 FROM public.marketplace_categorias c WHERE c.slug = v.slug);

-- ---------------------------------------------------------------------
-- 3) Especialista: colunas novas (entidade global, sem tenant)
-- ---------------------------------------------------------------------
ALTER TABLE public.marketplace_profissionais
  ADD COLUMN IF NOT EXISTS tipo_pessoa           text NOT NULL DEFAULT 'pf' CHECK (tipo_pessoa IN ('pf','pj')),
  ADD COLUMN IF NOT EXISTS pais                  text NOT NULL DEFAULT 'BR',
  ADD COLUMN IF NOT EXISTS moeda                 text NOT NULL DEFAULT 'BRL',
  ADD COLUMN IF NOT EXISTS atende_remoto         boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS raio_atendimento_km   int NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS disponibilidade       jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS politicas             text,
  ADD COLUMN IF NOT EXISTS site_url              text,
  ADD COLUMN IF NOT EXISTS video_url             text,
  ADD COLUMN IF NOT EXISTS moderacao_resultado   text CHECK (moderacao_resultado IN ('aprovado','rejeitado')),
  ADD COLUMN IF NOT EXISTS moderacao_motivo      text,
  ADD COLUMN IF NOT EXISTS moderado_por          uuid,
  ADD COLUMN IF NOT EXISTS moderado_em           timestamptz,
  ADD COLUMN IF NOT EXISTS excluido_em           timestamptz,
  ADD COLUMN IF NOT EXISTS consentimento_versao  text,
  ADD COLUMN IF NOT EXISTS consentimento_em      timestamptz,
  ADD COLUMN IF NOT EXISTS origem_cadastro       text NOT NULL DEFAULT 'sistema',
  ADD COLUMN IF NOT EXISTS parceiro_id           uuid;

-- Papéis sobrepostos (0.6): a mesma pessoa pode ser parceiro do canal.
DO $fk_parceiro$
BEGIN
  IF to_regclass('public.parceiros') IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM pg_constraint WHERE conname = 'marketplace_profissionais_parceiro_id_fkey') THEN
    ALTER TABLE public.marketplace_profissionais
      ADD CONSTRAINT marketplace_profissionais_parceiro_id_fkey FOREIGN KEY (parceiro_id) REFERENCES public.parceiros(id) ON DELETE SET NULL;
  END IF;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'FK parceiro_id: %', SQLERRM;
END $fk_parceiro$;

-- Novo cadastro nasce pendente (o default tinha virado 'ativo' em 05/2026).
ALTER TABLE public.marketplace_profissionais ALTER COLUMN status SET DEFAULT 'pendente';

-- Um CPF/CNPJ = uma conta de especialista (RN-012). Só para documentos
-- válidos e cadastros vivos; registros antigos sem documento não colidem.
CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_prof_documento_unico
  ON public.marketplace_profissionais (public.marketye_so_digitos(cpf_cnpj))
  WHERE cpf_cnpj IS NOT NULL AND length(public.marketye_so_digitos(cpf_cnpj)) IN (11, 14) AND excluido_em IS NULL;

-- ---------------------------------------------------------------------
-- 4) Anúncio (marketplace_servicos): colunas novas
-- ---------------------------------------------------------------------
ALTER TABLE public.marketplace_servicos
  ADD COLUMN IF NOT EXISTS status               text NOT NULL DEFAULT 'rascunho' CHECK (status IN ('rascunho','publicado','pausado','removido')),
  ADD COLUMN IF NOT EXISTS publicado_em         timestamptz,
  ADD COLUMN IF NOT EXISTS tipo_preco           text NOT NULL DEFAULT 'sob_orcamento' CHECK (tipo_preco IN ('hora','visita','pacote','mensal','sob_orcamento')),
  ADD COLUMN IF NOT EXISTS preco_minimo         numeric(10,2),
  ADD COLUMN IF NOT EXISTS preco_maximo         numeric(10,2),
  ADD COLUMN IF NOT EXISTS moeda                text NOT NULL DEFAULT 'BRL',
  ADD COLUMN IF NOT EXISTS pais                 text NOT NULL DEFAULT 'BR',
  ADD COLUMN IF NOT EXISTS tags                 text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS obrigacao_legal      text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS area_atendimento     jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS prazo_tipico         text,
  ADD COLUMN IF NOT EXISTS politica_cancelamento text,
  ADD COLUMN IF NOT EXISTS midia                jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS gerado_por_ia        boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS promocao_percentual  numeric(5,2),
  ADD COLUMN IF NOT EXISTS promocao_inicio      date,
  ADD COLUMN IF NOT EXISTS promocao_fim         date,
  ADD COLUMN IF NOT EXISTS promocao_descricao   text,
  ADD COLUMN IF NOT EXISTS impressoes           int NOT NULL DEFAULT 0;

-- Serviços que já estavam ativos continuam na vitrine: viram 'publicado'.
UPDATE public.marketplace_servicos SET status = 'publicado', publicado_em = COALESCE(publicado_em, created_at)
WHERE ativo AND status = 'rascunho' AND created_at < now() - interval '1 minute';
UPDATE public.marketplace_servicos SET tipo_preco = 'visita' WHERE preco_referencia IS NOT NULL AND tipo_preco = 'sob_orcamento';

CREATE INDEX IF NOT EXISTS idx_marketplace_servicos_vitrine ON public.marketplace_servicos (status, ativo, categoria_id) WHERE status = 'publicado' AND ativo;

-- ---------------------------------------------------------------------
-- 5) Avaliação bidirecional atrelada a transação verificada (RN-004/RN-022)
-- ---------------------------------------------------------------------
ALTER TABLE public.marketplace_avaliacoes
  ADD COLUMN IF NOT EXISTS lead_id               uuid,
  ADD COLUMN IF NOT EXISTS direcao               text NOT NULL DEFAULT 'cliente_para_especialista' CHECK (direcao IN ('cliente_para_especialista','especialista_para_cliente')),
  ADD COLUMN IF NOT EXISTS criterios             jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS resposta              text,
  ADD COLUMN IF NOT EXISTS respondido_em         timestamptz,
  ADD COLUMN IF NOT EXISTS moderada              boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS moderacao_motivo      text;
ALTER TABLE public.marketplace_avaliacoes ALTER COLUMN contratacao_id DROP NOT NULL;
ALTER TABLE public.marketplace_avaliacoes ALTER COLUMN servico_id DROP NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_avaliacoes_contratacao_direcao ON public.marketplace_avaliacoes (contratacao_id, direcao) WHERE contratacao_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_avaliacoes_lead_direcao ON public.marketplace_avaliacoes (lead_id, direcao) WHERE lead_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- 6) Leads (RF-012): o elo entre demanda e oferta, com contato mascarado
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marketplace_leads (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  empresa_id           uuid,
  profissional_id      uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  servico_id           uuid REFERENCES public.marketplace_servicos(id) ON DELETE SET NULL,
  criado_por           uuid,
  solicitante_nome     text,
  canal                text NOT NULL DEFAULT 'chat',
  status               text NOT NULL DEFAULT 'novo' CHECK (status IN ('novo','respondido','qualificado','ganho','perdido','encerrado')),
  contato_liberado     boolean NOT NULL DEFAULT false,
  contato_liberado_em  timestamptz,
  primeira_resposta_em timestamptz,
  ultima_mensagem_em   timestamptz,
  ganho_em             timestamptz,
  origem_modulo        text,
  origem_id            uuid,
  obrigacao_legal      text,
  cupom_codigo         text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_marketplace_leads_tenant ON public.marketplace_leads (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_marketplace_leads_prof ON public.marketplace_leads (profissional_id, created_at DESC);
DROP TRIGGER IF EXISTS update_marketplace_leads_updated_at ON public.marketplace_leads;
CREATE TRIGGER update_marketplace_leads_updated_at BEFORE UPDATE ON public.marketplace_leads FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.marketplace_lead_mensagens (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id        uuid NOT NULL REFERENCES public.marketplace_leads(id) ON DELETE CASCADE,
  autor_tipo     text NOT NULL CHECK (autor_tipo IN ('cliente','especialista','sistema')),
  autor_id       uuid,
  texto          text NOT NULL,
  texto_original text,
  mascarada      boolean NOT NULL DEFAULT false,
  sinal_saida    boolean NOT NULL DEFAULT false,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_marketplace_lead_mensagens_lead ON public.marketplace_lead_mensagens (lead_id, created_at);

CREATE TABLE IF NOT EXISTS public.marketplace_lead_documentos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id      uuid NOT NULL REFERENCES public.marketplace_leads(id) ON DELETE CASCADE,
  documento_id uuid NOT NULL,
  tipo         text NOT NULL DEFAULT 'proposta',
  created_at   timestamptz NOT NULL DEFAULT now()
);

DO $fk_avaliacao_lead$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'marketplace_avaliacoes_lead_id_fkey') THEN
    ALTER TABLE public.marketplace_avaliacoes ADD CONSTRAINT marketplace_avaliacoes_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.marketplace_leads(id) ON DELETE CASCADE;
  END IF;
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'FK avaliacoes.lead_id: %', SQLERRM;
END $fk_avaliacao_lead$;

-- ---------------------------------------------------------------------
-- 7) Reputação em dois eixos (RF-009) — uma linha por especialista
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marketplace_reputacao (
  profissional_id          uuid PRIMARY KEY REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  saude_score              numeric(5,2) NOT NULL DEFAULT 60,
  saude_cor                text NOT NULL DEFAULT 'cinza' CHECK (saude_cor IN ('verde','amarelo','vermelho','cinza')),
  media_90d                numeric(3,2),
  avaliacoes_90d           int NOT NULL DEFAULT 0,
  clientes_unicos_total    int NOT NULL DEFAULT 0,
  clientes_unicos_90d      int NOT NULL DEFAULT 0,
  taxa_resposta_90d        numeric(4,3),
  tempo_resposta_mediano_min int,
  taxa_cancelamento_90d    numeric(4,3),
  ocorrencias_90d          int NOT NULL DEFAULT 0,
  servicos_concluidos_total int NOT NULL DEFAULT 0,
  nivel                    text NOT NULL DEFAULT 'novo',
  nivel_desde              timestamptz NOT NULL DEFAULT now(),
  nivel_aviso_em           timestamptz,
  nivel_aviso_motivo       text,
  abaixo_piso              boolean NOT NULL DEFAULT false,
  protegido_ate            timestamptz,
  calculado_em             timestamptz NOT NULL DEFAULT now()
);

-- Ocorrências (léxico não-disciplinar): registro factual com reflexo na
-- visibilidade; nunca condição para continuar operando.
CREATE TABLE IF NOT EXISTS public.marketplace_ocorrencias (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id      uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  tipo                 text NOT NULL,
  descricao            text,
  origem_tipo          text,
  origem_id            uuid,
  reflexo_visibilidade boolean NOT NULL DEFAULT true,
  registrado_por       uuid,
  created_at           timestamptz NOT NULL DEFAULT now()
);

-- Destaque pago: camada aditiva, rotulada, com teto (8.2). A cobrança em si
-- não está nesta onda — só o registro e o reflexo no ranking.
CREATE TABLE IF NOT EXISTS public.marketplace_destaques (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  servico_id      uuid REFERENCES public.marketplace_servicos(id) ON DELETE CASCADE,
  tipo            text NOT NULL DEFAULT 'categoria' CHECK (tipo IN ('categoria','regiao','topo')),
  categoria_id    uuid REFERENCES public.marketplace_categorias(id) ON DELETE SET NULL,
  uf              text,
  inicio          date NOT NULL DEFAULT CURRENT_DATE,
  fim             date NOT NULL,
  valor           numeric(10,2),
  moeda           text NOT NULL DEFAULT 'BRL',
  ativo           boolean NOT NULL DEFAULT true,
  criado_por      uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.marketplace_cupons (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id     uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  codigo              text NOT NULL,
  descricao           text,
  desconto_percentual numeric(5,2) NOT NULL CHECK (desconto_percentual > 0 AND desconto_percentual <= 100),
  validade            date,
  limite_uso          int,
  usos                int NOT NULL DEFAULT 0,
  ativo               boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (profissional_id, codigo)
);

-- ---------------------------------------------------------------------
-- 8) LGPD, devido processo e trilha de autonomia
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marketplace_consentimentos (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  tipo            text NOT NULL,
  versao          text NOT NULL,
  aceito_em       timestamptz NOT NULL DEFAULT now(),
  ip              text,
  user_agent      text,
  origem          text
);
CREATE INDEX IF NOT EXISTS idx_marketplace_consentimentos_prof ON public.marketplace_consentimentos (profissional_id, tipo, aceito_em DESC);

-- Canal único de contestação (RN-032/RN-033): a decisão é sempre de uma
-- pessoa (human-in-the-loop), com trilha de evidência.
CREATE TABLE IF NOT EXISTS public.marketplace_contestacoes (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  decisao_tipo    text NOT NULL CHECK (decisao_tipo IN ('rejeicao_cadastro','suspensao','remocao_anuncio','ajuste_nivel','reflexo_visibilidade','avaliacao','outro')),
  referencia_id   uuid,
  motivo          text NOT NULL,
  evidencias      jsonb NOT NULL DEFAULT '[]'::jsonb,
  status          text NOT NULL DEFAULT 'aberta' CHECK (status IN ('aberta','em_analise','deferida','indeferida')),
  resposta        text,
  analisado_por   uuid,
  analisado_em    timestamptz,
  trilha          jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Trilha de autonomia (RN-031): toda definição de preço/horário/política é
-- do prestador e fica registrada como evento.
CREATE TABLE IF NOT EXISTS public.marketplace_autonomia_eventos (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id uuid NOT NULL REFERENCES public.marketplace_profissionais(id) ON DELETE CASCADE,
  tipo            text NOT NULL,
  referencia_id   uuid,
  anterior        jsonb,
  novo            jsonb,
  autor_id        uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_marketplace_autonomia_prof ON public.marketplace_autonomia_eventos (profissional_id, created_at DESC);

-- Demanda latente (busca sem oferta suficiente): uma linha por
-- (empresa × categoria × UF × dia); a página pública só vê agregados com
-- célula mínima (RN-034).
CREATE TABLE IF NOT EXISTS public.marketplace_demanda_latente (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL,
  categoria_id  uuid REFERENCES public.marketplace_categorias(id) ON DELETE CASCADE,
  uf            text,
  cidade        text,
  dia           date NOT NULL DEFAULT CURRENT_DATE,
  termos        text,
  resultados    int NOT NULL DEFAULT 0,
  avisar        boolean NOT NULL DEFAULT false,
  avisar_email  text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, categoria_id, uf, dia)
);

-- ---------------------------------------------------------------------
-- 9) RLS das tabelas novas: leitura por política, escrita por função
-- ---------------------------------------------------------------------
ALTER TABLE public.marketplace_leads              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_lead_mensagens     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_lead_documentos    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_reputacao          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_ocorrencias        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_destaques          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_cupons             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_consentimentos     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_contestacoes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_autonomia_eventos  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketplace_demanda_latente    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.marketplace_leads, public.marketplace_lead_mensagens, public.marketplace_lead_documentos,
  public.marketplace_reputacao, public.marketplace_ocorrencias, public.marketplace_destaques, public.marketplace_cupons,
  public.marketplace_consentimentos, public.marketplace_contestacoes, public.marketplace_autonomia_eventos,
  public.marketplace_demanda_latente FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.marketplace_leads, public.marketplace_lead_mensagens, public.marketplace_lead_documentos,
  public.marketplace_reputacao, public.marketplace_ocorrencias, public.marketplace_destaques, public.marketplace_cupons,
  public.marketplace_consentimentos, public.marketplace_contestacoes, public.marketplace_autonomia_eventos,
  public.marketplace_demanda_latente TO authenticated;

DROP POLICY IF EXISTS marketplace_leads_leitura ON public.marketplace_leads;
CREATE POLICY marketplace_leads_leitura ON public.marketplace_leads FOR SELECT TO authenticated
  USING (tenant_id = public.get_user_tenant_id() OR profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_lead_mensagens_leitura ON public.marketplace_lead_mensagens;
CREATE POLICY marketplace_lead_mensagens_leitura ON public.marketplace_lead_mensagens FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.marketplace_leads l WHERE l.id = lead_id
                   AND (l.tenant_id = public.get_user_tenant_id() OR l.profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()))));

DROP POLICY IF EXISTS marketplace_lead_documentos_leitura ON public.marketplace_lead_documentos;
CREATE POLICY marketplace_lead_documentos_leitura ON public.marketplace_lead_documentos FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.marketplace_leads l WHERE l.id = lead_id
                   AND (l.tenant_id = public.get_user_tenant_id() OR l.profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()))));

DROP POLICY IF EXISTS marketplace_reputacao_leitura ON public.marketplace_reputacao;
CREATE POLICY marketplace_reputacao_leitura ON public.marketplace_reputacao FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS marketplace_ocorrencias_leitura ON public.marketplace_ocorrencias;
CREATE POLICY marketplace_ocorrencias_leitura ON public.marketplace_ocorrencias FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_destaques_leitura ON public.marketplace_destaques;
CREATE POLICY marketplace_destaques_leitura ON public.marketplace_destaques FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_cupons_leitura ON public.marketplace_cupons;
CREATE POLICY marketplace_cupons_leitura ON public.marketplace_cupons FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_consentimentos_leitura ON public.marketplace_consentimentos;
CREATE POLICY marketplace_consentimentos_leitura ON public.marketplace_consentimentos FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_contestacoes_leitura ON public.marketplace_contestacoes;
CREATE POLICY marketplace_contestacoes_leitura ON public.marketplace_contestacoes FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_autonomia_leitura ON public.marketplace_autonomia_eventos;
CREATE POLICY marketplace_autonomia_leitura ON public.marketplace_autonomia_eventos FOR SELECT TO authenticated
  USING (profissional_id = public.marketye_meu_id() OR public.is_superadmin(auth.uid()));

DROP POLICY IF EXISTS marketplace_demanda_latente_leitura ON public.marketplace_demanda_latente;
CREATE POLICY marketplace_demanda_latente_leitura ON public.marketplace_demanda_latente FOR SELECT TO authenticated
  USING (public.is_superadmin(auth.uid()));

-- ---------------------------------------------------------------------
-- 10) RLS das tabelas antigas: fecha as brechas herdadas
-- ---------------------------------------------------------------------
-- 10.1 "Admins manage all professionals" usava has_minimum_role('admin'),
--      que NÃO é por empresa: o admin de qualquer empresa gerenciava todos
--      os prestadores. Agora só superadmin (a moderação é da casa).
DROP POLICY IF EXISTS "Admins manage all professionals" ON public.marketplace_profissionais;
DROP POLICY IF EXISTS marketplace_profissionais_superadmin ON public.marketplace_profissionais;
CREATE POLICY marketplace_profissionais_superadmin ON public.marketplace_profissionais FOR ALL TO authenticated
  USING (public.is_superadmin(auth.uid())) WITH CHECK (public.is_superadmin(auth.uid()));

-- 10.2 Leitura direta só das colunas públicas: e-mail, telefone, CPF/CNPJ,
--      user_id e tenant_id saem da leitura por tabela. O próprio prestador e
--      a moderação leem o perfil completo por função (marketye_meu_portal,
--      marketye_moderacao_fila); o cliente recebe o contato pelo lead
--      liberado (marketye_lead_contato).
REVOKE SELECT ON public.marketplace_profissionais FROM authenticated;
GRANT SELECT (id, nome_completo, foto_url, bio, formacao_academica, registro_profissional, conselho, uf_registro, registro_validade,
              certificacoes, especialidades, areas_atuacao, modalidades_atendimento, cidade, estado, status, plano, selo_verificado,
              nota_media, total_avaliacoes, total_servicos_executados, tem_atestado_capacidade, latitude, longitude, created_at, updated_at,
              tipo_pessoa, pais, moeda, atende_remoto, raio_atendimento_km, disponibilidade, politicas, site_url, video_url,
              excluido_em, consentimento_versao, consentimento_em, origem_cadastro, moderacao_resultado, aceite_codigo_etica)
  ON public.marketplace_profissionais TO authenticated;

-- 10.3 Avaliação: só por função (transação verificada). A leitura continua
--      pública (é reputação), mas sem expor quem avaliou.
DROP POLICY IF EXISTS "Tenant members can create reviews" ON public.marketplace_avaliacoes;
REVOKE SELECT ON public.marketplace_avaliacoes FROM authenticated;
GRANT SELECT (id, contratacao_id, profissional_id, servico_id, pontualidade, clareza, aderencia_escopo, profissionalismo, nota_geral,
              comentario, created_at, lead_id, direcao, criterios, resposta, respondido_em, moderada)
  ON public.marketplace_avaliacoes TO authenticated;

-- 10.4 Vitrine só mostra anúncio publicado (rascunho e pausado ficam com o dono).
DROP POLICY IF EXISTS "Public can view active services" ON public.marketplace_servicos;
CREATE POLICY "Public can view active services" ON public.marketplace_servicos FOR SELECT TO anon, authenticated
  USING (ativo = true AND status = 'publicado');

-- 10.5 A antiga busca por proximidade devolvia e-mail e telefone; some.
DROP FUNCTION IF EXISTS public.buscar_profissionais_proximos(double precision, double precision, double precision);

-- ---------------------------------------------------------------------
-- 11) Guardas (RN-021 / CA-013): dado sensível só muda por função
-- ---------------------------------------------------------------------
-- As guardas NÃO são SECURITY DEFINER de propósito: rodam como quem escreve.
-- Escrita direta pela API chega como 'authenticated' (guarda ativa); escrita
-- de dentro das funções marketye_* chega como o dono delas (postgres) e passa.
CREATE OR REPLACE FUNCTION public.marketye_guarda_profissional()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $marketye_guarda_profissional$
BEGIN
  IF public.marketye_via_funcao() OR public.is_superadmin(auth.uid()) THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    -- Cadastro direto pela tabela nasce pendente, sem selo e sem reputação.
    NEW.status := 'pendente'; NEW.selo_verificado := false; NEW.nota_media := 0; NEW.total_avaliacoes := 0;
    NEW.total_servicos_executados := 0; NEW.plano := 'base'; NEW.moderacao_resultado := NULL; NEW.moderacao_motivo := NULL;
    NEW.moderado_por := NULL; NEW.moderado_em := NULL; NEW.excluido_em := NULL; NEW.tem_atestado_capacidade := false;
    NEW.user_id := auth.uid();
    RETURN NEW;
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status OR NEW.selo_verificado IS DISTINCT FROM OLD.selo_verificado
     OR NEW.nota_media IS DISTINCT FROM OLD.nota_media OR NEW.total_avaliacoes IS DISTINCT FROM OLD.total_avaliacoes
     OR NEW.total_servicos_executados IS DISTINCT FROM OLD.total_servicos_executados OR NEW.plano IS DISTINCT FROM OLD.plano
     OR NEW.moderacao_resultado IS DISTINCT FROM OLD.moderacao_resultado OR NEW.moderacao_motivo IS DISTINCT FROM OLD.moderacao_motivo
     OR NEW.moderado_por IS DISTINCT FROM OLD.moderado_por OR NEW.moderado_em IS DISTINCT FROM OLD.moderado_em
     OR NEW.excluido_em IS DISTINCT FROM OLD.excluido_em OR NEW.consentimento_versao IS DISTINCT FROM OLD.consentimento_versao
     OR NEW.consentimento_em IS DISTINCT FROM OLD.consentimento_em OR NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.cpf_cnpj IS DISTINCT FROM OLD.cpf_cnpj OR NEW.tem_atestado_capacidade IS DISTINCT FROM OLD.tem_atestado_capacidade
     OR NEW.parceiro_id IS DISTINCT FROM OLD.parceiro_id THEN
    RAISE EXCEPTION 'MarketYE: status, selo, reputação, documento e consentimento só mudam por função do sistema'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END $marketye_guarda_profissional$;
DROP TRIGGER IF EXISTS marketye_guarda_profissional ON public.marketplace_profissionais;
CREATE TRIGGER marketye_guarda_profissional BEFORE INSERT OR UPDATE ON public.marketplace_profissionais
  FOR EACH ROW EXECUTE FUNCTION public.marketye_guarda_profissional();

CREATE OR REPLACE FUNCTION public.marketye_guarda_anuncio()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $marketye_guarda_anuncio$
BEGIN
  IF public.marketye_via_funcao() OR public.is_superadmin(auth.uid()) THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.status := 'rascunho'; NEW.publicado_em := NULL; NEW.impressoes := 0;
    RETURN NEW;
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'publicado' THEN
    RAISE EXCEPTION 'MarketYE: a publicação do anúncio passa pela função marketye_anuncio_publicar' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NEW.impressoes IS DISTINCT FROM OLD.impressoes THEN NEW.impressoes := OLD.impressoes; END IF;
  RETURN NEW;
END $marketye_guarda_anuncio$;
DROP TRIGGER IF EXISTS marketye_guarda_anuncio ON public.marketplace_servicos;
CREATE TRIGGER marketye_guarda_anuncio BEFORE INSERT OR UPDATE ON public.marketplace_servicos
  FOR EACH ROW EXECUTE FUNCTION public.marketye_guarda_anuncio();

-- Trilha de autonomia (RN-031): preço, horário e política são do prestador.
CREATE OR REPLACE FUNCTION public.marketye_trilha_autonomia_anuncio()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_trilha_autonomia_anuncio$
DECLARE v_ant jsonb; v_novo jsonb;
BEGIN
  v_novo := jsonb_build_object('preco_referencia', NEW.preco_referencia, 'tipo_preco', NEW.tipo_preco, 'preco_minimo', NEW.preco_minimo,
                               'preco_maximo', NEW.preco_maximo, 'prazo_tipico', NEW.prazo_tipico, 'politica_cancelamento', NEW.politica_cancelamento,
                               'area_atendimento', NEW.area_atendimento, 'modalidade', NEW.modalidade::text);
  IF TG_OP = 'UPDATE' THEN
    v_ant := jsonb_build_object('preco_referencia', OLD.preco_referencia, 'tipo_preco', OLD.tipo_preco, 'preco_minimo', OLD.preco_minimo,
                                'preco_maximo', OLD.preco_maximo, 'prazo_tipico', OLD.prazo_tipico, 'politica_cancelamento', OLD.politica_cancelamento,
                                'area_atendimento', OLD.area_atendimento, 'modalidade', OLD.modalidade::text);
    IF v_ant = v_novo THEN RETURN NEW; END IF;
  END IF;
  INSERT INTO public.marketplace_autonomia_eventos (profissional_id, tipo, referencia_id, anterior, novo, autor_id)
  VALUES (NEW.profissional_id, 'anuncio_preco_politica', NEW.id, v_ant, v_novo, auth.uid());
  RETURN NEW;
END $marketye_trilha_autonomia_anuncio$;
DROP TRIGGER IF EXISTS marketye_trilha_autonomia_anuncio ON public.marketplace_servicos;
CREATE TRIGGER marketye_trilha_autonomia_anuncio AFTER INSERT OR UPDATE ON public.marketplace_servicos
  FOR EACH ROW EXECUTE FUNCTION public.marketye_trilha_autonomia_anuncio();

CREATE OR REPLACE FUNCTION public.marketye_trilha_autonomia_perfil()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_trilha_autonomia_perfil$
DECLARE v_ant jsonb; v_novo jsonb;
BEGIN
  v_novo := jsonb_build_object('modalidades', to_jsonb(NEW.modalidades_atendimento), 'atende_remoto', NEW.atende_remoto,
                               'raio_atendimento_km', NEW.raio_atendimento_km, 'disponibilidade', NEW.disponibilidade, 'politicas', NEW.politicas);
  v_ant  := jsonb_build_object('modalidades', to_jsonb(OLD.modalidades_atendimento), 'atende_remoto', OLD.atende_remoto,
                               'raio_atendimento_km', OLD.raio_atendimento_km, 'disponibilidade', OLD.disponibilidade, 'politicas', OLD.politicas);
  IF v_ant = v_novo THEN RETURN NEW; END IF;
  INSERT INTO public.marketplace_autonomia_eventos (profissional_id, tipo, referencia_id, anterior, novo, autor_id)
  VALUES (NEW.id, 'perfil_horario_politica', NEW.id, v_ant, v_novo, auth.uid());
  RETURN NEW;
END $marketye_trilha_autonomia_perfil$;
DROP TRIGGER IF EXISTS marketye_trilha_autonomia_perfil ON public.marketplace_profissionais;
CREATE TRIGGER marketye_trilha_autonomia_perfil AFTER UPDATE ON public.marketplace_profissionais
  FOR EACH ROW EXECUTE FUNCTION public.marketye_trilha_autonomia_perfil();

-- ---------------------------------------------------------------------
-- 2) FUNÇÕES DO MÓDULO
-- ---------------------------------------------------------------------
-- =====================================================================
-- MARKETYE · FUNÇÕES DO MÓDULO (segunda parte da fundação)
--
-- Doutrina do módulo (a mesma do Programa de Parceiros): leitura por
-- política, escrita por função SECURITY DEFINER. Nenhuma ação sensível do
-- prestador (cadastro, publicação, aceite de termos, avaliação, contato)
-- acontece por UPDATE direto de tabela exposta (RN-021).
--
-- Grupos: cadastro/consentimento · portal · anúncios · leads · avaliação e
-- reputação em dois eixos · busca com relevância personalizada · demanda
-- latente e vitrine pública · moderação, contestação e transparência ·
-- LGPD · painel de liquidez.
--
-- Idempotente: só CREATE OR REPLACE e GRANT.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) Cadastro e consentimento (RF-001, RN-001, RN-012, RN-018)
-- ---------------------------------------------------------------------
-- Núcleo do cadastro. Chamada pela função autenticada (abaixo) e pela Edge
-- Function marketye-cadastro (service_role), que antes cria a conta.
CREATE OR REPLACE FUNCTION public.marketye_cadastrar_especialista_para(p_user_id uuid, _dados jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_cadastrar_especialista_para$
DECLARE
  v_id uuid; v_nome text; v_email text; v_doc text; v_tipo text; v_versoes jsonb; v_modalidades text[];
  v_parceiro uuid; v_ip text; v_ua text; v_status text;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'Conta não identificada'; END IF;
  SELECT id, status::text INTO v_id, v_status FROM public.marketplace_profissionais WHERE user_id = p_user_id ORDER BY created_at LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN jsonb_build_object('id', v_id, 'status', v_status, 'ja_existia', true);
  END IF;

  v_nome  := trim(COALESCE(_dados->>'nome_completo', _dados->>'nome', ''));
  v_email := lower(trim(COALESCE(_dados->>'email', '')));
  v_doc   := public.marketye_so_digitos(_dados->>'cpf_cnpj');
  v_tipo  := CASE WHEN length(v_doc) = 14 THEN 'pj' WHEN COALESCE(_dados->>'tipo_pessoa', '') = 'pj' THEN 'pj' ELSE 'pf' END;
  IF length(v_nome) < 3 THEN RAISE EXCEPTION 'Informe o nome (mínimo 3 letras)'; END IF;
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RAISE EXCEPTION 'E-mail inválido'; END IF;
  IF v_doc = '' THEN RAISE EXCEPTION 'Informe o CPF ou CNPJ'; END IF;
  IF NOT public.marketye_documento_valido(v_doc) THEN RAISE EXCEPTION 'CPF/CNPJ inválido: confira os dígitos'; END IF;
  IF EXISTS (SELECT 1 FROM public.marketplace_profissionais WHERE public.marketye_so_digitos(cpf_cnpj) = v_doc AND excluido_em IS NULL) THEN
    RAISE EXCEPTION 'Este CPF/CNPJ já possui cadastro de especialista.';
  END IF;
  IF COALESCE((_dados->>'aceite_termos')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'É preciso aceitar os Termos do Especialista e a Política de Privacidade';
  END IF;

  v_modalidades := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_dados->'modalidades')), ARRAY['presencial']);
  IF array_length(v_modalidades, 1) IS NULL THEN v_modalidades := ARRAY['presencial']; END IF;
  v_versoes := COALESCE(public.marketye_config('termos_versoes'), '{}'::jsonb);
  v_ip := _dados->>'ip'; v_ua := _dados->>'user_agent';

  -- Papéis sobrepostos (0.6): quem já é parceiro do canal reaproveita a identidade.
  IF to_regclass('public.parceiro_usuarios') IS NOT NULL THEN
    SELECT parceiro_id INTO v_parceiro FROM public.parceiro_usuarios WHERE user_id = p_user_id LIMIT 1;
  END IF;

  INSERT INTO public.marketplace_profissionais
    (user_id, tenant_id, nome_completo, email, telefone, cpf_cnpj, tipo_pessoa, bio, formacao_academica, registro_profissional, conselho,
     uf_registro, registro_validade, certificacoes, especialidades, areas_atuacao, modalidades_atendimento, cidade, estado,
     latitude, longitude, atende_remoto, raio_atendimento_km, aceite_codigo_etica, aceite_codigo_etica_data,
     status, plano, selo_verificado, consentimento_versao, consentimento_em, origem_cadastro, parceiro_id, pais, moeda, site_url)
  VALUES
    (p_user_id, NULLIF(_dados->>'tenant_origem', '')::uuid, v_nome, v_email, NULLIF(trim(_dados->>'telefone'), ''), v_doc, v_tipo, NULLIF(_dados->>'bio', ''),
     NULLIF(_dados->>'formacao_academica', ''), NULLIF(_dados->>'registro_profissional', ''), NULLIF(_dados->>'conselho', ''),
     NULLIF(upper(_dados->>'uf_registro'), ''), NULLIF(_dados->>'registro_validade', '')::date,
     NULLIF(ARRAY(SELECT jsonb_array_elements_text(COALESCE(_dados->'certificacoes', '[]'::jsonb))), '{}'),
     NULLIF(ARRAY(SELECT jsonb_array_elements_text(COALESCE(_dados->'especialidades', '[]'::jsonb))), '{}'),
     NULLIF(ARRAY(SELECT jsonb_array_elements_text(COALESCE(_dados->'areas_atuacao', '[]'::jsonb))), '{}'),
     v_modalidades::public.marketplace_servico_modalidade[], NULLIF(_dados->>'cidade', ''), NULLIF(upper(_dados->>'estado'), ''),
     NULLIF(_dados->>'latitude', '')::double precision, NULLIF(_dados->>'longitude', '')::double precision,
     COALESCE((_dados->>'atende_remoto')::boolean, 'online' = ANY(v_modalidades) OR 'hibrido' = ANY(v_modalidades)),
     COALESCE(NULLIF(_dados->>'raio_atendimento_km', '')::int, 100), true, now(),
     'pendente', 'base', false, v_versoes->>'termos_especialista', now(), COALESCE(_dados->>'origem', 'sistema'), v_parceiro,
     COALESCE(NULLIF(_dados->>'pais', ''), COALESCE(public.marketye_config('localizacao')->>'pais', 'BR')),
     COALESCE(NULLIF(_dados->>'moeda', ''), COALESCE(public.marketye_config('localizacao')->>'moeda', 'BRL')),
     NULLIF(_dados->>'site_url', ''))
  RETURNING id INTO v_id;

  INSERT INTO public.marketplace_consentimentos (profissional_id, tipo, versao, ip, user_agent, origem)
  SELECT v_id, t.tipo, COALESCE(v_versoes->>t.tipo, 'sem-versao'), v_ip, v_ua, COALESCE(_dados->>'origem', 'sistema')
  FROM (VALUES ('termos_especialista'), ('privacidade_nao_usuario'), ('codigo_etica')) AS t(tipo);

  INSERT INTO public.marketplace_reputacao (profissional_id, protegido_ate)
  VALUES (v_id, now() + make_interval(days => COALESCE((public.marketye_config('protecao_novato')->>'dias')::int, 30)))
  ON CONFLICT (profissional_id) DO NOTHING;

  IF v_parceiro IS NOT NULL AND to_regclass('public.parceiros') IS NOT NULL THEN
    UPDATE public.parceiros SET marketplace_profissional_id = v_id WHERE id = v_parceiro AND marketplace_profissional_id IS NULL;
  END IF;

  INSERT INTO public.marketplace_audit_log (tenant_id, profissional_id, acao, descricao, dados, usuario_id)
  VALUES (NULLIF(_dados->>'tenant_origem', '')::uuid, v_id, 'especialista_cadastrado', 'Cadastro de especialista recebido para verificação',
          json_build_object('origem', COALESCE(_dados->>'origem', 'sistema'), 'tipo_pessoa', v_tipo), p_user_id);

  RETURN jsonb_build_object('id', v_id, 'status', 'pendente', 'ja_existia', false);
END $marketye_cadastrar_especialista_para$;
REVOKE ALL ON FUNCTION public.marketye_cadastrar_especialista_para(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marketye_cadastrar_especialista_para(uuid, jsonb) TO service_role;

-- Quem já tem conta (cliente, parceiro) se cadastra autenticado.
CREATE OR REPLACE FUNCTION public.marketye_cadastrar_especialista(_dados jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_cadastrar_especialista$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre na sua conta para se cadastrar'; END IF;
  -- tenant_origem só registra de qual empresa a pessoa se cadastrou (a entidade continua global).
  RETURN public.marketye_cadastrar_especialista_para(auth.uid(), COALESCE(_dados, '{}'::jsonb)
    || jsonb_build_object('origem', COALESCE(_dados->>'origem', 'sistema'), 'tenant_origem', public.get_user_tenant_id()));
END $marketye_cadastrar_especialista$;
GRANT EXECUTE ON FUNCTION public.marketye_cadastrar_especialista(jsonb) TO authenticated;

-- Aceite de termos versionado (RN-018), sempre por função.
CREATE OR REPLACE FUNCTION public.marketye_aceitar_termos(p_tipo text, p_versao text DEFAULT NULL, p_user_agent text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_aceitar_termos$
DECLARE v_id uuid := public.marketye_meu_id(); v_versao text;
BEGIN
  IF v_id IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF p_tipo NOT IN ('termos_especialista', 'privacidade_nao_usuario', 'codigo_etica') THEN RAISE EXCEPTION 'Tipo de termo desconhecido'; END IF;
  v_versao := COALESCE(p_versao, public.marketye_config('termos_versoes')->>p_tipo, 'sem-versao');
  INSERT INTO public.marketplace_consentimentos (profissional_id, tipo, versao, user_agent, origem) VALUES (v_id, p_tipo, v_versao, p_user_agent, 'portal');
  IF p_tipo = 'termos_especialista' THEN
    UPDATE public.marketplace_profissionais SET consentimento_versao = v_versao, consentimento_em = now() WHERE id = v_id;
  END IF;
  RETURN jsonb_build_object('tipo', p_tipo, 'versao', v_versao, 'aceito_em', now());
END $marketye_aceitar_termos$;
GRANT EXECUTE ON FUNCTION public.marketye_aceitar_termos(text, text, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 2) Reputação em dois eixos e níveis (RF-009, RF-011, RN-005/009/010/029)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_nivel_indice(p_nivel text)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_nivel_indice$
  SELECT COALESCE((SELECT (i - 1)::int FROM jsonb_array_elements_text(COALESCE(public.marketye_config('niveis')->'ordem', '["novo","bronze","prata","ouro","top"]'::jsonb)) WITH ORDINALITY AS o(nome, i) WHERE o.nome = p_nivel), 0);
$marketye_nivel_indice$;
GRANT EXECUTE ON FUNCTION public.marketye_nivel_indice(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.marketye_recalcular_reputacao(p_profissional_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_recalcular_reputacao$
DECLARE
  v_cfg_saude jsonb := COALESCE(public.marketye_config('saude_recente'), '{"janela_dias":90,"verde":75,"amarelo":50}'::jsonb);
  v_cfg_piso  jsonb := COALESCE(public.marketye_config('piso_nota'), '{"nota":3.5,"minimo_avaliacoes":3}'::jsonb);
  v_cfg_niv   jsonb := COALESCE(public.marketye_config('niveis'), '{}'::jsonb);
  v_cfg_nov   jsonb := COALESCE(public.marketye_config('protecao_novato'), '{"dias":30,"ate_avaliacoes":3}'::jsonb);
  v_janela interval; v_media_total numeric; v_total_aval int; v_media_90 numeric; v_aval_90 int;
  v_leads_90 int; v_resp_90 int; v_tempo_med int; v_canc_90 int; v_concl_90 int; v_ocorr_90 int;
  v_serv_total int; v_cli_total int; v_cli_90 int; v_taxa_resp numeric; v_taxa_canc numeric;
  v_score numeric; v_cor text; v_abaixo boolean; v_ordem text[]; v_nivel_atual text; v_alvo text; v_req jsonb; v_i int;
  v_aviso timestamptz; v_amort int; v_criado timestamptz; v_protegido timestamptz; v_resultado jsonb;
BEGIN
  IF p_profissional_id IS NULL THEN RETURN NULL; END IF;
  v_janela := make_interval(days => COALESCE((v_cfg_saude->>'janela_dias')::int, 90));
  SELECT created_at INTO v_criado FROM public.marketplace_profissionais WHERE id = p_profissional_id;
  IF v_criado IS NULL THEN RETURN NULL; END IF;

  SELECT round(avg(nota_geral)::numeric, 2), count(*) INTO v_media_total, v_total_aval
  FROM public.marketplace_avaliacoes WHERE profissional_id = p_profissional_id AND direcao = 'cliente_para_especialista' AND NOT moderada;
  SELECT round(avg(nota_geral)::numeric, 2), count(*) INTO v_media_90, v_aval_90
  FROM public.marketplace_avaliacoes WHERE profissional_id = p_profissional_id AND direcao = 'cliente_para_especialista' AND NOT moderada AND created_at >= now() - v_janela;

  SELECT count(*), count(*) FILTER (WHERE primeira_resposta_em IS NOT NULL),
         percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (primeira_resposta_em - created_at)) / 60) FILTER (WHERE primeira_resposta_em IS NOT NULL)
  INTO v_leads_90, v_resp_90, v_tempo_med
  FROM public.marketplace_leads WHERE profissional_id = p_profissional_id AND created_at >= now() - v_janela AND created_at < now() - interval '1 hour';

  SELECT count(*) FILTER (WHERE status = 'cancelada'), count(*) FILTER (WHERE status = 'concluida') INTO v_canc_90, v_concl_90
  FROM public.marketplace_contratacoes WHERE profissional_id = p_profissional_id AND created_at >= now() - v_janela;
  SELECT count(*) INTO v_ocorr_90 FROM public.marketplace_ocorrencias WHERE profissional_id = p_profissional_id AND reflexo_visibilidade AND created_at >= now() - v_janela;

  SELECT count(*) INTO v_serv_total FROM (
    SELECT id FROM public.marketplace_contratacoes WHERE profissional_id = p_profissional_id AND status = 'concluida'
    UNION ALL SELECT id FROM public.marketplace_leads WHERE profissional_id = p_profissional_id AND status = 'ganho') x;
  SELECT count(DISTINCT tenant_id) INTO v_cli_total FROM (
    SELECT tenant_id FROM public.marketplace_contratacoes WHERE profissional_id = p_profissional_id AND status = 'concluida'
    UNION ALL SELECT tenant_id FROM public.marketplace_leads WHERE profissional_id = p_profissional_id AND status = 'ganho') x;
  SELECT count(DISTINCT tenant_id) INTO v_cli_90 FROM (
    SELECT tenant_id FROM public.marketplace_contratacoes WHERE profissional_id = p_profissional_id AND status = 'concluida' AND created_at >= now() - v_janela
    UNION ALL SELECT tenant_id FROM public.marketplace_leads WHERE profissional_id = p_profissional_id AND status = 'ganho' AND created_at >= now() - v_janela) x;

  v_taxa_resp := CASE WHEN v_leads_90 > 0 THEN round(v_resp_90::numeric / v_leads_90, 3) END;
  v_taxa_canc := CASE WHEN (v_canc_90 + v_concl_90) > 0 THEN round(v_canc_90::numeric / (v_canc_90 + v_concl_90), 3) END;

  -- Eixo A — saúde recente: reflete o "agora"; sem dado recente fica cinza (neutro).
  IF v_aval_90 = 0 AND v_leads_90 = 0 AND (v_canc_90 + v_concl_90) = 0 AND v_ocorr_90 = 0 THEN
    v_score := 60; v_cor := 'cinza';
  ELSE
    v_score := 100 * (0.5 * COALESCE(v_media_90 / 5, 0.8) + 0.25 * COALESCE(v_taxa_resp, 0.8) + 0.25 * (1 - COALESCE(v_taxa_canc, 0)))
               - 10 * COALESCE(v_ocorr_90, 0);
    v_score := GREATEST(0, LEAST(100, round(v_score, 2)));
    v_cor := CASE WHEN v_score >= COALESCE((v_cfg_saude->>'verde')::numeric, 75) THEN 'verde'
                  WHEN v_score >= COALESCE((v_cfg_saude->>'amarelo')::numeric, 50) THEN 'amarelo' ELSE 'vermelho' END;
  END IF;
  v_abaixo := COALESCE(v_total_aval, 0) >= COALESCE((v_cfg_piso->>'minimo_avaliacoes')::int, 3)
              AND COALESCE(v_media_total, 5) < COALESCE((v_cfg_piso->>'nota')::numeric, 3.5);
  v_protegido := CASE WHEN COALESCE(v_total_aval, 0) < COALESCE((v_cfg_nov->>'ate_avaliacoes')::int, 3)
                      THEN v_criado + make_interval(days => COALESCE((v_cfg_nov->>'dias')::int, 30)) END;

  -- Eixo B — nível: só sobe com TODAS as métricas ao mesmo tempo (RN-009);
  -- só desce com aviso + amortecedor (RN-010); só afeta visibilidade (RN-029).
  INSERT INTO public.marketplace_reputacao (profissional_id) VALUES (p_profissional_id) ON CONFLICT (profissional_id) DO NOTHING;
  SELECT nivel, nivel_aviso_em INTO v_nivel_atual, v_aviso FROM public.marketplace_reputacao WHERE profissional_id = p_profissional_id;
  v_ordem := ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_cfg_niv->'ordem', '["novo","bronze","prata","ouro","top"]'::jsonb)));
  v_alvo := v_ordem[1];
  FOR v_i IN 2..COALESCE(array_length(v_ordem, 1), 1) LOOP
    v_req := v_cfg_niv->'requisitos'->v_ordem[v_i];
    IF v_req IS NULL THEN EXIT; END IF;
    IF v_serv_total >= COALESCE((v_req->>'servicos')::int, 0)
       AND v_cli_total >= COALESCE((v_req->>'clientes_unicos')::int, 0)
       AND COALESCE(v_media_total, 0) >= COALESCE((v_req->>'media')::numeric, 0)
       AND COALESCE(v_taxa_resp, 1) >= COALESCE((v_req->>'taxa_resposta')::numeric, 0)
       AND COALESCE(v_ocorr_90, 0) <= COALESCE((v_req->>'ocorrencias')::int, 0) THEN
      v_alvo := v_ordem[v_i];
    ELSE
      EXIT;
    END IF;
  END LOOP;
  v_amort := COALESCE((v_cfg_niv->>'amortecedor_dias')::int, 14);

  IF public.marketye_nivel_indice(v_alvo) > public.marketye_nivel_indice(v_nivel_atual) THEN
    UPDATE public.marketplace_reputacao SET nivel = v_alvo, nivel_desde = now(), nivel_aviso_em = NULL, nivel_aviso_motivo = NULL WHERE profissional_id = p_profissional_id;
    v_nivel_atual := v_alvo;
  ELSIF public.marketye_nivel_indice(v_alvo) < public.marketye_nivel_indice(v_nivel_atual) THEN
    IF v_aviso IS NULL THEN
      UPDATE public.marketplace_reputacao SET nivel_aviso_em = now(),
        nivel_aviso_motivo = format('As métricas atuais correspondem ao nível %s. Há %s dias para recuperar antes do ajuste de nível (só afeta a visibilidade).', v_alvo, v_amort)
      WHERE profissional_id = p_profissional_id;
    ELSIF v_aviso < now() - make_interval(days => v_amort) THEN
      UPDATE public.marketplace_reputacao SET nivel = v_alvo, nivel_desde = now(), nivel_aviso_em = NULL, nivel_aviso_motivo = NULL WHERE profissional_id = p_profissional_id;
      v_nivel_atual := v_alvo;
    END IF;
  ELSE
    UPDATE public.marketplace_reputacao SET nivel_aviso_em = NULL, nivel_aviso_motivo = NULL WHERE profissional_id = p_profissional_id AND nivel_aviso_em IS NOT NULL;
  END IF;

  UPDATE public.marketplace_reputacao SET
    saude_score = v_score, saude_cor = v_cor, media_90d = v_media_90, avaliacoes_90d = COALESCE(v_aval_90, 0),
    clientes_unicos_total = COALESCE(v_cli_total, 0), clientes_unicos_90d = COALESCE(v_cli_90, 0), taxa_resposta_90d = v_taxa_resp,
    tempo_resposta_mediano_min = v_tempo_med, taxa_cancelamento_90d = v_taxa_canc, ocorrencias_90d = COALESCE(v_ocorr_90, 0),
    servicos_concluidos_total = COALESCE(v_serv_total, 0), abaixo_piso = v_abaixo, protegido_ate = v_protegido, calculado_em = now()
  WHERE profissional_id = p_profissional_id;

  UPDATE public.marketplace_profissionais SET nota_media = COALESCE(v_media_total, 0), total_avaliacoes = COALESCE(v_total_aval, 0),
    total_servicos_executados = COALESCE(v_serv_total, 0) WHERE id = p_profissional_id;

  SELECT to_jsonb(r) INTO v_resultado FROM public.marketplace_reputacao r WHERE r.profissional_id = p_profissional_id;
  RETURN v_resultado;
END $marketye_recalcular_reputacao$;
REVOKE ALL ON FUNCTION public.marketye_recalcular_reputacao(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marketye_recalcular_reputacao(uuid) TO service_role;

-- ---------------------------------------------------------------------
-- 3) Portal do especialista (RF-004)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_meu_portal()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_meu_portal$
DECLARE v_id uuid := public.marketye_meu_id(); v_perfil jsonb; v_rep jsonb; v_versoes jsonb; v_niveis jsonb; v_nivel text; v_ordem text[]; v_prox text; v_i int;
BEGIN
  IF v_id IS NULL THEN RETURN NULL; END IF;
  SELECT to_jsonb(p) - 'user_id' INTO v_perfil FROM public.marketplace_profissionais p WHERE p.id = v_id;
  SELECT to_jsonb(r) INTO v_rep FROM public.marketplace_reputacao r WHERE r.profissional_id = v_id;
  v_versoes := COALESCE(public.marketye_config('termos_versoes'), '{}'::jsonb);
  v_niveis := COALESCE(public.marketye_config('niveis'), '{}'::jsonb);
  v_nivel := COALESCE(v_rep->>'nivel', 'novo');
  v_ordem := ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_niveis->'ordem', '["novo","bronze","prata","ouro","top"]'::jsonb)));
  v_prox := NULL;
  FOR v_i IN 1..COALESCE(array_length(v_ordem, 1), 1) LOOP
    IF v_ordem[v_i] = v_nivel AND v_i < array_length(v_ordem, 1) THEN v_prox := v_ordem[v_i + 1]; END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'perfil', v_perfil,
    'reputacao', v_rep,
    'nivel', jsonb_build_object('atual', v_nivel, 'proximo', v_prox, 'requisitos_proximo', v_niveis->'requisitos'->v_prox,
                                'aviso_em', v_rep->>'nivel_aviso_em', 'aviso_motivo', v_rep->>'nivel_aviso_motivo', 'ordem', to_jsonb(v_ordem)),
    'completude', (SELECT round(100.0 * (
        (v_perfil->>'foto_url' IS NOT NULL)::int + (COALESCE(v_perfil->>'bio', '') <> '')::int + (v_perfil->>'registro_profissional' IS NOT NULL)::int
        + (jsonb_array_length(COALESCE(v_perfil->'especialidades', '[]'::jsonb)) > 0)::int + (v_perfil->>'cidade' IS NOT NULL)::int
        + (v_perfil->>'video_url' IS NOT NULL)::int + (v_perfil->>'telefone' IS NOT NULL)::int
        + (EXISTS (SELECT 1 FROM public.marketplace_servicos s WHERE s.profissional_id = v_id AND s.status = 'publicado'))::int) / 8)),
    'anuncios', COALESCE((SELECT jsonb_agg(to_jsonb(s) || jsonb_build_object('categoria_nome', c.nome, 'categoria_slug', c.slug, 'exige_registro', c.exige_registro) ORDER BY s.created_at DESC)
                          FROM public.marketplace_servicos s LEFT JOIN public.marketplace_categorias c ON c.id = s.categoria_id WHERE s.profissional_id = v_id AND s.status <> 'removido'), '[]'::jsonb),
    'leads', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'id', l.id, 'status', l.status, 'created_at', l.created_at, 'contato_liberado', l.contato_liberado, 'primeira_resposta_em', l.primeira_resposta_em,
                'ultima_mensagem_em', l.ultima_mensagem_em, 'servico_nome', s.nome, 'empresa_nome', t.nome, 'origem_modulo', l.origem_modulo,
                'obrigacao_legal', l.obrigacao_legal, 'cupom_codigo', l.cupom_codigo, 'ganho_em', l.ganho_em,
                'reputacao_empresa', (SELECT jsonb_build_object('media', round(avg(a.nota_geral)::numeric, 1), 'total', count(*))
                                      FROM public.marketplace_avaliacoes a WHERE a.tenant_id = l.tenant_id AND a.direcao = 'especialista_para_cliente'),
                'ultima_mensagem', (SELECT m.texto FROM public.marketplace_lead_mensagens m WHERE m.lead_id = l.id ORDER BY m.created_at DESC LIMIT 1),
                'avaliei', EXISTS (SELECT 1 FROM public.marketplace_avaliacoes a WHERE a.lead_id = l.id AND a.direcao = 'especialista_para_cliente')
              ) ORDER BY COALESCE(l.ultima_mensagem_em, l.created_at) DESC)
              FROM public.marketplace_leads l LEFT JOIN public.marketplace_servicos s ON s.id = l.servico_id LEFT JOIN public.tenants t ON t.id = l.tenant_id
              WHERE l.profissional_id = v_id), '[]'::jsonb),
    'metricas', jsonb_build_object(
      'leads_30d', (SELECT count(*) FROM public.marketplace_leads WHERE profissional_id = v_id AND created_at >= now() - interval '30 days'),
      'leads_ganhos_30d', (SELECT count(*) FROM public.marketplace_leads WHERE profissional_id = v_id AND status = 'ganho' AND ganho_em >= now() - interval '30 days'),
      'sem_resposta', (SELECT count(*) FROM public.marketplace_leads WHERE profissional_id = v_id AND status = 'novo'),
      'avaliacoes', (SELECT count(*) FROM public.marketplace_avaliacoes WHERE profissional_id = v_id AND direcao = 'cliente_para_especialista')),
    'avaliacoes', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', a.id, 'nota_geral', a.nota_geral, 'comentario', a.comentario, 'created_at', a.created_at,
                              'resposta', a.resposta, 'criterios', a.criterios, 'pontualidade', a.pontualidade, 'clareza', a.clareza,
                              'aderencia_escopo', a.aderencia_escopo, 'profissionalismo', a.profissionalismo) ORDER BY a.created_at DESC)
                            FROM public.marketplace_avaliacoes a WHERE a.profissional_id = v_id AND a.direcao = 'cliente_para_especialista' AND NOT a.moderada), '[]'::jsonb),
    'consentimentos', COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.aceito_em DESC) FROM public.marketplace_consentimentos c WHERE c.profissional_id = v_id), '[]'::jsonb),
    'termos_pendentes', COALESCE((SELECT jsonb_agg(jsonb_build_object('tipo', t.tipo, 'versao', v_versoes->>t.tipo))
                                  FROM (VALUES ('termos_especialista'), ('privacidade_nao_usuario'), ('codigo_etica')) AS t(tipo)
                                  WHERE v_versoes->>t.tipo IS NOT NULL AND NOT EXISTS (
                                    SELECT 1 FROM public.marketplace_consentimentos c WHERE c.profissional_id = v_id AND c.tipo = t.tipo AND c.versao = v_versoes->>t.tipo)), '[]'::jsonb),
    'contestacoes', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM public.marketplace_contestacoes x WHERE x.profissional_id = v_id), '[]'::jsonb),
    'ocorrencias', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', o.id, 'tipo', o.tipo, 'descricao', o.descricao, 'created_at', o.created_at, 'reflexo_visibilidade', o.reflexo_visibilidade) ORDER BY o.created_at DESC)
                             FROM public.marketplace_ocorrencias o WHERE o.profissional_id = v_id), '[]'::jsonb),
    'cupons', COALESCE((SELECT jsonb_agg(to_jsonb(k) ORDER BY k.created_at DESC) FROM public.marketplace_cupons k WHERE k.profissional_id = v_id), '[]'::jsonb),
    'destaques', COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.fim DESC) FROM public.marketplace_destaques d WHERE d.profissional_id = v_id), '[]'::jsonb),
    'autonomia_eventos', (SELECT count(*) FROM public.marketplace_autonomia_eventos WHERE profissional_id = v_id),
    'termos_versoes', v_versoes,
    'parceiro', CASE WHEN v_perfil->>'parceiro_id' IS NOT NULL THEN jsonb_build_object('id', v_perfil->>'parceiro_id') END
  );
END $marketye_meu_portal$;
GRANT EXECUTE ON FUNCTION public.marketye_meu_portal() TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_meu_perfil_salvar(_dados jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_meu_perfil_salvar$
DECLARE v_id uuid := public.marketye_meu_id(); v_mod text[];
BEGIN
  IF v_id IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF _dados ? 'modalidades' THEN v_mod := ARRAY(SELECT jsonb_array_elements_text(_dados->'modalidades')); END IF;
  UPDATE public.marketplace_profissionais SET
    nome_completo = CASE WHEN status = 'pendente' AND length(COALESCE(_dados->>'nome_completo', '')) >= 3 THEN _dados->>'nome_completo' ELSE nome_completo END,
    telefone = CASE WHEN _dados ? 'telefone' THEN NULLIF(_dados->>'telefone', '') ELSE telefone END,
    bio = CASE WHEN _dados ? 'bio' THEN NULLIF(_dados->>'bio', '') ELSE bio END,
    formacao_academica = CASE WHEN _dados ? 'formacao_academica' THEN NULLIF(_dados->>'formacao_academica', '') ELSE formacao_academica END,
    registro_profissional = CASE WHEN _dados ? 'registro_profissional' THEN NULLIF(_dados->>'registro_profissional', '') ELSE registro_profissional END,
    conselho = CASE WHEN _dados ? 'conselho' THEN NULLIF(_dados->>'conselho', '') ELSE conselho END,
    uf_registro = CASE WHEN _dados ? 'uf_registro' THEN NULLIF(upper(_dados->>'uf_registro'), '') ELSE uf_registro END,
    registro_validade = CASE WHEN _dados ? 'registro_validade' THEN NULLIF(_dados->>'registro_validade', '')::date ELSE registro_validade END,
    certificacoes = CASE WHEN _dados ? 'certificacoes' THEN NULLIF(ARRAY(SELECT jsonb_array_elements_text(_dados->'certificacoes')), '{}') ELSE certificacoes END,
    especialidades = CASE WHEN _dados ? 'especialidades' THEN NULLIF(ARRAY(SELECT jsonb_array_elements_text(_dados->'especialidades')), '{}') ELSE especialidades END,
    areas_atuacao = CASE WHEN _dados ? 'areas_atuacao' THEN NULLIF(ARRAY(SELECT jsonb_array_elements_text(_dados->'areas_atuacao')), '{}') ELSE areas_atuacao END,
    modalidades_atendimento = CASE WHEN v_mod IS NOT NULL AND array_length(v_mod, 1) > 0 THEN v_mod::public.marketplace_servico_modalidade[] ELSE modalidades_atendimento END,
    cidade = CASE WHEN _dados ? 'cidade' THEN NULLIF(_dados->>'cidade', '') ELSE cidade END,
    estado = CASE WHEN _dados ? 'estado' THEN NULLIF(upper(_dados->>'estado'), '') ELSE estado END,
    latitude = CASE WHEN _dados ? 'latitude' THEN NULLIF(_dados->>'latitude', '')::double precision ELSE latitude END,
    longitude = CASE WHEN _dados ? 'longitude' THEN NULLIF(_dados->>'longitude', '')::double precision ELSE longitude END,
    atende_remoto = CASE WHEN _dados ? 'atende_remoto' THEN (_dados->>'atende_remoto')::boolean ELSE atende_remoto END,
    raio_atendimento_km = CASE WHEN _dados ? 'raio_atendimento_km' THEN COALESCE(NULLIF(_dados->>'raio_atendimento_km', '')::int, raio_atendimento_km) ELSE raio_atendimento_km END,
    disponibilidade = CASE WHEN _dados ? 'disponibilidade' THEN COALESCE(_dados->'disponibilidade', '{}'::jsonb) ELSE disponibilidade END,
    politicas = CASE WHEN _dados ? 'politicas' THEN NULLIF(_dados->>'politicas', '') ELSE politicas END,
    site_url = CASE WHEN _dados ? 'site_url' THEN NULLIF(_dados->>'site_url', '') ELSE site_url END,
    video_url = CASE WHEN _dados ? 'video_url' THEN NULLIF(_dados->>'video_url', '') ELSE video_url END,
    foto_url = CASE WHEN _dados ? 'foto_url' THEN NULLIF(_dados->>'foto_url', '') ELSE foto_url END,
    tipo_pessoa = CASE WHEN _dados->>'tipo_pessoa' IN ('pf', 'pj') THEN _dados->>'tipo_pessoa' ELSE tipo_pessoa END
  WHERE id = v_id;
  RETURN jsonb_build_object('id', v_id, 'ok', true);
END $marketye_meu_perfil_salvar$;
GRANT EXECUTE ON FUNCTION public.marketye_meu_perfil_salvar(jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- 4) Anúncios (RF-003, RN-011, RN-013): salvar como rascunho, publicar por função
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_anuncio_salvar(_dados jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_anuncio_salvar$
DECLARE v_prof uuid := public.marketye_meu_id(); v_id uuid := NULLIF(_dados->>'id', '')::uuid; v_cat uuid := NULLIF(_dados->>'categoria_id', '')::uuid; v_obr text[];
BEGIN
  IF v_prof IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF length(trim(COALESCE(_dados->>'nome', ''))) < 5 THEN RAISE EXCEPTION 'Dê um título ao anúncio (mínimo 5 letras)'; END IF;
  IF length(trim(COALESCE(_dados->>'descricao', ''))) < 20 THEN RAISE EXCEPTION 'Descreva o serviço (mínimo 20 letras)'; END IF;
  IF COALESCE(_dados->>'tipo_preco', 'sob_orcamento') <> 'sob_orcamento' AND COALESCE(NULLIF(_dados->>'preco_referencia', '')::numeric, 0) <= 0 THEN
    RAISE EXCEPTION 'Informe um preço-base ou marque "sob orçamento".';
  END IF;
  v_obr := ARRAY(SELECT jsonb_array_elements_text(COALESCE(_dados->'obrigacao_legal', '[]'::jsonb)));
  IF array_length(v_obr, 1) IS NULL AND v_cat IS NOT NULL THEN
    SELECT obrigacao_legal INTO v_obr FROM public.marketplace_categorias WHERE id = v_cat;
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO public.marketplace_servicos (profissional_id, categoria_id, nome, descricao, base_legal, modalidade, publico_alvo, evidencia_minima,
      preco_referencia, tipo_preco, preco_minimo, preco_maximo, duracao_estimada_minutos, tags, obrigacao_legal, area_atendimento, prazo_tipico,
      politica_cancelamento, midia, gerado_por_ia, promocao_percentual, promocao_inicio, promocao_fim, promocao_descricao, ativo, status, moeda, pais)
    VALUES (v_prof, v_cat, trim(_dados->>'nome'), trim(_dados->>'descricao'), NULLIF(_dados->>'base_legal', ''),
      COALESCE(NULLIF(_dados->>'modalidade', ''), 'presencial')::public.marketplace_servico_modalidade, NULLIF(_dados->>'publico_alvo', ''), NULLIF(_dados->>'evidencia_minima', ''),
      NULLIF(_dados->>'preco_referencia', '')::numeric, COALESCE(NULLIF(_dados->>'tipo_preco', ''), 'sob_orcamento'), NULLIF(_dados->>'preco_minimo', '')::numeric,
      NULLIF(_dados->>'preco_maximo', '')::numeric, NULLIF(_dados->>'duracao_estimada_minutos', '')::int,
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(_dados->'tags', '[]'::jsonb))), COALESCE(v_obr, '{}'), COALESCE(_dados->'area_atendimento', '{}'::jsonb),
      NULLIF(_dados->>'prazo_tipico', ''), NULLIF(_dados->>'politica_cancelamento', ''), COALESCE(_dados->'midia', '[]'::jsonb),
      COALESCE((_dados->>'gerado_por_ia')::boolean, false), NULLIF(_dados->>'promocao_percentual', '')::numeric, NULLIF(_dados->>'promocao_inicio', '')::date,
      NULLIF(_dados->>'promocao_fim', '')::date, NULLIF(_dados->>'promocao_descricao', ''), true, 'rascunho',
      COALESCE(NULLIF(_dados->>'moeda', ''), 'BRL'), COALESCE(NULLIF(_dados->>'pais', ''), 'BR'))
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.marketplace_servicos SET
      categoria_id = v_cat, nome = trim(_dados->>'nome'), descricao = trim(_dados->>'descricao'), base_legal = NULLIF(_dados->>'base_legal', ''),
      modalidade = COALESCE(NULLIF(_dados->>'modalidade', ''), modalidade::text)::public.marketplace_servico_modalidade,
      publico_alvo = NULLIF(_dados->>'publico_alvo', ''), evidencia_minima = NULLIF(_dados->>'evidencia_minima', ''),
      preco_referencia = NULLIF(_dados->>'preco_referencia', '')::numeric, tipo_preco = COALESCE(NULLIF(_dados->>'tipo_preco', ''), 'sob_orcamento'),
      preco_minimo = NULLIF(_dados->>'preco_minimo', '')::numeric, preco_maximo = NULLIF(_dados->>'preco_maximo', '')::numeric,
      duracao_estimada_minutos = NULLIF(_dados->>'duracao_estimada_minutos', '')::int,
      tags = ARRAY(SELECT jsonb_array_elements_text(COALESCE(_dados->'tags', '[]'::jsonb))), obrigacao_legal = COALESCE(v_obr, '{}'),
      area_atendimento = COALESCE(_dados->'area_atendimento', '{}'::jsonb), prazo_tipico = NULLIF(_dados->>'prazo_tipico', ''),
      politica_cancelamento = NULLIF(_dados->>'politica_cancelamento', ''), midia = COALESCE(_dados->'midia', midia),
      promocao_percentual = NULLIF(_dados->>'promocao_percentual', '')::numeric, promocao_inicio = NULLIF(_dados->>'promocao_inicio', '')::date,
      promocao_fim = NULLIF(_dados->>'promocao_fim', '')::date, promocao_descricao = NULLIF(_dados->>'promocao_descricao', ''),
      status = CASE WHEN status = 'removido' THEN 'rascunho' ELSE status END
    WHERE id = v_id AND profissional_id = v_prof;
    IF NOT FOUND THEN RAISE EXCEPTION 'Anúncio não encontrado'; END IF;
  END IF;
  RETURN jsonb_build_object('id', v_id);
END $marketye_anuncio_salvar$;
GRANT EXECUTE ON FUNCTION public.marketye_anuncio_salvar(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_anuncio_publicar(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_anuncio_publicar$
DECLARE v_prof uuid := public.marketye_meu_id(); s record; p record; c record;
BEGIN
  IF v_prof IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  SELECT * INTO s FROM public.marketplace_servicos WHERE id = p_id AND profissional_id = v_prof;
  IF s.id IS NULL THEN RAISE EXCEPTION 'Anúncio não encontrado'; END IF;
  SELECT * INTO p FROM public.marketplace_profissionais WHERE id = v_prof;
  IF p.status::text <> 'ativo' THEN
    RAISE EXCEPTION 'Seu cadastro ainda está em verificação. O anúncio fica salvo e aparece na vitrine assim que a verificação concluir.';
  END IF;
  IF p.excluido_em IS NOT NULL THEN RAISE EXCEPTION 'Perfil excluído'; END IF;
  IF s.categoria_id IS NOT NULL THEN
    SELECT * INTO c FROM public.marketplace_categorias WHERE id = s.categoria_id;
    IF c.exige_registro AND (p.registro_profissional IS NULL OR p.conselho IS NULL) THEN
      RAISE EXCEPTION 'Para publicar em %, informe seu registro profissional (%).', c.nome, COALESCE(array_to_string(c.conselhos_aceitos, '/'), 'conselho');
    END IF;
  END IF;
  IF public.marketye_texto_tem_contato(s.nome) OR public.marketye_texto_tem_contato(s.descricao) THEN
    RAISE EXCEPTION 'Remova telefones, e-mails ou links do texto — o contato acontece pelo MarketYE.';
  END IF;
  UPDATE public.marketplace_servicos SET status = 'publicado', ativo = true, publicado_em = COALESCE(publicado_em, now()) WHERE id = p_id;
  RETURN jsonb_build_object('id', p_id, 'status', 'publicado');
END $marketye_anuncio_publicar$;
GRANT EXECUTE ON FUNCTION public.marketye_anuncio_publicar(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_anuncio_status(p_id uuid, p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_anuncio_status$
DECLARE v_prof uuid := public.marketye_meu_id();
BEGIN
  IF v_prof IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF p_status NOT IN ('pausado', 'removido', 'rascunho') THEN RAISE EXCEPTION 'Use marketye_anuncio_publicar para publicar'; END IF;
  UPDATE public.marketplace_servicos SET status = p_status, ativo = (p_status <> 'removido') WHERE id = p_id AND profissional_id = v_prof;
  IF NOT FOUND THEN RAISE EXCEPTION 'Anúncio não encontrado'; END IF;
  RETURN jsonb_build_object('id', p_id, 'status', p_status);
END $marketye_anuncio_status$;
GRANT EXECUTE ON FUNCTION public.marketye_anuncio_status(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_cupom_salvar(_dados jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_cupom_salvar$
DECLARE v_prof uuid := public.marketye_meu_id(); v_id uuid;
BEGIN
  IF v_prof IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF COALESCE(_dados->>'codigo', '') !~ '^[A-Za-z0-9_-]{3,20}$' THEN RAISE EXCEPTION 'Código do cupom: 3 a 20 letras/números'; END IF;
  INSERT INTO public.marketplace_cupons (profissional_id, codigo, descricao, desconto_percentual, validade, limite_uso)
  VALUES (v_prof, upper(_dados->>'codigo'), NULLIF(_dados->>'descricao', ''), (_dados->>'desconto_percentual')::numeric,
          NULLIF(_dados->>'validade', '')::date, NULLIF(_dados->>'limite_uso', '')::int)
  ON CONFLICT (profissional_id, codigo) DO UPDATE SET descricao = EXCLUDED.descricao, desconto_percentual = EXCLUDED.desconto_percentual,
    validade = EXCLUDED.validade, limite_uso = EXCLUDED.limite_uso, ativo = COALESCE((_dados->>'ativo')::boolean, true)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id);
END $marketye_cupom_salvar$;
GRANT EXECUTE ON FUNCTION public.marketye_cupom_salvar(jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- 5) Leads (RF-012, RN-020, RN-027, RN-030)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_lead_papel(p_lead_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $marketye_lead_papel$
DECLARE l record;
BEGIN
  SELECT tenant_id, profissional_id INTO l FROM public.marketplace_leads WHERE id = p_lead_id;
  IF l.tenant_id IS NULL THEN RETURN NULL; END IF;
  IF l.profissional_id = public.marketye_meu_id() THEN RETURN 'especialista'; END IF;
  IF l.tenant_id = public.get_user_tenant_id() THEN RETURN 'cliente'; END IF;
  IF public.is_superadmin(auth.uid()) THEN RETURN 'moderador'; END IF;
  RETURN NULL;
END $marketye_lead_papel$;
GRANT EXECUTE ON FUNCTION public.marketye_lead_papel(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_abrir_lead(p_profissional_id uuid, p_servico_id uuid, p_mensagem text,
                                                      p_origem_modulo text DEFAULT NULL, p_origem_id uuid DEFAULT NULL, p_obrigacao text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_abrir_lead$
DECLARE v_tenant uuid := public.get_user_tenant_id(); v_lead uuid; v_nome text; v_cupom text; v_mascarar boolean; v_texto text; v_existente uuid;
BEGIN
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'Só usuários de uma empresa cliente abrem contato'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.marketplace_profissionais WHERE id = p_profissional_id AND status = 'ativo' AND excluido_em IS NULL) THEN
    RAISE EXCEPTION 'Especialista indisponível no momento';
  END IF;
  IF length(trim(COALESCE(p_mensagem, ''))) < 5 THEN RAISE EXCEPTION 'Escreva uma mensagem com o que você precisa'; END IF;
  SELECT id INTO v_existente FROM public.marketplace_leads WHERE tenant_id = v_tenant AND profissional_id = p_profissional_id
    AND status IN ('novo', 'respondido', 'qualificado') ORDER BY created_at DESC LIMIT 1;
  IF v_existente IS NOT NULL THEN
    PERFORM public.marketye_lead_mensagem(v_existente, p_mensagem);
    RETURN jsonb_build_object('id', v_existente, 'reaproveitado', true);
  END IF;
  SELECT nome_completo INTO v_nome FROM public.profiles WHERE user_id = auth.uid() LIMIT 1;
  SELECT codigo INTO v_cupom FROM public.marketplace_cupons WHERE profissional_id = p_profissional_id AND ativo
    AND (validade IS NULL OR validade >= CURRENT_DATE) AND (limite_uso IS NULL OR usos < limite_uso) ORDER BY desconto_percentual DESC LIMIT 1;
  v_mascarar := COALESCE(public.marketye_config('mascaramento_contato')->>'ate', 'contato_qualificado') <> 'nunca';
  v_texto := CASE WHEN v_mascarar THEN public.marketye_mascarar_contato(p_mensagem) ELSE p_mensagem END;

  INSERT INTO public.marketplace_leads (tenant_id, profissional_id, servico_id, criado_por, solicitante_nome, origem_modulo, origem_id, obrigacao_legal, cupom_codigo, ultima_mensagem_em)
  VALUES (v_tenant, p_profissional_id, p_servico_id, auth.uid(), v_nome, p_origem_modulo, p_origem_id, p_obrigacao, v_cupom, now()) RETURNING id INTO v_lead;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto, texto_original, mascarada, sinal_saida)
  VALUES (v_lead, 'cliente', auth.uid(), v_texto, CASE WHEN v_texto <> p_mensagem THEN p_mensagem END, v_texto <> p_mensagem, public.marketye_texto_tem_contato(p_mensagem));
  IF v_cupom IS NOT NULL THEN
    INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, texto) VALUES (v_lead, 'sistema', format('Este especialista tem o cupom %s ativo para esta conversa.', v_cupom));
    UPDATE public.marketplace_cupons SET usos = usos + 1 WHERE profissional_id = p_profissional_id AND codigo = v_cupom;
  END IF;
  RETURN jsonb_build_object('id', v_lead, 'reaproveitado', false);
END $marketye_abrir_lead$;
GRANT EXECUTE ON FUNCTION public.marketye_abrir_lead(uuid, uuid, text, text, uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_lead_mensagem(p_lead_id uuid, p_texto text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_lead_mensagem$
DECLARE v_papel text := public.marketye_lead_papel(p_lead_id); l record; v_texto text; v_mascarar boolean; v_id uuid;
BEGIN
  IF v_papel NOT IN ('cliente', 'especialista') THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF length(trim(COALESCE(p_texto, ''))) = 0 THEN RAISE EXCEPTION 'Mensagem vazia'; END IF;
  SELECT * INTO l FROM public.marketplace_leads WHERE id = p_lead_id;
  IF l.status IN ('perdido', 'encerrado') THEN RAISE EXCEPTION 'Esta conversa foi encerrada'; END IF;
  v_mascarar := NOT l.contato_liberado AND COALESCE(public.marketye_config('mascaramento_contato')->>'ate', 'contato_qualificado') <> 'nunca';
  v_texto := CASE WHEN v_mascarar THEN public.marketye_mascarar_contato(p_texto) ELSE p_texto END;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto, texto_original, mascarada, sinal_saida)
  VALUES (p_lead_id, v_papel, auth.uid(), v_texto, CASE WHEN v_texto <> p_texto THEN p_texto END, v_texto <> p_texto, public.marketye_texto_tem_contato(p_texto))
  RETURNING id INTO v_id;
  UPDATE public.marketplace_leads SET ultima_mensagem_em = now(),
    primeira_resposta_em = CASE WHEN v_papel = 'especialista' AND primeira_resposta_em IS NULL THEN now() ELSE primeira_resposta_em END,
    status = CASE WHEN v_papel = 'especialista' AND status = 'novo' THEN 'respondido' ELSE status END
  WHERE id = p_lead_id;
  RETURN jsonb_build_object('id', v_id, 'mascarada', v_texto <> p_texto);
END $marketye_lead_mensagem$;
GRANT EXECUTE ON FUNCTION public.marketye_lead_mensagem(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_lead_liberar_contato(p_lead_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_lead_liberar_contato$
BEGIN
  IF public.marketye_lead_papel(p_lead_id) <> 'cliente' THEN RAISE EXCEPTION 'Só a empresa cliente libera o contato'; END IF;
  UPDATE public.marketplace_leads SET contato_liberado = true, contato_liberado_em = COALESCE(contato_liberado_em, now()),
    status = CASE WHEN status IN ('novo', 'respondido') THEN 'qualificado' ELSE status END, ultima_mensagem_em = now() WHERE id = p_lead_id;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, texto)
  VALUES (p_lead_id, 'sistema', 'A empresa liberou o contato direto. Combinem os detalhes e, ao fechar, marquem "serviço combinado" para habilitar a avaliação.');
  RETURN jsonb_build_object('id', p_lead_id, 'contato_liberado', true);
END $marketye_lead_liberar_contato$;
GRANT EXECUTE ON FUNCTION public.marketye_lead_liberar_contato(uuid) TO authenticated;

-- Fechamento do lead. Recusar não gera reflexo algum (RN-030): o prestador é livre.
CREATE OR REPLACE FUNCTION public.marketye_lead_status(p_lead_id uuid, p_status text, p_motivo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_lead_status$
DECLARE v_papel text := public.marketye_lead_papel(p_lead_id); v_prof uuid;
BEGIN
  IF v_papel NOT IN ('cliente', 'especialista') THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_status NOT IN ('ganho', 'perdido', 'encerrado') THEN RAISE EXCEPTION 'Situação inválida'; END IF;
  UPDATE public.marketplace_leads SET status = p_status, ganho_em = CASE WHEN p_status = 'ganho' THEN COALESCE(ganho_em, now()) ELSE ganho_em END,
    contato_liberado = CASE WHEN p_status = 'ganho' THEN true ELSE contato_liberado END, ultima_mensagem_em = now()
  WHERE id = p_lead_id RETURNING profissional_id INTO v_prof;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto)
  VALUES (p_lead_id, 'sistema', auth.uid(), CASE p_status WHEN 'ganho' THEN 'Serviço combinado. Os dois lados já podem avaliar.'
                                                   WHEN 'perdido' THEN 'A empresa encerrou esta conversa sem contratar.'
                                                   ELSE COALESCE('Conversa encerrada. ' || p_motivo, 'Conversa encerrada.') END);
  IF p_status = 'ganho' THEN PERFORM public.marketye_recalcular_reputacao(v_prof); END IF;
  RETURN jsonb_build_object('id', p_lead_id, 'status', p_status);
END $marketye_lead_status$;
GRANT EXECUTE ON FUNCTION public.marketye_lead_status(uuid, text, text) TO authenticated;

-- Contato da outra parte, só depois da liberação (RN-020).
CREATE OR REPLACE FUNCTION public.marketye_lead_contato(p_lead_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_lead_contato$
DECLARE v_papel text := public.marketye_lead_papel(p_lead_id); l record; v_email text;
BEGIN
  IF v_papel IS NULL THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  SELECT * INTO l FROM public.marketplace_leads WHERE id = p_lead_id;
  IF NOT l.contato_liberado THEN RETURN jsonb_build_object('liberado', false); END IF;
  IF v_papel IN ('cliente', 'moderador') THEN
    RETURN (SELECT jsonb_build_object('liberado', true, 'nome', p.nome_completo, 'email', p.email, 'telefone', p.telefone, 'site_url', p.site_url)
            FROM public.marketplace_profissionais p WHERE p.id = l.profissional_id);
  END IF;
  SELECT email INTO v_email FROM auth.users WHERE id = l.criado_por;
  RETURN (SELECT jsonb_build_object('liberado', true, 'empresa', t.nome, 'solicitante', l.solicitante_nome, 'email', v_email, 'telefone', pr.telefone)
          FROM public.tenants t LEFT JOIN public.profiles pr ON pr.user_id = l.criado_por WHERE t.id = l.tenant_id);
END $marketye_lead_contato$;
GRANT EXECUTE ON FUNCTION public.marketye_lead_contato(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_lead_vincular_documento(p_lead_id uuid, p_documento_id uuid, p_tipo text DEFAULT 'proposta')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_lead_vincular_documento$
DECLARE v_id uuid;
BEGIN
  IF public.marketye_lead_papel(p_lead_id) <> 'cliente' THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  INSERT INTO public.marketplace_lead_documentos (lead_id, documento_id, tipo) VALUES (p_lead_id, p_documento_id, COALESCE(p_tipo, 'proposta')) RETURNING id INTO v_id;
  INSERT INTO public.marketplace_lead_mensagens (lead_id, autor_tipo, autor_id, texto) VALUES (p_lead_id, 'sistema', auth.uid(), 'Documento arquivado no módulo Documentos e vinculado a esta conversa.');
  RETURN jsonb_build_object('id', v_id);
END $marketye_lead_vincular_documento$;
GRANT EXECUTE ON FUNCTION public.marketye_lead_vincular_documento(uuid, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 6) Avaliação bidirecional só com transação verificada (RF-010, RN-004/022)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_avaliar(p_ref_tipo text, p_ref_id uuid, p_notas jsonb, p_comentario text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_avaliar$
DECLARE
  v_tenant uuid; v_prof uuid; v_servico uuid; v_concluido timestamptz; v_direcao text; v_janela int; v_notas numeric[]; v_media numeric;
  v_id uuid; v_coment text; k text; v_val numeric; v_meu uuid := public.marketye_meu_id(); v_lead uuid; v_contr uuid;
BEGIN
  v_janela := COALESCE((public.marketye_config('janela_avaliacao_dias')->>'dias')::int, 14);
  IF p_ref_tipo = 'contratacao' THEN
    SELECT tenant_id, profissional_id, servico_id, CASE WHEN status = 'concluida' THEN COALESCE(data_conclusao, updated_at) END
      INTO v_tenant, v_prof, v_servico, v_concluido FROM public.marketplace_contratacoes WHERE id = p_ref_id;
    v_contr := p_ref_id;
  ELSIF p_ref_tipo = 'lead' THEN
    SELECT tenant_id, profissional_id, servico_id, CASE WHEN status = 'ganho' THEN ganho_em END
      INTO v_tenant, v_prof, v_servico, v_concluido FROM public.marketplace_leads WHERE id = p_ref_id;
    v_lead := p_ref_id;
  ELSE
    RAISE EXCEPTION 'Referência inválida';
  END IF;
  IF v_tenant IS NULL THEN RAISE EXCEPTION 'Registro não encontrado'; END IF;
  IF v_concluido IS NULL THEN RAISE EXCEPTION 'Avaliações ficam disponíveis após o atendimento (serviço concluído ou combinado).'; END IF;
  IF v_concluido < now() - make_interval(days => v_janela) THEN RAISE EXCEPTION 'O prazo de % dias para avaliar já passou.', v_janela; END IF;

  IF v_meu IS NOT NULL AND v_meu = v_prof THEN v_direcao := 'especialista_para_cliente';
  ELSIF public.get_user_tenant_id() = v_tenant THEN v_direcao := 'cliente_para_especialista';
  ELSE RAISE EXCEPTION 'Só quem participou do atendimento avalia'; END IF;

  -- Anti-gaming (11.4): no máximo 3 avaliações por par empresa×especialista em 30 dias.
  IF (SELECT count(*) FROM public.marketplace_avaliacoes WHERE tenant_id = v_tenant AND profissional_id = v_prof AND direcao = v_direcao AND created_at >= now() - interval '30 days') >= 3 THEN
    RAISE EXCEPTION 'Limite de avaliações entre esta empresa e este especialista no período.';
  END IF;

  v_notas := '{}';
  FOR k, v_val IN SELECT key, value::text::numeric FROM jsonb_each(COALESCE(p_notas, '{}'::jsonb)) LOOP
    IF v_val < 1 OR v_val > 5 THEN RAISE EXCEPTION 'Notas vão de 1 a 5'; END IF;
    v_notas := v_notas || v_val;
  END LOOP;
  IF array_length(v_notas, 1) IS NULL THEN RAISE EXCEPTION 'Avalie ao menos um critério'; END IF;
  SELECT round(avg(x)::numeric, 2) INTO v_media FROM unnest(v_notas) x;
  v_coment := NULLIF(trim(COALESCE(p_comentario, '')), '');
  IF v_coment IS NOT NULL AND public.marketye_texto_tem_contato(v_coment) THEN v_coment := public.marketye_mascarar_contato(v_coment); END IF;

  INSERT INTO public.marketplace_avaliacoes (contratacao_id, lead_id, profissional_id, servico_id, avaliador_id, tenant_id, direcao, criterios,
    pontualidade, clareza, aderencia_escopo, profissionalismo, nota_geral, comentario)
  VALUES (v_contr, v_lead, v_prof, v_servico, auth.uid(), v_tenant, v_direcao, COALESCE(p_notas, '{}'::jsonb),
    CASE WHEN v_direcao = 'cliente_para_especialista' THEN NULLIF(p_notas->>'pontualidade', '')::int END,
    CASE WHEN v_direcao = 'cliente_para_especialista' THEN NULLIF(p_notas->>'clareza', '')::int END,
    CASE WHEN v_direcao = 'cliente_para_especialista' THEN NULLIF(p_notas->>'aderencia_escopo', '')::int END,
    CASE WHEN v_direcao = 'cliente_para_especialista' THEN NULLIF(p_notas->>'profissionalismo', '')::int END,
    v_media, v_coment)
  RETURNING id INTO v_id;

  INSERT INTO public.marketplace_audit_log (tenant_id, contratacao_id, profissional_id, acao, descricao, dados, usuario_id)
  VALUES (v_tenant, v_contr, v_prof, 'avaliacao_enviada', format('Avaliação %s: %s/5', v_direcao, v_media), json_build_object('avaliacao_id', v_id, 'lead_id', v_lead), auth.uid());
  IF v_direcao = 'cliente_para_especialista' THEN PERFORM public.marketye_recalcular_reputacao(v_prof); END IF;
  RETURN jsonb_build_object('id', v_id, 'nota_geral', v_media, 'direcao', v_direcao);
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Este atendimento já foi avaliado por você.';
END $marketye_avaliar$;
GRANT EXECUTE ON FUNCTION public.marketye_avaliar(text, uuid, jsonb, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_avaliacao_responder(p_avaliacao_id uuid, p_resposta text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_avaliacao_responder$
BEGIN
  UPDATE public.marketplace_avaliacoes SET resposta = public.marketye_mascarar_contato(left(trim(p_resposta), 1000)), respondido_em = now()
  WHERE id = p_avaliacao_id AND profissional_id = public.marketye_meu_id() AND direcao = 'cliente_para_especialista';
  IF NOT FOUND THEN RAISE EXCEPTION 'Avaliação não encontrada'; END IF;
  RETURN jsonb_build_object('id', p_avaliacao_id);
END $marketye_avaliacao_responder$;
GRANT EXECUTE ON FUNCTION public.marketye_avaliacao_responder(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 7) Busca com relevância personalizada e busca nunca-vazia (RF-006/008, RN-006/007/008/023)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_buscar_interno(p jsonb)
RETURNS SETOF jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_buscar_interno$
  WITH cfg AS (
    SELECT COALESCE(public.marketye_config('relevancia_pesos'), '{"fit":0.25,"reputacao":0.20,"saude":0.20,"proximidade":0.15,"exploracao":0.10,"preco":0.05,"destaque":0.05}'::jsonb) AS pesos,
           COALESCE(public.marketye_config('protecao_novato'), '{"dias":30,"ate_avaliacoes":3}'::jsonb) AS nov
  ), f AS (
    SELECT NULLIF(trim(p->>'q'), '') AS q,
           NULLIF(p->>'categoria_id', '')::uuid AS categoria_id,
           NULLIF(p->>'categoria_slug', '') AS categoria_slug,
           NULLIF(p->>'modalidade', '') AS modalidade,
           NULLIF(upper(p->>'uf'), '') AS uf,
           NULLIF(trim(p->>'cidade'), '') AS cidade,
           COALESCE((p->>'somente_remoto')::boolean, false) AS somente_remoto,
           NULLIF(p->>'preco_max', '')::numeric AS preco_max,
           NULLIF(p->>'nota_min', '')::numeric AS nota_min,
           COALESCE((p->>'selo')::boolean, false) AS selo,
           NULLIF(p->>'nivel_min', '') AS nivel_min,
           NULLIF(p->>'lat', '')::double precision AS lat,
           NULLIF(p->>'lng', '')::double precision AS lng,
           COALESCE(NULLIF(p->>'raio_km', '')::double precision, 100) AS raio_km,
           COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(p->'obrigacoes', '[]'::jsonb))), '{}'::text[]) AS obrigacoes,
           COALESCE(NULLIF(p->>'limite', '')::int, 60) AS limite
  ), cat AS (
    SELECT c.id FROM public.marketplace_categorias c, f
    WHERE (f.categoria_id IS NOT NULL AND (c.id = f.categoria_id OR c.pai_id = f.categoria_id))
       OR (f.categoria_slug IS NOT NULL AND (c.slug = f.categoria_slug OR c.pai_id = (SELECT id FROM public.marketplace_categorias WHERE slug = f.categoria_slug LIMIT 1)))
  ), base AS (
    SELECT s.id AS servico_id, s.nome, s.descricao, s.base_legal, s.modalidade::text AS modalidade, s.preco_referencia, s.tipo_preco, s.preco_minimo, s.preco_maximo,
           s.moeda, s.duracao_estimada_minutos, s.tags, s.obrigacao_legal, s.prazo_tipico, s.midia, s.promocao_percentual, s.promocao_descricao,
           s.categoria_id, c.nome AS categoria_nome, c.slug AS categoria_slug, c.obrigacao_legal AS cat_obrigacao, c.pai_id,
           p.id AS profissional_id, p.nome_completo, p.foto_url, p.bio, p.cidade, p.estado, p.selo_verificado, p.nota_media, p.total_avaliacoes,
           p.total_servicos_executados, p.atende_remoto, p.conselho, p.registro_profissional, p.especialidades, p.modalidades_atendimento,
           p.created_at AS prof_created_at, p.tipo_pessoa, p.video_url,
           COALESCE(r.saude_score, 60) AS saude_score, COALESCE(r.saude_cor, 'cinza') AS saude_cor, COALESCE(r.nivel, 'novo') AS nivel,
           COALESCE(r.abaixo_piso, false) AS abaixo_piso, COALESCE(r.clientes_unicos_total, 0) AS clientes_unicos, r.tempo_resposta_mediano_min, r.taxa_resposta_90d,
           (s.modalidade::text = 'online' OR (s.modalidade::text = 'hibrido' AND p.atende_remoto) OR p.atende_remoto) AS remoto,
           (s.promocao_percentual IS NOT NULL AND CURRENT_DATE BETWEEN COALESCE(s.promocao_inicio, CURRENT_DATE) AND COALESCE(s.promocao_fim, CURRENT_DATE)) AS promocao_ativa,
           EXISTS (SELECT 1 FROM public.marketplace_cupons k WHERE k.profissional_id = p.id AND k.ativo AND (k.validade IS NULL OR k.validade >= CURRENT_DATE) AND (k.limite_uso IS NULL OR k.usos < k.limite_uso)) AS tem_cupom,
           EXISTS (SELECT 1 FROM public.marketplace_destaques d, f WHERE d.profissional_id = p.id AND d.ativo AND CURRENT_DATE BETWEEN d.inicio AND d.fim
                     AND (d.servico_id IS NULL OR d.servico_id = s.id)
                     AND (d.tipo = 'topo' OR (d.tipo = 'categoria' AND (d.categoria_id = s.categoria_id OR d.categoria_id = c.pai_id))
                          OR (d.tipo = 'regiao' AND d.uf IS NOT NULL AND d.uf = COALESCE(f.uf, p.estado)))) AS destaque_ativo,
           CASE WHEN f.lat IS NOT NULL AND f.lng IS NOT NULL AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL
                THEN public.haversine_distance(f.lat, f.lng, p.latitude, p.longitude) END AS distancia_km,
           (COALESCE(r.protegido_ate, p.created_at + make_interval(days => COALESCE((cfg.nov->>'dias')::int, 30))) > now()
              AND p.total_avaliacoes < COALESCE((cfg.nov->>'ate_avaliacoes')::int, 3)) AS novato_protegido
    FROM public.marketplace_servicos s
    JOIN public.marketplace_profissionais p ON p.id = s.profissional_id
    LEFT JOIN public.marketplace_categorias c ON c.id = s.categoria_id
    LEFT JOIN public.marketplace_reputacao r ON r.profissional_id = p.id
    CROSS JOIN f CROSS JOIN cfg
    WHERE s.ativo AND s.status = 'publicado' AND p.status = 'ativo' AND p.excluido_em IS NULL
      AND (f.q IS NULL OR s.nome ILIKE '%' || f.q || '%' OR s.descricao ILIKE '%' || f.q || '%' OR p.nome_completo ILIKE '%' || f.q || '%'
           OR c.nome ILIKE '%' || f.q || '%' OR EXISTS (SELECT 1 FROM unnest(s.tags || c.aliases || COALESCE(p.especialidades, '{}')) t WHERE t ILIKE '%' || f.q || '%'))
      AND ((f.categoria_id IS NULL AND f.categoria_slug IS NULL) OR s.categoria_id IN (SELECT id FROM cat))
      AND (f.modalidade IS NULL OR s.modalidade::text = f.modalidade OR (f.modalidade = 'online' AND s.modalidade::text = 'hibrido'))
      AND (NOT f.somente_remoto OR s.modalidade::text IN ('online', 'hibrido') OR p.atende_remoto)
      AND (f.uf IS NULL OR p.estado = f.uf OR s.modalidade::text = 'online' OR p.atende_remoto)
      AND (f.cidade IS NULL OR p.cidade ILIKE f.cidade OR s.modalidade::text = 'online' OR p.atende_remoto)
      AND (f.lat IS NULL OR f.lng IS NULL OR p.latitude IS NULL OR p.longitude IS NULL OR s.modalidade::text = 'online' OR p.atende_remoto
           OR public.haversine_distance(f.lat, f.lng, p.latitude, p.longitude) <= f.raio_km)
      AND (f.preco_max IS NULL OR s.preco_referencia IS NULL OR s.preco_referencia <= f.preco_max)
      AND (f.nota_min IS NULL OR p.nota_media >= f.nota_min OR p.total_avaliacoes = 0)
      AND (NOT f.selo OR p.selo_verificado)
      AND (f.nivel_min IS NULL OR public.marketye_nivel_indice(COALESCE(r.nivel, 'novo')) >= public.marketye_nivel_indice(f.nivel_min))
  ), pontuado AS (
    SELECT b.*,
      CASE WHEN array_length(f.obrigacoes, 1) IS NOT NULL AND (b.obrigacao_legal && f.obrigacoes OR COALESCE(b.cat_obrigacao, '{}') && f.obrigacoes) THEN 1.0
           WHEN f.categoria_id IS NOT NULL OR f.categoria_slug IS NOT NULL THEN 0.6 ELSE 0.3 END AS f_fit,
      CASE WHEN b.total_avaliacoes = 0 THEN 0.5 ELSE 0.7 * (b.nota_media / 5.0) + 0.3 * (public.marketye_nivel_indice(b.nivel) / 4.0) END AS f_reputacao,
      b.saude_score / 100.0 AS f_saude,
      CASE WHEN b.remoto THEN 0.8
           WHEN b.distancia_km IS NOT NULL THEN GREATEST(0, 1 - b.distancia_km / GREATEST(f.raio_km, 1))
           WHEN f.uf IS NOT NULL AND b.estado = f.uf THEN 0.7 ELSE 0.3 END AS f_proximidade,
      CASE WHEN b.novato_protegido THEN 1.0 ELSE (abs(hashtext(b.servico_id::text || CURRENT_DATE::text)) % 30) / 100.0 END AS f_exploracao,
      CASE WHEN b.promocao_ativa THEN 0.9 WHEN b.preco_referencia IS NULL THEN 0.5 ELSE 0.6 END AS f_preco,
      CASE WHEN b.destaque_ativo AND NOT b.abaixo_piso THEN 1.0 ELSE 0.0 END AS f_destaque
    FROM base b CROSS JOIN f
  ), final AS (
    SELECT p.*, round(((
        (cfg.pesos->>'fit')::numeric * f_fit::numeric + (cfg.pesos->>'reputacao')::numeric * f_reputacao::numeric + (cfg.pesos->>'saude')::numeric * f_saude::numeric
        + (cfg.pesos->>'proximidade')::numeric * f_proximidade::numeric + (cfg.pesos->>'exploracao')::numeric * f_exploracao::numeric
        + (cfg.pesos->>'preco')::numeric * f_preco::numeric + (cfg.pesos->>'destaque')::numeric * f_destaque::numeric
      ) * CASE WHEN p.abaixo_piso THEN 0.25 ELSE 1 END)::numeric, 4) AS score
    FROM pontuado p CROSS JOIN cfg
  )
  SELECT jsonb_build_object(
    'servico_id', servico_id, 'nome', nome, 'descricao', descricao, 'base_legal', base_legal, 'modalidade', modalidade,
    'preco_referencia', preco_referencia, 'tipo_preco', tipo_preco, 'preco_minimo', preco_minimo, 'preco_maximo', preco_maximo, 'moeda', moeda,
    'duracao_estimada_minutos', duracao_estimada_minutos, 'tags', to_jsonb(tags), 'obrigacao_legal', to_jsonb(obrigacao_legal), 'prazo_tipico', prazo_tipico,
    'midia', midia, 'promocao_ativa', promocao_ativa, 'promocao_percentual', promocao_percentual, 'promocao_descricao', promocao_descricao, 'tem_cupom', tem_cupom,
    'categoria_id', categoria_id, 'categoria_nome', categoria_nome, 'categoria_slug', categoria_slug,
    'profissional', jsonb_build_object('id', profissional_id, 'nome_completo', nome_completo, 'foto_url', foto_url, 'bio', bio, 'cidade', cidade, 'estado', estado,
      'selo_verificado', selo_verificado, 'nota_media', nota_media, 'total_avaliacoes', total_avaliacoes, 'total_servicos_executados', total_servicos_executados,
      'atende_remoto', atende_remoto, 'conselho', conselho, 'registro_profissional', registro_profissional, 'especialidades', to_jsonb(especialidades),
      'modalidades_atendimento', to_jsonb(modalidades_atendimento), 'tipo_pessoa', tipo_pessoa, 'video_url', video_url,
      'saude_score', saude_score, 'saude_cor', saude_cor, 'nivel', nivel, 'clientes_unicos', clientes_unicos,
      'tempo_resposta_mediano_min', tempo_resposta_mediano_min, 'taxa_resposta_90d', taxa_resposta_90d, 'novato', novato_protegido),
    'distancia_km', CASE WHEN distancia_km IS NULL THEN NULL ELSE round(distancia_km::numeric, 1) END, 'remoto', remoto,
    'patrocinado', (f_destaque > 0), 'abaixo_piso', abaixo_piso, 'score', score,
    'fatores', jsonb_build_object('fit', round(f_fit::numeric, 2), 'reputacao', round(f_reputacao::numeric, 2), 'saude', round(f_saude::numeric, 2), 'proximidade', round(f_proximidade::numeric, 2),
                                  'exploracao', round(f_exploracao::numeric, 2), 'preco', round(f_preco::numeric, 2), 'destaque', round(f_destaque::numeric, 2)))
  FROM final
  ORDER BY score DESC, nota_media DESC, prof_created_at DESC
  LIMIT (SELECT limite FROM f);
$marketye_buscar_interno$;
REVOKE ALL ON FUNCTION public.marketye_buscar_interno(jsonb) FROM PUBLIC, anon, authenticated;

-- Busca com relaxamento progressivo (RN-023): nunca "0 resultados" seco.
CREATE OR REPLACE FUNCTION public.marketye_buscar(p_filtros jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $marketye_buscar$
DECLARE
  f jsonb := COALESCE(p_filtros, '{}'::jsonb); v_res jsonb; v_n int; v_relax text[] := '{}'; v_tenant uuid := public.get_user_tenant_id();
  v_lat double precision; v_lng double precision; v_uf text; v_min int := 3; v_adj jsonb; v_cat uuid;
BEGIN
  -- Origem do endereço do cliente (9.2): a empresa do usuário, salvo se a tela mandou coordenadas.
  IF (f->>'lat') IS NULL AND v_tenant IS NOT NULL THEN
    SELECT latitude, longitude, estado INTO v_lat, v_lng, v_uf FROM public.empresa_cadastro WHERE tenant_id = v_tenant ORDER BY created_at LIMIT 1;
    IF v_lat IS NOT NULL AND v_lng IS NOT NULL THEN f := f || jsonb_build_object('lat', v_lat, 'lng', v_lng); END IF;
    IF (f->>'uf') IS NULL AND (f->>'ignorar_uf_padrao') IS NULL AND v_uf IS NOT NULL THEN f := f || jsonb_build_object('uf', v_uf, 'uf_padrao', true); END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  IF v_n < v_min AND (f->>'lat') IS NOT NULL THEN
    f := f || jsonb_build_object('raio_km', COALESCE(NULLIF(f->>'raio_km', '')::numeric, 100) * 3); v_relax := v_relax || 'raio';
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;
  IF v_n < v_min AND (f->>'cidade') IS NOT NULL THEN
    f := f - 'cidade'; v_relax := v_relax || 'cidade';
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;
  IF v_n < v_min AND (f->>'modalidade') IS NOT NULL THEN
    f := f - 'modalidade'; v_relax := v_relax || 'modalidade';
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;
  IF v_n < v_min AND (f->>'uf') IS NOT NULL THEN
    f := (f - 'uf') - 'lat' - 'lng'; v_relax := v_relax || 'uf';
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;
  IF v_n < v_min AND (f->>'nota_min') IS NOT NULL THEN
    f := f - 'nota_min'; v_relax := v_relax || 'nota_min';
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb), count(*) INTO v_res, v_n FROM public.marketye_buscar_interno(f) x;
  END IF;

  v_cat := NULLIF(f->>'categoria_id', '')::uuid;
  IF v_cat IS NULL AND (f->>'categoria_slug') IS NOT NULL THEN SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = f->>'categoria_slug' LIMIT 1; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'slug', c.slug)), '[]'::jsonb) INTO v_adj
  FROM public.marketplace_categorias c WHERE v_cat IS NOT NULL AND c.ativo AND c.id <> v_cat
    AND c.pai_id IS NOT DISTINCT FROM (SELECT pai_id FROM public.marketplace_categorias WHERE id = v_cat)
  LIMIT 6;

  RETURN jsonb_build_object('total', v_n, 'resultados', v_res, 'relaxamentos', to_jsonb(v_relax), 'filtros_aplicados', f,
                            'categorias_adjacentes', v_adj, 'oferta_insuficiente', v_n < v_min);
END $marketye_buscar$;
GRANT EXECUTE ON FUNCTION public.marketye_buscar(jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- 8) Demanda latente e vitrine pública (6.3, RN-034, CA-021)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_registrar_busca(p_categoria_id uuid, p_uf text, p_cidade text, p_termos text, p_resultados int,
                                                           p_avisar boolean DEFAULT false, p_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_registrar_busca$
DECLARE v_tenant uuid := public.get_user_tenant_id();
BEGIN
  IF v_tenant IS NULL THEN RETURN jsonb_build_object('registrado', false); END IF;
  INSERT INTO public.marketplace_demanda_latente (tenant_id, categoria_id, uf, cidade, termos, resultados, avisar, avisar_email)
  VALUES (v_tenant, p_categoria_id, NULLIF(upper(p_uf), ''), NULLIF(p_cidade, ''), left(p_termos, 200), COALESCE(p_resultados, 0), COALESCE(p_avisar, false), p_email)
  ON CONFLICT (tenant_id, categoria_id, uf, dia) DO UPDATE SET resultados = LEAST(public.marketplace_demanda_latente.resultados, EXCLUDED.resultados),
    avisar = public.marketplace_demanda_latente.avisar OR EXCLUDED.avisar, avisar_email = COALESCE(EXCLUDED.avisar_email, public.marketplace_demanda_latente.avisar_email),
    termos = COALESCE(EXCLUDED.termos, public.marketplace_demanda_latente.termos);
  RETURN jsonb_build_object('registrado', true);
END $marketye_registrar_busca$;
GRANT EXECUTE ON FUNCTION public.marketye_registrar_busca(uuid, text, text, text, int, boolean, text) TO authenticated;

-- Agregado anonimizado com célula mínima: nada abaixo do piso aparece.
CREATE OR REPLACE FUNCTION public.marketye_vagas_demanda(p_dias int DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_vagas_demanda$
  WITH cfg AS (SELECT COALESCE((public.marketye_config('demanda_latente')->>'piso_celula')::int, 5) AS piso,
                      COALESCE(p_dias, (public.marketye_config('demanda_latente')->>'janela_dias')::int, 30) AS dias)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('categoria', c.nome, 'categoria_slug', c.slug, 'uf', x.uf, 'empresas', x.empresas) ORDER BY x.empresas DESC), '[]'::jsonb)
  FROM (
    SELECT d.categoria_id, d.uf, count(DISTINCT d.tenant_id) AS empresas
    FROM public.marketplace_demanda_latente d, cfg
    WHERE d.dia >= CURRENT_DATE - cfg.dias AND d.resultados < 3
    GROUP BY d.categoria_id, d.uf
  ) x JOIN public.marketplace_categorias c ON c.id = x.categoria_id, cfg
  WHERE x.empresas >= cfg.piso;
$marketye_vagas_demanda$;
GRANT EXECUTE ON FUNCTION public.marketye_vagas_demanda(int) TO anon, authenticated;

-- Números da página de captação: faixas, nunca contagens exatas de clientes.
CREATE OR REPLACE FUNCTION public.marketye_vitrine_publica()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_vitrine_publica$
  SELECT jsonb_build_object(
    'empresas_faixa', (SELECT CASE WHEN n >= 100 THEN (floor(n / 100.0) * 100)::int::text || '+' ELSE 'dezenas de' END FROM (SELECT count(*) AS n FROM public.tenants WHERE ativo) t),
    'especialistas_ativos', (SELECT count(*) FROM public.marketplace_profissionais WHERE status = 'ativo' AND excluido_em IS NULL),
    'anuncios_publicados', (SELECT count(*) FROM public.marketplace_servicos WHERE status = 'publicado' AND ativo),
    'categorias', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'slug', c.slug, 'icone', c.icone, 'obrigacao_legal', to_jsonb(c.obrigacao_legal),
                                    'filhas', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome, 'slug', s.slug, 'obrigacao_legal', to_jsonb(s.obrigacao_legal), 'exige_registro', s.exige_registro) ORDER BY s.ordem), '[]'::jsonb)
                                               FROM public.marketplace_categorias s WHERE s.pai_id = c.id AND s.ativo)) ORDER BY c.ordem), '[]'::jsonb)
                   FROM public.marketplace_categorias c WHERE c.pai_id IS NULL AND c.ativo),
    'vagas_demanda', public.marketye_vagas_demanda(NULL),
    'termos_versoes', public.marketye_config('termos_versoes'));
$marketye_vitrine_publica$;
GRANT EXECUTE ON FUNCTION public.marketye_vitrine_publica() TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 9) Moderação, contestação e transparência (RF-018/028, RN-013/032/033)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_moderacao_fila(p_status text DEFAULT 'pendente')
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_moderacao_fila$
  SELECT CASE WHEN NOT public.is_superadmin(auth.uid()) THEN NULL ELSE COALESCE((
    SELECT jsonb_agg((to_jsonb(p) - 'user_id') || jsonb_build_object(
      'documentos', (SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.created_at), '[]'::jsonb) FROM public.marketplace_profissional_documentos d WHERE d.profissional_id = p.id),
      'consentimentos', (SELECT COALESCE(jsonb_agg(jsonb_build_object('tipo', c.tipo, 'versao', c.versao, 'aceito_em', c.aceito_em)), '[]'::jsonb) FROM public.marketplace_consentimentos c WHERE c.profissional_id = p.id),
      'anuncios', (SELECT count(*) FROM public.marketplace_servicos s WHERE s.profissional_id = p.id AND s.status <> 'removido'),
      'denuncias_abertas', (SELECT count(*) FROM public.marketplace_denuncias x WHERE x.profissional_id = p.id AND x.status IN ('aberta', 'em_analise')),
      'reputacao', (SELECT to_jsonb(r) FROM public.marketplace_reputacao r WHERE r.profissional_id = p.id)
    ) ORDER BY p.created_at)
    FROM public.marketplace_profissionais p WHERE p.status::text = COALESCE(p_status, 'pendente') AND p.excluido_em IS NULL), '[]'::jsonb) END;
$marketye_moderacao_fila$;
GRANT EXECUTE ON FUNCTION public.marketye_moderacao_fila(text) TO authenticated;

-- Aprovar/rejeitar cadastro. O selo comunica VERIFICAÇÃO DE DADOS, não garantia de qualidade (RN-026).
CREATE OR REPLACE FUNCTION public.marketye_moderar_especialista(p_id uuid, p_resultado text, p_motivo text DEFAULT NULL, p_selo boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_moderar_especialista$
DECLARE v_nome text;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_resultado NOT IN ('aprovado', 'rejeitado') THEN RAISE EXCEPTION 'Resultado inválido'; END IF;
  IF p_resultado = 'rejeitado' AND length(trim(COALESCE(p_motivo, ''))) < 5 THEN RAISE EXCEPTION 'Informe o motivo (o especialista pode contestar)'; END IF;
  UPDATE public.marketplace_profissionais SET
    status = CASE WHEN p_resultado = 'aprovado' THEN 'ativo'::public.marketplace_profissional_status ELSE 'bloqueado'::public.marketplace_profissional_status END,
    selo_verificado = (p_resultado = 'aprovado' AND COALESCE(p_selo, true)),
    moderacao_resultado = p_resultado, moderacao_motivo = p_motivo, moderado_por = auth.uid(), moderado_em = now()
  WHERE id = p_id RETURNING nome_completo INTO v_nome;
  IF v_nome IS NULL THEN RAISE EXCEPTION 'Especialista não encontrado'; END IF;
  INSERT INTO public.marketplace_reputacao (profissional_id) VALUES (p_id) ON CONFLICT (profissional_id) DO NOTHING;
  INSERT INTO public.marketplace_audit_log (tenant_id, profissional_id, acao, descricao, dados, usuario_id)
  VALUES ((SELECT tenant_id FROM public.marketplace_profissionais WHERE id = p_id), p_id, 'especialista_' || p_resultado, format('Especialista %s %s', v_nome, p_resultado), json_build_object('motivo', p_motivo, 'selo', p_selo), auth.uid());
  PERFORM public.marketye_recalcular_reputacao(p_id);
  RETURN jsonb_build_object('id', p_id, 'resultado', p_resultado);
END $marketye_moderar_especialista$;
GRANT EXECUTE ON FUNCTION public.marketye_moderar_especialista(uuid, text, text, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_especialista_situacao(p_id uuid, p_situacao text, p_motivo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_especialista_situacao$
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_situacao NOT IN ('ativo', 'suspenso', 'pendente') THEN RAISE EXCEPTION 'Situação inválida'; END IF;
  UPDATE public.marketplace_profissionais SET status = p_situacao::public.marketplace_profissional_status, moderacao_motivo = COALESCE(p_motivo, moderacao_motivo) WHERE id = p_id;
  INSERT INTO public.marketplace_audit_log (tenant_id, profissional_id, acao, descricao, dados, usuario_id)
  VALUES ((SELECT tenant_id FROM public.marketplace_profissionais WHERE id = p_id), p_id, 'especialista_' || p_situacao, COALESCE(p_motivo, 'Situação alterada pela moderação'), json_build_object('situacao', p_situacao), auth.uid());
  RETURN jsonb_build_object('id', p_id, 'status', p_situacao);
END $marketye_especialista_situacao$;
GRANT EXECUTE ON FUNCTION public.marketye_especialista_situacao(uuid, text, text) TO authenticated;

-- Decisão sobre denúncia: procedente vira OCORRÊNCIA (reflexo na visibilidade), nunca "punição".
CREATE OR REPLACE FUNCTION public.marketye_denuncia_decidir(p_id uuid, p_status text, p_acao text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_denuncia_decidir$
DECLARE d record;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_status NOT IN ('em_analise', 'procedente', 'improcedente', 'resolvida') THEN RAISE EXCEPTION 'Situação inválida'; END IF;
  UPDATE public.marketplace_denuncias SET status = p_status, acao_tomada = COALESCE(p_acao, acao_tomada), analisado_por = auth.uid(), analisado_em = now()
  WHERE id = p_id RETURNING * INTO d;
  IF d.id IS NULL THEN RAISE EXCEPTION 'Denúncia não encontrada'; END IF;
  IF p_status = 'procedente' THEN
    INSERT INTO public.marketplace_ocorrencias (profissional_id, tipo, descricao, origem_tipo, origem_id, registrado_por)
    VALUES (d.profissional_id, d.tipo, COALESCE(p_acao, d.descricao), 'denuncia', d.id, auth.uid());
    PERFORM public.marketye_recalcular_reputacao(d.profissional_id);
  END IF;
  RETURN jsonb_build_object('id', p_id, 'status', p_status);
END $marketye_denuncia_decidir$;
GRANT EXECUTE ON FUNCTION public.marketye_denuncia_decidir(uuid, text, text) TO authenticated;

-- Canal único de contestação (devido processo + LGPD art. 20).
CREATE OR REPLACE FUNCTION public.marketye_contestar(p_tipo text, p_referencia_id uuid, p_motivo text, p_evidencias jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_contestar$
DECLARE v_prof uuid := public.marketye_meu_id(); v_id uuid;
BEGIN
  IF v_prof IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF length(trim(COALESCE(p_motivo, ''))) < 10 THEN RAISE EXCEPTION 'Explique o motivo da contestação (mínimo 10 letras)'; END IF;
  IF EXISTS (SELECT 1 FROM public.marketplace_contestacoes WHERE profissional_id = v_prof AND decisao_tipo = p_tipo AND referencia_id IS NOT DISTINCT FROM p_referencia_id AND status IN ('aberta', 'em_analise')) THEN
    RAISE EXCEPTION 'Já existe uma contestação aberta sobre esta decisão';
  END IF;
  INSERT INTO public.marketplace_contestacoes (profissional_id, decisao_tipo, referencia_id, motivo, evidencias, trilha)
  VALUES (v_prof, p_tipo, p_referencia_id, trim(p_motivo), COALESCE(p_evidencias, '[]'::jsonb),
          jsonb_build_array(jsonb_build_object('evento', 'aberta', 'em', now(), 'por', 'especialista')))
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id, 'status', 'aberta');
END $marketye_contestar$;
GRANT EXECUTE ON FUNCTION public.marketye_contestar(text, uuid, text, jsonb) TO authenticated;

-- A decisão é sempre de uma pessoa (human-in-the-loop): a IA não fecha contestação.
CREATE OR REPLACE FUNCTION public.marketye_contestacao_decidir(p_id uuid, p_resultado text, p_resposta text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_contestacao_decidir$
DECLARE c record;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_resultado NOT IN ('em_analise', 'deferida', 'indeferida') THEN RAISE EXCEPTION 'Resultado inválido'; END IF;
  IF p_resultado <> 'em_analise' AND length(trim(COALESCE(p_resposta, ''))) < 10 THEN RAISE EXCEPTION 'Escreva a resposta ao especialista (trilha de evidência)'; END IF;
  UPDATE public.marketplace_contestacoes SET status = p_resultado, resposta = COALESCE(p_resposta, resposta),
    analisado_por = CASE WHEN p_resultado <> 'em_analise' THEN auth.uid() END, analisado_em = CASE WHEN p_resultado <> 'em_analise' THEN now() END,
    trilha = trilha || jsonb_build_object('evento', p_resultado, 'em', now(), 'por', 'moderador', 'resposta', p_resposta)
  WHERE id = p_id RETURNING * INTO c;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Contestação não encontrada'; END IF;
  IF p_resultado = 'deferida' THEN
    IF c.decisao_tipo = 'rejeicao_cadastro' THEN
      UPDATE public.marketplace_profissionais SET status = 'pendente', moderacao_resultado = NULL, moderacao_motivo = NULL WHERE id = c.profissional_id;
    ELSIF c.decisao_tipo = 'suspensao' THEN
      UPDATE public.marketplace_profissionais SET status = 'ativo' WHERE id = c.profissional_id AND status = 'suspenso';
    ELSIF c.decisao_tipo = 'remocao_anuncio' AND c.referencia_id IS NOT NULL THEN
      UPDATE public.marketplace_servicos SET status = 'pausado', ativo = true WHERE id = c.referencia_id AND profissional_id = c.profissional_id;
    ELSIF c.decisao_tipo = 'reflexo_visibilidade' AND c.referencia_id IS NOT NULL THEN
      UPDATE public.marketplace_ocorrencias SET reflexo_visibilidade = false WHERE id = c.referencia_id AND profissional_id = c.profissional_id;
      PERFORM public.marketye_recalcular_reputacao(c.profissional_id);
    ELSIF c.decisao_tipo = 'avaliacao' AND c.referencia_id IS NOT NULL THEN
      UPDATE public.marketplace_avaliacoes SET moderada = true, moderacao_motivo = p_resposta WHERE id = c.referencia_id AND profissional_id = c.profissional_id;
      PERFORM public.marketye_recalcular_reputacao(c.profissional_id);
    END IF;
  END IF;
  INSERT INTO public.marketplace_audit_log (tenant_id, profissional_id, acao, descricao, dados, usuario_id)
  VALUES ((SELECT tenant_id FROM public.marketplace_profissionais WHERE id = c.profissional_id), c.profissional_id, 'contestacao_' || p_resultado, left(p_resposta, 500), json_build_object('contestacao_id', c.id, 'tipo', c.decisao_tipo), auth.uid());
  RETURN jsonb_build_object('id', p_id, 'status', p_resultado);
END $marketye_contestacao_decidir$;
GRANT EXECUTE ON FUNCTION public.marketye_contestacao_decidir(uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.marketye_contestacoes_fila()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_contestacoes_fila$
  SELECT CASE WHEN NOT public.is_superadmin(auth.uid()) THEN NULL ELSE COALESCE((
    SELECT jsonb_agg(to_jsonb(c) || jsonb_build_object('especialista', p.nome_completo, 'especialista_status', p.status) ORDER BY (c.status IN ('aberta', 'em_analise')) DESC, c.created_at)
    FROM public.marketplace_contestacoes c JOIN public.marketplace_profissionais p ON p.id = c.profissional_id), '[]'::jsonb) END;
$marketye_contestacoes_fila$;
GRANT EXECUTE ON FUNCTION public.marketye_contestacoes_fila() TO authenticated;

-- Destaque pago (camada rotulada). Só acima do piso e dentro do teto por categoria.
CREATE OR REPLACE FUNCTION public.marketye_destaque_criar(p_profissional_id uuid, p_servico_id uuid, p_tipo text, p_categoria_id uuid, p_uf text,
                                                          p_inicio date, p_fim date, p_valor numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_destaque_criar$
DECLARE v_cfg jsonb := COALESCE(public.marketye_config('destaque'), '{"teto_slots_por_categoria":2,"exige_acima_do_piso":true}'::jsonb); v_id uuid; v_abaixo boolean; v_slots int;
BEGIN
  IF NOT public.is_superadmin(auth.uid()) THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF p_tipo NOT IN ('categoria', 'regiao', 'topo') THEN RAISE EXCEPTION 'Tipo de destaque inválido'; END IF;
  IF p_fim < COALESCE(p_inicio, CURRENT_DATE) THEN RAISE EXCEPTION 'Período inválido'; END IF;
  SELECT COALESCE(abaixo_piso, false) INTO v_abaixo FROM public.marketplace_reputacao WHERE profissional_id = p_profissional_id;
  IF COALESCE((v_cfg->>'exige_acima_do_piso')::boolean, true) AND COALESCE(v_abaixo, false) THEN
    RAISE EXCEPTION 'Melhore sua nota para ativar destaques.';
  END IF;
  IF p_tipo = 'categoria' THEN
    SELECT count(*) INTO v_slots FROM public.marketplace_destaques WHERE tipo = 'categoria' AND categoria_id = p_categoria_id AND ativo AND fim >= COALESCE(p_inicio, CURRENT_DATE) AND inicio <= p_fim;
    IF v_slots >= COALESCE((v_cfg->>'teto_slots_por_categoria')::int, 2) THEN RAISE EXCEPTION 'Teto de destaques desta categoria atingido no período.'; END IF;
  END IF;
  INSERT INTO public.marketplace_destaques (profissional_id, servico_id, tipo, categoria_id, uf, inicio, fim, valor, criado_por)
  VALUES (p_profissional_id, p_servico_id, p_tipo, p_categoria_id, NULLIF(upper(p_uf), ''), COALESCE(p_inicio, CURRENT_DATE), p_fim, p_valor, auth.uid()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('id', v_id);
END $marketye_destaque_criar$;
GRANT EXECUTE ON FUNCTION public.marketye_destaque_criar(uuid, uuid, text, uuid, text, date, date, numeric) TO authenticated;

-- Relatório anual de transparência (RN-032).
CREATE OR REPLACE FUNCTION public.marketye_transparencia(p_ano int DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_transparencia$
  WITH a AS (SELECT COALESCE(p_ano, EXTRACT(YEAR FROM now())::int) AS ano)
  SELECT CASE WHEN NOT public.is_superadmin(auth.uid()) THEN NULL ELSE jsonb_build_object(
    'ano', a.ano,
    'denuncias_recebidas', (SELECT count(*) FROM public.marketplace_denuncias d WHERE EXTRACT(YEAR FROM d.created_at) = a.ano),
    'denuncias_procedentes', (SELECT count(*) FROM public.marketplace_denuncias d WHERE EXTRACT(YEAR FROM d.created_at) = a.ano AND d.status = 'procedente'),
    'cadastros_rejeitados', (SELECT count(*) FROM public.marketplace_profissionais p WHERE EXTRACT(YEAR FROM p.moderado_em) = a.ano AND p.moderacao_resultado = 'rejeitado'),
    'cadastros_aprovados', (SELECT count(*) FROM public.marketplace_profissionais p WHERE EXTRACT(YEAR FROM p.moderado_em) = a.ano AND p.moderacao_resultado = 'aprovado'),
    'anuncios_publicados', (SELECT count(*) FROM public.marketplace_servicos s WHERE EXTRACT(YEAR FROM s.publicado_em) = a.ano),
    'impulsionamentos', (SELECT count(*) FROM public.marketplace_destaques d WHERE EXTRACT(YEAR FROM d.created_at) = a.ano),
    'contestacoes', (SELECT jsonb_build_object('abertas', count(*) FILTER (WHERE status IN ('aberta','em_analise')), 'deferidas', count(*) FILTER (WHERE status = 'deferida'), 'indeferidas', count(*) FILTER (WHERE status = 'indeferida'))
                     FROM public.marketplace_contestacoes c WHERE EXTRACT(YEAR FROM c.created_at) = a.ano),
    'exclusoes_lgpd', (SELECT count(*) FROM public.marketplace_profissionais p WHERE EXTRACT(YEAR FROM p.excluido_em) = a.ano)
  ) END FROM a;
$marketye_transparencia$;
GRANT EXECUTE ON FUNCTION public.marketye_transparencia(int) TO authenticated;

-- ---------------------------------------------------------------------
-- 10) LGPD do não-usuário (RF-021, RN-019, CA-014)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_exportar_meus_dados()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_exportar_meus_dados$
  SELECT jsonb_build_object(
    'perfil', (SELECT to_jsonb(p) - 'user_id' FROM public.marketplace_profissionais p WHERE p.id = public.marketye_meu_id()),
    'anuncios', (SELECT COALESCE(jsonb_agg(to_jsonb(s)), '[]'::jsonb) FROM public.marketplace_servicos s WHERE s.profissional_id = public.marketye_meu_id()),
    'leads', (SELECT COALESCE(jsonb_agg(to_jsonb(l) - 'criado_por'), '[]'::jsonb) FROM public.marketplace_leads l WHERE l.profissional_id = public.marketye_meu_id()),
    'avaliacoes', (SELECT COALESCE(jsonb_agg(to_jsonb(a) - 'avaliador_id'), '[]'::jsonb) FROM public.marketplace_avaliacoes a WHERE a.profissional_id = public.marketye_meu_id()),
    'consentimentos', (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]'::jsonb) FROM public.marketplace_consentimentos c WHERE c.profissional_id = public.marketye_meu_id()),
    'contestacoes', (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]'::jsonb) FROM public.marketplace_contestacoes c WHERE c.profissional_id = public.marketye_meu_id()),
    'autonomia', (SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]'::jsonb) FROM public.marketplace_autonomia_eventos e WHERE e.profissional_id = public.marketye_meu_id()),
    'exportado_em', now());
$marketye_exportar_meus_dados$;
GRANT EXECUTE ON FUNCTION public.marketye_exportar_meus_dados() TO authenticated;

-- Sai da vitrine e anonimiza o perfil; leads, avaliações e contratações
-- ficam pelo prazo legal (sem o nome). Os prazos por tipo aguardam advogado.
CREATE OR REPLACE FUNCTION public.marketye_excluir_meu_perfil(p_confirmacao text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $marketye_excluir_meu_perfil$
DECLARE v_id uuid := public.marketye_meu_id();
BEGIN
  IF v_id IS NULL THEN RAISE EXCEPTION 'Sem cadastro de especialista'; END IF;
  IF COALESCE(p_confirmacao, '') <> 'EXCLUIR' THEN RAISE EXCEPTION 'Digite EXCLUIR para confirmar'; END IF;
  UPDATE public.marketplace_servicos SET status = 'removido', ativo = false WHERE profissional_id = v_id;
  UPDATE public.marketplace_cupons SET ativo = false WHERE profissional_id = v_id;
  UPDATE public.marketplace_destaques SET ativo = false WHERE profissional_id = v_id;
  INSERT INTO public.marketplace_consentimentos (profissional_id, tipo, versao, origem) VALUES (v_id, 'revogacao_exclusao', 'lgpd', 'portal');
  UPDATE public.marketplace_profissionais SET
    status = 'bloqueado', excluido_em = now(), nome_completo = 'Especialista removido', email = 'removido+' || v_id::text || '@anonimizado.invalid',
    telefone = NULL, cpf_cnpj = NULL, foto_url = NULL, bio = NULL, formacao_academica = NULL, registro_profissional = NULL, certificacoes = NULL,
    especialidades = NULL, areas_atuacao = NULL, latitude = NULL, longitude = NULL, site_url = NULL, video_url = NULL, disponibilidade = '{}'::jsonb,
    politicas = NULL, link_afiliado = NULL, user_id = NULL
  WHERE id = v_id;
  INSERT INTO public.marketplace_audit_log (tenant_id, profissional_id, acao, descricao, usuario_id)
  VALUES ((SELECT tenant_id FROM public.marketplace_profissionais WHERE id = v_id), v_id, 'exclusao_lgpd', 'Perfil removido a pedido do titular; transações retidas pelo prazo legal', auth.uid());
  RETURN jsonb_build_object('id', v_id, 'excluido', true);
END $marketye_excluir_meu_perfil$;
GRANT EXECUTE ON FUNCTION public.marketye_excluir_meu_perfil(text) TO authenticated;

-- ---------------------------------------------------------------------
-- 11) Painel de liquidez (RF-019, 2.4, 23)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketye_painel_liquidez()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $marketye_painel_liquidez$
  SELECT CASE WHEN NOT public.is_superadmin(auth.uid()) THEN NULL ELSE jsonb_build_object(
    'especialistas', jsonb_build_object(
      'ativos', (SELECT count(*) FROM public.marketplace_profissionais WHERE status = 'ativo' AND excluido_em IS NULL),
      'pendentes', (SELECT count(*) FROM public.marketplace_profissionais WHERE status = 'pendente' AND excluido_em IS NULL),
      'novos_30d', (SELECT count(*) FROM public.marketplace_profissionais WHERE created_at >= now() - interval '30 days'),
      'excluidos_30d', (SELECT count(*) FROM public.marketplace_profissionais WHERE excluido_em >= now() - interval '30 days')),
    'anuncios_publicados', (SELECT count(*) FROM public.marketplace_servicos WHERE status = 'publicado' AND ativo),
    'densidade', (SELECT COALESCE(jsonb_agg(jsonb_build_object('categoria', categoria, 'uf', uf, 'especialistas', n) ORDER BY n DESC), '[]'::jsonb) FROM (
        SELECT COALESCE(cr.nome, c.nome) AS categoria, p.estado AS uf, count(DISTINCT p.id) AS n
        FROM public.marketplace_servicos s JOIN public.marketplace_profissionais p ON p.id = s.profissional_id
        LEFT JOIN public.marketplace_categorias c ON c.id = s.categoria_id LEFT JOIN public.marketplace_categorias cr ON cr.id = c.pai_id
        WHERE s.status = 'publicado' AND s.ativo AND p.status = 'ativo' GROUP BY 1, 2) d),
    'cobertura', (SELECT jsonb_build_object('celulas_total', count(*), 'celulas_densas', count(*) FILTER (WHERE n >= 3)) FROM (
        SELECT count(DISTINCT p.id) AS n FROM public.marketplace_servicos s JOIN public.marketplace_profissionais p ON p.id = s.profissional_id
        WHERE s.status = 'publicado' AND s.ativo AND p.status = 'ativo' GROUP BY s.categoria_id, p.estado) x),
    'leads', jsonb_build_object(
      'abertos_30d', (SELECT count(*) FROM public.marketplace_leads WHERE created_at >= now() - interval '30 days'),
      'respondidos_30d', (SELECT count(*) FROM public.marketplace_leads WHERE created_at >= now() - interval '30 days' AND primeira_resposta_em IS NOT NULL),
      'ganhos_30d', (SELECT count(*) FROM public.marketplace_leads WHERE created_at >= now() - interval '30 days' AND status = 'ganho'),
      'tempo_resposta_mediano_min', (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (primeira_resposta_em - created_at)) / 60)
                                     FROM public.marketplace_leads WHERE primeira_resposta_em IS NOT NULL AND created_at >= now() - interval '90 days')),
    'demanda_latente', (SELECT COALESCE(jsonb_agg(jsonb_build_object('categoria', c.nome, 'uf', d.uf, 'empresas', d.n, 'avisar', d.avisar) ORDER BY d.n DESC), '[]'::jsonb) FROM (
        SELECT categoria_id, uf, count(DISTINCT tenant_id) AS n, bool_or(avisar) AS avisar FROM public.marketplace_demanda_latente
        WHERE dia >= CURRENT_DATE - 30 AND resultados < 3 GROUP BY categoria_id, uf) d JOIN public.marketplace_categorias c ON c.id = d.categoria_id),
    'tempo_ate_primeira_venda_dias', (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (x.primeira - p.created_at)) / 86400)::numeric, 1)
        FROM public.marketplace_profissionais p JOIN (SELECT profissional_id, min(ganho_em) AS primeira FROM public.marketplace_leads WHERE status = 'ganho' GROUP BY 1) x ON x.profissional_id = p.id),
    'contestacoes_abertas', (SELECT count(*) FROM public.marketplace_contestacoes WHERE status IN ('aberta', 'em_analise')),
    'gerado_em', now()) END;
$marketye_painel_liquidez$;
GRANT EXECUTE ON FUNCTION public.marketye_painel_liquidez() TO authenticated;

-- Reputação inicial para quem já estava ativo antes desta onda.
INSERT INTO public.marketplace_reputacao (profissional_id)
SELECT id FROM public.marketplace_profissionais p WHERE NOT EXISTS (SELECT 1 FROM public.marketplace_reputacao r WHERE r.profissional_id = p.id)
ON CONFLICT (profissional_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- 3) QA: casos MKY-* e rotinas
-- ---------------------------------------------------------------------
-- =====================================================================
-- MARKETYE · QA: CASOS DOCUMENTADOS (MKY-*) E ROTINAS SOMENTE-LEITURA
--
-- A Documentação de testes é a fonte da verdade: cada regra sensível do
-- MarketYE vira um caso; os de nível 'api' ganham rotina qa_caso_mky_*()
-- (executadas por qa_rodar_bateria('manual','rede-parceiros'), sempre em
-- transação descartada); os de nível 'e2e' vivem no Cypress
-- (cypress/e2e/marketye.cy.ts) ligados pela ponte qa_cobertura_e2e.
--
-- O módulo de QA 'rede-parceiros' passa a se chamar MarketYE (o path fica,
-- porque está gravado nos casos PARC-* e nos filhos programa-parceiros).
-- Os casos PARC-001/002/004/024 ganham texto coerente com o comportamento
-- novo (cadastro nasce pendente; rejeição por moderação; avaliação só com
-- transação verificada).
--
-- Idempotente: casos com ON CONFLICT (codigo) DO UPDATE, rotinas com
-- CREATE OR REPLACE, ponte com ON CONFLICT DO NOTHING.
-- =====================================================================


UPDATE public.qa_modulos SET label = 'MarketYE', icone = '🏪' WHERE path = 'rede-parceiros' AND label <> 'MarketYE';

-- Trava do cercado do QA nas tabelas novas com tenant_id que as rotinas tocam.
-- marketplace_demanda_latente fica de fora de propósito: só guarda contadores
-- (empresa × categoria × UF × dia), sem dado pessoal, e a rotina MKY-005
-- precisa de cinco empresas distintas para provar a célula mínima.
DO $cerca$
DECLARE t text;
BEGIN
  IF to_regprocedure('public.qa_bloqueia_fora_do_cercado()') IS NULL THEN RETURN; END IF;
  FOREACH t IN ARRAY ARRAY['marketplace_leads'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'qa_guarda_cercado' AND tgrelid = ('public.' || t)::regclass AND NOT tgisinternal) THEN
      EXECUTE format('CREATE TRIGGER qa_guarda_cercado BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.qa_bloqueia_fora_do_cercado()', t);
    END IF;
    INSERT INTO public.qa_tabelas_protegidas (tabela, motivo) VALUES (t, 'MarketYE: tabela tem tenant_id') ON CONFLICT (tabela) DO NOTHING;
  END LOOP;
END $cerca$;

-- ---------------------------------------------------------------------
-- 1) Casos documentados
-- ---------------------------------------------------------------------
DO $qa$
DECLARE v_mod uuid;
BEGIN
  SELECT id INTO v_mod FROM public.qa_modulos WHERE path = 'rede-parceiros';
  IF v_mod IS NULL THEN RETURN; END IF;

  INSERT INTO public.qa_casos_teste (modulo_id, codigo, titulo, tipo, prioridade, status, nivel, base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes) VALUES
  (v_mod, 'MKY-001', 'Cadastro do especialista nasce pendente, com consentimento versionado; cadastro direto pela tabela também nasce pendente',
   'feliz', 'critica', 'aprovado', 'api', 'LGPD art. 7º/8º (consentimento); RN-001, RN-012, RN-018, RN-021',
   'Todo cadastro — por função ou por INSERT direto — entra como pendente, sem selo, e registra as três versões de termos aceitas.',
   'Versões de termos em marketplace_config (chave termos_versoes).',
   '[{"ordem":1,"acao":"Cadastrar especialista pela função com CPF fictício válido e aceite dos termos","resultado_esperado":"status pendente, selo false, 3 consentimentos, linha de reputação criada"},
     {"ordem":2,"acao":"Repetir o cadastro com o mesmo CPF em outra conta","resultado_esperado":"recusado: CPF/CNPJ já possui cadastro"},
     {"ordem":3,"acao":"Como usuário autenticado, inserir direto na tabela com status ativo e selo true","resultado_esperado":"a guarda rebaixa para pendente e selo false"}]'::jsonb,
   'Ninguém entra na vitrine sem passar pela verificação; consentimento fica registrado por versão.',
   'A rotina cria contas fictícias (@sandbox.invalid) e apaga tudo; roda em transação descartada.'),
  (v_mod, 'MKY-002', 'Perfil global: pendente não aparece na busca; aprovado aparece para empresas distintas; rascunho de anúncio não aparece',
   'feliz', 'critica', 'aprovado', 'api', 'RN-002, RN-011, RN-013; CA-003',
   'A vitrine é global (cross-tenant) e só mostra especialista ativo com anúncio publicado.',
   'Cercado qa-sandbox e uma segunda empresa sintética.',
   '[{"ordem":1,"acao":"Especialista pendente com anúncio salvo (rascunho)","resultado_esperado":"busca por nome não encontra"},
     {"ordem":2,"acao":"Publicar antes da aprovação","resultado_esperado":"recusado: cadastro em verificação"},
     {"ordem":3,"acao":"Superadmin aprova; especialista publica","resultado_esperado":"busca encontra a partir de duas empresas diferentes, com selo e nível"}]'::jsonb,
   'Mesmo anúncio visível para qualquer empresa cliente; nada vaza antes da verificação.',
   'Simula claims de superadmin, do especialista e de usuários de duas empresas.'),
  (v_mod, 'MKY-003', 'Avaliação só com transação verificada (lead ganho), nos dois sentidos, com recálculo da reputação',
   'negativo', 'critica', 'aprovado', 'api', 'RN-004, RN-005, RN-022; CA-007; CDC art. 6º (informação)',
   'Sem lead ganho ou contratação concluída ninguém avalia; depois, cliente e especialista avaliam uma vez cada e a nota média é recalculada.',
   'Especialista ativo com anúncio publicado.',
   '[{"ordem":1,"acao":"Empresa abre lead; tenta avaliar","resultado_esperado":"recusado: avaliações ficam disponíveis após o atendimento"},
     {"ordem":2,"acao":"Especialista responde; empresa marca serviço combinado (ganho); avalia","resultado_esperado":"aceita; nota_media e total_avaliacoes do especialista atualizados"},
     {"ordem":3,"acao":"Empresa avalia de novo o mesmo lead","resultado_esperado":"recusado: já avaliado"},
     {"ordem":4,"acao":"Especialista avalia a empresa","resultado_esperado":"aceita na direção especialista→cliente"}]'::jsonb,
   'Avaliação atrelada a transação real, bidirecional, uma por lado.', NULL),
  (v_mod, 'MKY-004', 'Piso de nota rebaixa a visibilidade orgânica e o destaque pago não ultrapassa quem está abaixo do piso',
   'negativo', 'alta', 'aprovado', 'api', 'RN-006, RN-007; CA-005, CA-010; CDC arts. 36-38 (publicidade)',
   'Um especialista com destaque ativo mas nota abaixo do piso fica atrás do bem avaliado e não recebe o rótulo Patrocinado.',
   'Config piso_nota vigente.',
   '[{"ordem":1,"acao":"Dois especialistas na mesma categoria/UF: A com três notas 2 e destaque topo; B com três notas 5","resultado_esperado":"recalcular marca A abaixo do piso"},
     {"ordem":2,"acao":"Buscar pela categoria","resultado_esperado":"B vem antes de A; A sem patrocinado; A.abaixo_piso = true"}]'::jsonb,
   'Orgânico é meritocrático; pago é aditivo e nunca contorna o piso.', NULL),
  (v_mod, 'MKY-005', 'Vagas de demanda: célula abaixo do piso mínimo não aparece no agregado público',
   'negativo', 'alta', 'aprovado', 'api', 'LGPD (minimização/anonimização); RN-034; CA-021',
   'O agregado público só mostra uma célula categoria×UF quando pelo menos N empresas distintas buscaram sem oferta.',
   'Config demanda_latente.piso_celula = 5.',
   '[{"ordem":1,"acao":"Registrar 4 empresas distintas sem oferta para a mesma categoria/UF sintética","resultado_esperado":"a célula não aparece"},
     {"ordem":2,"acao":"Registrar a 5ª empresa","resultado_esperado":"a célula aparece com empresas = 5"}]'::jsonb,
   'Nenhuma contagem pequena que reidentifique uma empresa.', NULL),
  (v_mod, 'MKY-006', 'Contato mascarado nas mensagens até a empresa liberar; contato direto só sai pela função depois da liberação',
   'feliz', 'alta', 'aprovado', 'api', 'RN-020; LGPD (finalidade)',
   'Telefones, e-mails e links são ocultados nas mensagens enquanto o contato não for liberado; depois passam limpos e a função de contato devolve o e-mail.',
   'Lead aberto entre empresa e especialista.',
   '[{"ordem":1,"acao":"Empresa escreve mensagem com telefone e e-mail","resultado_esperado":"texto gravado com os trechos ocultos e sinal de saída marcado"},
     {"ordem":2,"acao":"Especialista pede o contato","resultado_esperado":"liberado = false"},
     {"ordem":3,"acao":"Empresa libera o contato e escreve de novo","resultado_esperado":"mensagem sem máscara; contato devolve o e-mail"}]'::jsonb,
   'Mascaramento proporcional: até o primeiro contato qualificado, sem penalização.', NULL),
  (v_mod, 'MKY-007', 'Léxico não-disciplinar no schema: nada se chama infração, punição, sanção ou demoção',
   'negativo', 'media', 'aprovado', 'api', 'CLT arts. 2º-3º (subordinação); RN-028; CA-018',
   'Auditoria de catálogo: tabelas, colunas, funções e valores de check do módulo não usam vocabulário disciplinar.',
   NULL,
   '[{"ordem":1,"acao":"Varrer information_schema e pg_proc pelos prefixos marketplace_ e marketye_","resultado_esperado":"nenhum nome com infrac, punic, sanc, democ ou penal"}]'::jsonb,
   'Ocorrência, reflexo na visibilidade e ajuste de nível são os únicos termos.', 'Somente leitura.'),
  (v_mod, 'MKY-008', 'Contestação por canal único: só uma pessoa (superadmin) decide, com trilha de evidência',
   'feliz', 'critica', 'aprovado', 'api', 'Marco Civil art. 19 (STF, Temas 987/533 — devido processo); LGPD art. 20; RN-032, RN-033; CA-020',
   'Cadastro rejeitado pode ser contestado; usuário comum não decide; superadmin defere e o cadastro volta a pendente com a trilha registrada.',
   NULL,
   '[{"ordem":1,"acao":"Superadmin rejeita o cadastro com motivo","resultado_esperado":"status bloqueado, moderacao_resultado rejeitado"},
     {"ordem":2,"acao":"Especialista contesta","resultado_esperado":"contestação aberta com trilha"},
     {"ordem":3,"acao":"Usuário de empresa tenta decidir","resultado_esperado":"acesso negado"},
     {"ordem":4,"acao":"Superadmin defere com resposta","resultado_esperado":"status pendente; trilha com dois eventos; resposta gravada"}]'::jsonb,
   'Human-in-the-loop obrigatório; a IA nunca fecha contestação.', NULL),
  (v_mod, 'MKY-009', 'Exclusão LGPD: perfil sai da vitrine e é anonimizado; leads e avaliações ficam pelo prazo legal',
   'feliz', 'alta', 'aprovado', 'api', 'LGPD arts. 16 e 18; RN-019; CA-014',
   'O titular exclui o próprio perfil: nome, e-mail, documento e foto anonimizados, anúncios removidos, transações retidas.',
   'Especialista com lead ganho e avaliação.',
   '[{"ordem":1,"acao":"Especialista chama a exclusão com a confirmação","resultado_esperado":"status bloqueado, excluido_em preenchido, PII anonimizada"},
     {"ordem":2,"acao":"Buscar pelo nome antigo","resultado_esperado":"nada encontrado"},
     {"ordem":3,"acao":"Conferir lead e avaliação","resultado_esperado":"continuam existindo, ligados ao id"}]'::jsonb,
   'Direito de exclusão atendido sem apagar a trilha transacional.', NULL),
  (v_mod, 'MKY-010', 'Ajuste de nível só depois de aviso e período de recuperação, e nunca bloqueia publicar',
   'alternativo', 'alta', 'aprovado', 'api', 'RN-010, RN-029; CA-009, CA-019; subordinação algorítmica (STF Temas 1291/1389 pendentes)',
   'Quem está em nível superior às métricas recebe aviso; só após o amortecedor o nível é ajustado; publicar continua permitido.',
   'Config niveis.amortecedor_dias = 14.',
   '[{"ordem":1,"acao":"Especialista prata sem métricas; recalcular","resultado_esperado":"continua prata, com aviso registrado"},
     {"ordem":2,"acao":"Envelhecer o aviso além do amortecedor; recalcular","resultado_esperado":"nível ajustado para novo"},
     {"ordem":3,"acao":"Publicar um anúncio","resultado_esperado":"publicado normalmente"}]'::jsonb,
   'Ajuste de nível é reflexo reputacional, não sanção.', NULL),
  (v_mod, 'MKY-011', 'Trilha de autonomia: definir e alterar preço gera eventos auditáveis',
   'feliz', 'media', 'aprovado', 'api', 'CLT arts. 2º-3º; RN-003, RN-031; CA-022',
   'Toda definição de preço/política do prestador fica registrada como evento com valor anterior e novo.',
   NULL,
   '[{"ordem":1,"acao":"Salvar anúncio com preço 300","resultado_esperado":"1 evento anuncio_preco_politica"},
     {"ordem":2,"acao":"Alterar para 350","resultado_esperado":"2º evento com anterior 300 e novo 350"}]'::jsonb,
   'Prova de que o preço é do prestador.', NULL),
  (v_mod, 'MKY-012', 'Leitura direta da tabela não expõe e-mail, telefone, CPF/CNPJ nem quem avaliou; admin de empresa não gerencia especialistas',
   'negativo', 'critica', 'aprovado', 'api', 'LGPD (minimização); RN-020; incidente prévio de exposição (25)',
   'Auditoria de privilégios: o papel authenticated não tem SELECT nas colunas de contato do especialista nem no avaliador_id; a política antiga de admin por empresa não existe mais.',
   NULL,
   '[{"ordem":1,"acao":"Conferir column_privileges de authenticated em marketplace_profissionais e marketplace_avaliacoes","resultado_esperado":"sem email, telefone, cpf_cnpj, user_id, tenant_id, avaliador_id"},
     {"ordem":2,"acao":"Conferir pg_policies","resultado_esperado":"política Admins manage all professionals ausente; superadmin presente"}]'::jsonb,
   'Contato só pelo lead liberado; moderação só da casa.', 'Somente leitura.'),
  (v_mod, 'MKY-013', 'Guarda RN-021: status/selo não mudam por UPDATE direto de usuário autenticado; mudam pela função de moderação',
   'negativo', 'critica', 'aprovado', 'api', 'RN-021; CA-013; classe de vulnerabilidade da assinatura por anônimo',
   'Um UPDATE direto de status pelo próprio especialista é recusado; a função de moderação (superadmin) muda.',
   NULL,
   '[{"ordem":1,"acao":"Como o especialista (papel authenticated), UPDATE status = ativo","resultado_esperado":"recusado pela guarda"},
     {"ordem":2,"acao":"Superadmin aprova pela função","resultado_esperado":"status ativo, selo verificado"}]'::jsonb,
   'Escrita sensível só por função.', NULL),
  (v_mod, 'MKY-020', 'Cabeçalho: botão MarketYE abre a vitrine do marketplace de serviços', 'feliz', 'alta', 'aprovado', 'e2e', 'RN-002; 0.5 (nomenclatura)',
   'O botão global do cabeçalho passa a se chamar MarketYE e abre a vitrine com o título MarketYE e os filtros.',
   'Conta-robô logada no ambiente de teste.',
   '[{"ordem":1,"acao":"Entrar e localizar o botão MarketYE no cabeçalho","resultado_esperado":"botão existe com o texto MarketYE"},
     {"ordem":2,"acao":"Abrir /marketplace","resultado_esperado":"título MarketYE, campo de busca e filtros visíveis"}]'::jsonb,
   'Nada mais se chama Rede de Parceiros.', 'Cypress: cypress/e2e/marketye.cy.ts'),
  (v_mod, 'MKY-021', 'Vitrine: filtrar por categoria lista anúncios; busca sem oferta oferece alternativas em vez de vazio', 'feliz', 'alta', 'aprovado', 'e2e', 'RN-023; CA-004',
   'Com a categoria Segurança do Trabalho a vitrine lista o anúncio do especialista de teste; um termo inexistente mostra o aviso de oferta insuficiente com o botão de aviso.',
   'Fixture "Especialista Staging (QA)" com anúncio publicado (ilha de teste).',
   '[{"ordem":1,"acao":"Selecionar a categoria Segurança do Trabalho","resultado_esperado":"ao menos um card de anúncio"},
     {"ordem":2,"acao":"Buscar um termo sem oferta","resultado_esperado":"aviso de oferta insuficiente e opção Avise-me"}]'::jsonb,
   'Busca nunca devolve vazio seco.', 'Cypress: cypress/e2e/marketye.cy.ts'),
  (v_mod, 'MKY-022', 'Página pública MarketYE: proposta ao especialista, vagas de demanda e caminho para o cadastro', 'feliz', 'media', 'aprovado', 'e2e', 'RN-001; 6.3',
   'A página /marketye abre sem login, mostra a proposta de valor e leva ao formulário de cadastro.',
   NULL,
   '[{"ordem":1,"acao":"Abrir /marketye sem sessão","resultado_esperado":"título com MarketYE e botão de cadastro"},
     {"ordem":2,"acao":"Clicar em cadastrar","resultado_esperado":"formulário /marketye/cadastro com campos de nome, e-mail e CPF/CNPJ"}]'::jsonb,
   'Captação pública do lado da oferta.', 'Cypress: cypress/e2e/marketye.cy.ts')
  ON CONFLICT (codigo) DO UPDATE SET titulo = EXCLUDED.titulo, tipo = EXCLUDED.tipo, prioridade = EXCLUDED.prioridade, nivel = EXCLUDED.nivel,
    base_legal = EXCLUDED.base_legal, objetivo = EXCLUDED.objetivo, pre_condicoes = EXCLUDED.pre_condicoes, passos = EXCLUDED.passos,
    resultado_esperado = EXCLUDED.resultado_esperado, observacoes = EXCLUDED.observacoes;

  -- Casos antigos que descreviam o comportamento anterior.
  UPDATE public.qa_casos_teste SET
    titulo = 'Cadastrar-se como especialista (com documentos e selfie): nasce pendente até a verificação',
    resultado_esperado = 'Cadastro salvo como pendente, sem selo; aparece na fila de moderação do MarketYE.'
  WHERE codigo = 'PARC-001';
  UPDATE public.qa_casos_teste SET titulo = 'Perfil pendente não aparece no MarketYE antes da verificação' WHERE codigo = 'PARC-002';
  UPDATE public.qa_casos_teste SET
    titulo = 'Moderação: superadmin rejeita o cadastro com motivo (contestável pelo canal único)',
    resultado_esperado = 'Status bloqueado com moderacao_resultado = rejeitado e motivo gravado; o especialista pode contestar.'
  WHERE codigo = 'PARC-004';
  UPDATE public.qa_casos_teste SET
    titulo = 'Não permite avaliar sem transação verificada (contratação concluída ou lead ganho)',
    resultado_esperado = 'A função marketye_avaliar recusa; não existe mais inserção direta de avaliação.'
  WHERE codigo = 'PARC-024';
END $qa$;

-- ---------------------------------------------------------------------
-- 2) Apoio das rotinas: fixtures sintéticas (apagadas no fim; a bateria
--    ainda descarta a transação inteira)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.qa_mky_claims(p_uid uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

-- Cria conta + perfil de empresa (para get_user_tenant_id) num tenant.
CREATE OR REPLACE FUNCTION public.qa_mky_usuario_empresa(p_tenant uuid, p_marca text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_uid uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky-' || p_marca || '-' || left(v_uid::text, 8) || '@sandbox.invalid');
  INSERT INTO public.profiles (user_id, tenant_id, nome_completo, onboarding_concluido) VALUES (v_uid, p_tenant, 'QA Empresa ' || p_marca, true);
  RETURN v_uid;
END $$;

CREATE OR REPLACE FUNCTION public.qa_mky_superadmin()
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_uid uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky-sa-' || left(v_uid::text, 8) || '@sandbox.invalid');
  INSERT INTO public.superadmins (user_id, email, nome, ativo) VALUES (v_uid, 'qa-mky-sa-' || left(v_uid::text, 8) || '@sandbox.invalid', 'QA Superadmin MKY', true);
  RETURN v_uid;
END $$;

-- Especialista fictício cadastrado pela função (pendente). CPF da faixa da casa.
CREATE OR REPLACE FUNCTION public.qa_mky_especialista(p_marca text, p_cpf text)
RETURNS TABLE (uid uuid, prof_id uuid) LANGUAGE plpgsql AS $$
DECLARE v_uid uuid := gen_random_uuid(); v_res jsonb;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_uid, 'qa-mky-esp-' || p_marca || '-' || left(v_uid::text, 8) || '@sandbox.invalid');
  v_res := public.marketye_cadastrar_especialista_para(v_uid, jsonb_build_object(
    'nome_completo', 'QA Especialista ' || p_marca, 'email', 'qa-mky-esp-' || p_marca || '-' || left(v_uid::text, 8) || '@sandbox.invalid',
    'cpf_cnpj', p_cpf, 'cidade', 'Cidade QA', 'estado', 'QA', 'modalidades', '["presencial","online"]'::jsonb, 'aceite_termos', true,
    'conselho', 'CREA', 'registro_profissional', 'QA-' || p_marca, 'origem', 'qa', 'tenant_origem', public.qa_sandbox_tenant_id()));
  RETURN QUERY SELECT v_uid, (v_res->>'id')::uuid;
END $$;

CREATE OR REPLACE FUNCTION public.qa_mky_limpar()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- Dependentes sem ON DELETE CASCADE primeiro (auditoria e avaliações), depois o especialista (o resto cascateia).
  DELETE FROM public.marketplace_audit_log WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_avaliacoes WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_leads WHERE profissional_id IN (SELECT id FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.marketplace_profissionais WHERE nome_completo LIKE 'QA Especialista %' OR email LIKE 'qa-mky-%@sandbox.invalid';
  DELETE FROM public.marketplace_demanda_latente WHERE uf = 'QA';
  DELETE FROM public.marketplace_categorias WHERE slug LIKE 'qa-mky-%';
  DELETE FROM public.superadmins WHERE email LIKE 'qa-mky-%@sandbox.invalid';
  DELETE FROM public.profiles WHERE nome_completo LIKE 'QA Empresa %' AND user_id IN (SELECT id FROM auth.users WHERE email LIKE 'qa-mky-%@sandbox.invalid');
  DELETE FROM public.tenants WHERE slug LIKE 'qa-mky-%';
  DELETE FROM auth.users WHERE email LIKE 'qa-mky-%@sandbox.invalid';
END $$;

-- ---------------------------------------------------------------------
-- 3) Rotinas
-- ---------------------------------------------------------------------
-- MKY-001 — cadastro nasce pendente; documento único; guarda no INSERT direto
CREATE OR REPLACE FUNCTION public.qa_caso_mky_001()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_status text; v_selo boolean; v_cons int; v_rep int; v_uid2 uuid := gen_random_uuid(); v_id2 uuid; v_claims text; v_dup text := 'ok';
        v_cercado uuid := public.qa_sandbox_tenant_id();
BEGIN
  PERFORM public.qa_mky_limpar();
  r.passo_ordem := 1; r.passo_acao := 'Cadastrar pela função com aceite'; r.esperado := 'pendente, sem selo, 3 consentimentos, reputação criada';
  SELECT * INTO e FROM public.qa_mky_especialista('001', '900.000.001-75');
  SELECT status::text, selo_verificado INTO v_status, v_selo FROM public.marketplace_profissionais WHERE id = e.prof_id;
  SELECT count(*) INTO v_cons FROM public.marketplace_consentimentos WHERE profissional_id = e.prof_id;
  SELECT count(*) INTO v_rep FROM public.marketplace_reputacao WHERE profissional_id = e.prof_id;
  IF v_status <> 'pendente' OR v_selo OR v_cons <> 3 OR v_rep <> 1 THEN
    r.situacao := 'falhou'; r.obtido := format('ACHADO: status %s, selo %s, consentimentos %s, reputação %s', v_status, v_selo, v_cons, v_rep); PERFORM public.qa_mky_limpar(); RETURN r;
  END IF;

  r.passo_ordem := 2; r.passo_acao := 'Repetir com o mesmo CPF em outra conta'; r.esperado := 'recusado';
  INSERT INTO auth.users (id, email) VALUES (v_uid2, 'qa-mky-dup-' || left(v_uid2::text, 8) || '@sandbox.invalid');
  BEGIN
    PERFORM public.marketye_cadastrar_especialista_para(v_uid2, jsonb_build_object('nome_completo', 'QA Especialista Dup', 'email', 'qa-mky-dup@sandbox.invalid', 'cpf_cnpj', '90000000175', 'aceite_termos', true));
    v_dup := 'aceitou';
  EXCEPTION WHEN OTHERS THEN v_dup := SQLERRM; END;
  IF v_dup NOT LIKE '%já possui cadastro%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: CPF repetido não foi recusado (' || v_dup || ')'; PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 3; r.passo_acao := 'INSERT direto como usuário autenticado com status ativo e selo'; r.esperado := 'guarda rebaixa para pendente/sem selo';
  v_claims := current_setting('request.jwt.claims', true);
  PERFORM public.qa_mky_claims(v_uid2);
  -- A trava do cercado (qa_guarda_cercado) lê public.tenants com o papel de
  -- quem escreve; como 'authenticated' ela não enxerga o cercado (RLS) e
  -- bloquearia este INSERT mesmo com tenant_id do cercado. O modo de teste
  -- fica desligado só neste statement: a linha é do cercado e a bateria
  -- descarta a transação inteira de qualquer jeito.
  PERFORM set_config('app.qa_modo', 'off', true);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.marketplace_profissionais (user_id, tenant_id, nome_completo, email, status, selo_verificado, nota_media)
    VALUES (v_uid2, v_cercado, 'QA Especialista Direto', 'qa-mky-direto-' || left(v_uid2::text, 8) || '@sandbox.invalid', 'ativo', true, 5) RETURNING id INTO v_id2;
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); RAISE;
  END;
  RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  SELECT status::text, selo_verificado INTO v_status, v_selo FROM public.marketplace_profissionais WHERE id = v_id2;
  IF v_status = 'pendente' AND NOT v_selo THEN
    r.situacao := 'passou'; r.obtido := 'Função e INSERT direto nascem pendentes e sem selo; CPF repetido recusado; consentimentos registrados.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: INSERT direto ficou %s / selo %s — a guarda não agiu.', v_status, v_selo);
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-002 — vitrine global: pendente não aparece; aprovado aparece para duas empresas
CREATE OR REPLACE FUNCTION public.qa_caso_mky_002()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_t1 uuid := public.qa_sandbox_tenant_id(); v_t2 uuid; v_u1 uuid; v_u2 uuid; v_claims text; v_an uuid; v_cat uuid;
        v_n1 int; v_n2 int; v_pub text := 'ok'; v_res jsonb;
BEGIN
  PERFORM public.qa_mky_limpar();
  IF v_t1 IS NULL THEN r.situacao := 'erro'; r.obtido := 'Cercado qa-sandbox não existe'; RETURN r; END IF;
  v_claims := current_setting('request.jwt.claims', true);
  SELECT id INTO v_t2 FROM public.tenants WHERE slug = 'qa-sandbox-2';
  IF v_t2 IS NULL THEN r.situacao := 'erro'; r.obtido := 'Segundo cercado (qa-sandbox-2) não existe'; RETURN r; END IF;
  v_u1 := public.qa_mky_usuario_empresa(v_t1, '002a'); v_u2 := public.qa_mky_usuario_empresa(v_t2, '002b'); v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('002', '900.000.002-56');
  SELECT id INTO v_cat FROM public.marketplace_categorias WHERE slug = 'seguranca-trabalho';

  r.passo_ordem := 1; r.passo_acao := 'Anúncio salvo (rascunho) com o cadastro pendente'; r.esperado := 'busca não encontra';
  PERFORM public.qa_mky_claims(e.uid);
  v_res := public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Laudo MKY-002 exclusivo', 'descricao', 'Serviço fictício de teste do MarketYE, apenas para a rotina automatizada.', 'categoria_id', v_cat, 'modalidade', 'online', 'tipo_preco', 'sob_orcamento'));
  v_an := (v_res->>'id')::uuid;
  PERFORM public.qa_mky_claims(v_u1);
  v_n1 := (public.marketye_buscar(jsonb_build_object('q', 'QA Laudo MKY-002', 'ignorar_uf_padrao', true))->>'total')::int;
  IF v_n1 <> 0 THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: anúncio de cadastro pendente apareceu na busca'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 2; r.passo_acao := 'Publicar antes da aprovação'; r.esperado := 'recusado';
  PERFORM public.qa_mky_claims(e.uid);
  BEGIN PERFORM public.marketye_anuncio_publicar(v_an); v_pub := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_pub := SQLERRM; END;
  IF v_pub NOT LIKE '%verificação%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: publicou sem aprovação (' || v_pub || ')'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 3; r.passo_acao := 'Superadmin aprova; especialista publica; duas empresas buscam'; r.esperado := 'as duas encontram';
  PERFORM public.qa_mky_claims(v_sa);
  PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM public.qa_mky_claims(e.uid);
  PERFORM public.marketye_anuncio_publicar(v_an);
  PERFORM public.qa_mky_claims(v_u1);
  v_n1 := (public.marketye_buscar(jsonb_build_object('q', 'QA Laudo MKY-002', 'ignorar_uf_padrao', true))->>'total')::int;
  PERFORM public.qa_mky_claims(v_u2);
  v_res := public.marketye_buscar(jsonb_build_object('q', 'QA Laudo MKY-002', 'ignorar_uf_padrao', true));
  v_n2 := (v_res->>'total')::int;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_n1 >= 1 AND v_n2 >= 1 AND (v_res->'resultados'->0->'profissional'->>'selo_verificado')::boolean THEN
    r.situacao := 'passou'; r.obtido := format('Pendente invisível; depois da aprovação, empresas distintas encontram o mesmo anúncio (%s/%s), com selo.', v_n1, v_n2);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: após aprovação, empresa 1 viu %s e empresa 2 viu %s.', v_n1, v_n2);
  END IF;
  r.detalhe := jsonb_build_object('primeiro', v_res->'resultados'->0->'fatores');
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-003 — avaliação só com lead ganho; bidirecional; recálculo
CREATE OR REPLACE FUNCTION public.qa_caso_mky_003()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_t uuid := public.qa_sandbox_tenant_id(); v_u uuid; v_claims text; v_an uuid; v_lead uuid; v_msg text := 'ok';
        v_nota numeric; v_tot int; v_dup text := 'ok'; v_rev jsonb;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_u := public.qa_mky_usuario_empresa(v_t, '003'); v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('003', '900.000.003-37');
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM public.qa_mky_claims(e.uid);
  v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Serviço MKY-003', 'descricao', 'Serviço fictício de teste do MarketYE para avaliação verificada.', 'modalidade', 'online'))->>'id')::uuid;
  PERFORM public.marketye_anuncio_publicar(v_an);

  r.passo_ordem := 1; r.passo_acao := 'Empresa abre lead e tenta avaliar'; r.esperado := 'recusado';
  PERFORM public.qa_mky_claims(v_u);
  v_lead := (public.marketye_abrir_lead(e.prof_id, v_an, 'Preciso de um orçamento para o serviço de teste.')->>'id')::uuid;
  BEGIN PERFORM public.marketye_avaliar('lead', v_lead, '{"pontualidade":5,"clareza":5,"aderencia_escopo":5,"profissionalismo":5}'::jsonb, NULL); v_msg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  IF v_msg NOT LIKE '%após o atendimento%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: avaliou sem transação (' || v_msg || ')'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 2; r.passo_acao := 'Especialista responde; empresa marca ganho e avalia'; r.esperado := 'aceita e recalcula';
  PERFORM public.qa_mky_claims(e.uid); PERFORM public.marketye_lead_mensagem(v_lead, 'Posso atender na próxima semana.');
  PERFORM public.qa_mky_claims(v_u); PERFORM public.marketye_lead_status(v_lead, 'ganho');
  v_rev := public.marketye_avaliar('lead', v_lead, '{"pontualidade":4,"clareza":5,"aderencia_escopo":4,"profissionalismo":5}'::jsonb, 'Ótimo atendimento de teste.');
  SELECT nota_media, total_avaliacoes INTO v_nota, v_tot FROM public.marketplace_profissionais WHERE id = e.prof_id;
  IF v_tot <> 1 OR v_nota <> 4.5 THEN r.situacao := 'falhou'; r.obtido := format('ACHADO: reputação não recalculou (nota %s, total %s)', v_nota, v_tot); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 3; r.passo_acao := 'Empresa avalia de novo'; r.esperado := 'recusado';
  BEGIN PERFORM public.marketye_avaliar('lead', v_lead, '{"pontualidade":1}'::jsonb, NULL); v_dup := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_dup := SQLERRM; END;
  IF v_dup NOT LIKE '%já foi avaliado%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: segunda avaliação passou (' || v_dup || ')'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 4; r.passo_acao := 'Especialista avalia a empresa'; r.esperado := 'direção especialista_para_cliente';
  PERFORM public.qa_mky_claims(e.uid);
  v_rev := public.marketye_avaliar('lead', v_lead, '{"clareza_demanda":5,"pagamento_combinado":5}'::jsonb, NULL);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_rev->>'direcao' = 'especialista_para_cliente' THEN
    r.situacao := 'passou'; r.obtido := 'Sem transação: recusa. Com lead ganho: cliente avalia uma vez (nota 4,5 recalculada) e o especialista avalia a empresa.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: avaliação reversa não gravou a direção correta.';
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-004 — piso de nota e destaque
CREATE OR REPLACE FUNCTION public.qa_caso_mky_004()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; ea record; eb record; v_sa uuid; v_t uuid := public.qa_sandbox_tenant_id(); v_u uuid; v_claims text; v_cat uuid; v_an_a uuid; v_an_b uuid;
        v_res jsonb; v_pos_a int; v_pos_b int; v_patro_a boolean; v_abaixo boolean; i int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_u := public.qa_mky_usuario_empresa(v_t, '004'); v_sa := public.qa_mky_superadmin();
  INSERT INTO public.marketplace_categorias (nome, slug, ativo, ordem) VALUES ('QA Categoria MKY-004', 'qa-mky-004', true, 999) RETURNING id INTO v_cat;
  SELECT * INTO ea FROM public.qa_mky_especialista('004A', '900.000.004-18');
  SELECT * INTO eb FROM public.qa_mky_especialista('004B', '900.000.005-07');
  PERFORM public.qa_mky_claims(v_sa);
  PERFORM public.marketye_moderar_especialista(ea.prof_id, 'aprovado', NULL, true); PERFORM public.marketye_moderar_especialista(eb.prof_id, 'aprovado', NULL, true);
  PERFORM public.qa_mky_claims(ea.uid);
  v_an_a := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Anúncio A MKY-004', 'descricao', 'Anúncio fictício A da rotina de piso de nota do MarketYE.', 'categoria_id', v_cat, 'modalidade', 'online'))->>'id')::uuid;
  PERFORM public.marketye_anuncio_publicar(v_an_a);
  PERFORM public.qa_mky_claims(eb.uid);
  v_an_b := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Anúncio B MKY-004', 'descricao', 'Anúncio fictício B da rotina de piso de nota do MarketYE.', 'categoria_id', v_cat, 'modalidade', 'online'))->>'id')::uuid;
  PERFORM public.marketye_anuncio_publicar(v_an_b);

  r.passo_ordem := 1; r.passo_acao := 'A: três notas 2 + destaque topo; B: três notas 5'; r.esperado := 'A abaixo do piso';
  FOR i IN 1..3 LOOP
    INSERT INTO public.marketplace_avaliacoes (profissional_id, tenant_id, direcao, nota_geral, criterios) VALUES (ea.prof_id, v_t, 'cliente_para_especialista', 2, '{}'::jsonb);
    INSERT INTO public.marketplace_avaliacoes (profissional_id, tenant_id, direcao, nota_geral, criterios) VALUES (eb.prof_id, v_t, 'cliente_para_especialista', 5, '{}'::jsonb);
  END LOOP;
  PERFORM public.marketye_recalcular_reputacao(ea.prof_id); PERFORM public.marketye_recalcular_reputacao(eb.prof_id);
  INSERT INTO public.marketplace_destaques (profissional_id, tipo, inicio, fim, ativo) VALUES (ea.prof_id, 'topo', CURRENT_DATE, CURRENT_DATE + 7, true);
  SELECT abaixo_piso INTO v_abaixo FROM public.marketplace_reputacao WHERE profissional_id = ea.prof_id;
  IF NOT COALESCE(v_abaixo, false) THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: nota 2 com 3 avaliações não marcou abaixo do piso'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 2; r.passo_acao := 'Buscar pela categoria'; r.esperado := 'B antes de A; A sem patrocinado';
  PERFORM public.qa_mky_claims(v_u);
  v_res := public.marketye_buscar(jsonb_build_object('categoria_id', v_cat, 'ignorar_uf_padrao', true));
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  SELECT o - 1 INTO v_pos_a FROM jsonb_array_elements(v_res->'resultados') WITH ORDINALITY AS x(v, o) WHERE (x.v->>'servico_id')::uuid = v_an_a;
  SELECT o - 1 INTO v_pos_b FROM jsonb_array_elements(v_res->'resultados') WITH ORDINALITY AS x(v, o) WHERE (x.v->>'servico_id')::uuid = v_an_b;
  SELECT (x.v->>'patrocinado')::boolean INTO v_patro_a FROM jsonb_array_elements(v_res->'resultados') AS x(v) WHERE (x.v->>'servico_id')::uuid = v_an_a;
  IF v_pos_b < v_pos_a AND NOT v_patro_a THEN
    r.situacao := 'passou'; r.obtido := format('B (nota 5) na posição %s, A (nota 2, destaque) na %s e sem rótulo Patrocinado.', v_pos_b, v_pos_a);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: posições B=%s A=%s, patrocinado A=%s', v_pos_b, v_pos_a, v_patro_a);
  END IF;
  r.detalhe := jsonb_build_object('total', v_res->'total');
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-005 — célula mínima das vagas de demanda
CREATE OR REPLACE FUNCTION public.qa_caso_mky_005()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_cat uuid; v_t uuid; i int; v_n4 int; v_n5 int; v_piso int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_piso := COALESCE((public.marketye_config('demanda_latente')->>'piso_celula')::int, 5);
  INSERT INTO public.marketplace_categorias (nome, slug, ativo, ordem) VALUES ('QA Categoria MKY-005', 'qa-mky-005', true, 999) RETURNING id INTO v_cat;
  r.passo_ordem := 1; r.passo_acao := format('%s empresas distintas sem oferta na mesma célula', v_piso - 1); r.esperado := 'célula ausente';
  FOR i IN 1..(v_piso - 1) LOOP
    INSERT INTO public.tenants (nome, slug) VALUES ('QA Empresa ' || i || ' (MKY-005)', 'qa-mky-005-' || i) RETURNING id INTO v_t;
    INSERT INTO public.marketplace_demanda_latente (tenant_id, categoria_id, uf, resultados) VALUES (v_t, v_cat, 'QA', 0);
  END LOOP;
  SELECT count(*) INTO v_n4 FROM jsonb_array_elements(public.marketye_vagas_demanda(30)) x WHERE x->>'categoria_slug' = 'qa-mky-005';
  r.passo_ordem := 2; r.passo_acao := 'Mais uma empresa'; r.esperado := format('célula com empresas = %s', v_piso);
  INSERT INTO public.tenants (nome, slug) VALUES ('QA Empresa extra (MKY-005)', 'qa-mky-005-x') RETURNING id INTO v_t;
  INSERT INTO public.marketplace_demanda_latente (tenant_id, categoria_id, uf, resultados) VALUES (v_t, v_cat, 'QA', 0);
  SELECT (x->>'empresas')::int INTO v_n5 FROM jsonb_array_elements(public.marketye_vagas_demanda(30)) x WHERE x->>'categoria_slug' = 'qa-mky-005';
  IF v_n4 = 0 AND v_n5 = v_piso THEN
    r.situacao := 'passou'; r.obtido := format('Com %s empresas a célula fica oculta; com %s aparece.', v_piso - 1, v_piso);
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: com %s empresas apareceu %s célula(s); com %s, empresas = %s', v_piso - 1, v_n4, v_piso, v_n5);
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-006 — mascaramento de contato
CREATE OR REPLACE FUNCTION public.qa_caso_mky_006()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_t uuid := public.qa_sandbox_tenant_id(); v_u uuid; v_claims text; v_an uuid; v_lead uuid; v_txt text; v_sinal boolean; v_c jsonb; v_txt2 text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_u := public.qa_mky_usuario_empresa(v_t, '006'); v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('006', '900.000.006-80');
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM public.qa_mky_claims(e.uid);
  v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Serviço MKY-006', 'descricao', 'Serviço fictício de teste do MarketYE para mascaramento de contato.', 'modalidade', 'online'))->>'id')::uuid;
  PERFORM public.marketye_anuncio_publicar(v_an);

  r.passo_ordem := 1; r.passo_acao := 'Mensagem com telefone e e-mail'; r.esperado := 'trechos ocultos e sinal de saída';
  PERFORM public.qa_mky_claims(v_u);
  v_lead := (public.marketye_abrir_lead(e.prof_id, v_an, 'Me chama no (46) 99999-1234 ou contato@exemplo.test para combinar.')->>'id')::uuid;
  SELECT texto, sinal_saida INTO v_txt, v_sinal FROM public.marketplace_lead_mensagens WHERE lead_id = v_lead AND autor_tipo = 'cliente' ORDER BY created_at LIMIT 1;
  IF v_txt LIKE '%99999%' OR v_txt LIKE '%exemplo.test%' OR NOT v_sinal THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: contato não foi mascarado: ' || v_txt; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 2; r.passo_acao := 'Especialista pede o contato'; r.esperado := 'liberado = false';
  PERFORM public.qa_mky_claims(e.uid);
  v_c := public.marketye_lead_contato(v_lead);
  IF (v_c->>'liberado')::boolean THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: contato saiu antes da liberação'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 3; r.passo_acao := 'Empresa libera e escreve de novo'; r.esperado := 'sem máscara; contato devolve e-mail';
  PERFORM public.qa_mky_claims(v_u);
  PERFORM public.marketye_lead_liberar_contato(v_lead);
  PERFORM public.marketye_lead_mensagem(v_lead, 'Agora pode falar no (46) 99999-1234.');
  SELECT texto INTO v_txt2 FROM public.marketplace_lead_mensagens WHERE lead_id = v_lead AND autor_tipo = 'cliente' AND texto LIKE 'Agora pode falar%' LIMIT 1;
  PERFORM public.qa_mky_claims(e.uid);
  v_c := public.marketye_lead_contato(v_lead);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_txt2 LIKE '%99999-1234%' AND (v_c->>'liberado')::boolean AND v_c->>'email' LIKE 'qa-mky-006%' THEN
    r.situacao := 'passou'; r.obtido := 'Mascarado até a liberação; depois, texto limpo e contato disponível pela função.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: após liberação texto=%s liberado=%s email=%s', v_txt2, v_c->>'liberado', v_c->>'email');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-007 — léxico não-disciplinar (somente leitura)
CREATE OR REPLACE FUNCTION public.qa_caso_mky_007()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_achados text[];
BEGIN
  r.passo_ordem := 1; r.passo_acao := 'Varrer nomes de tabelas, colunas e funções do módulo'; r.esperado := 'nenhum termo disciplinar';
  SELECT COALESCE(array_agg(DISTINCT nome), '{}') INTO v_achados FROM (
    SELECT table_name || '.' || column_name AS nome FROM information_schema.columns WHERE table_schema = 'public' AND (table_name LIKE 'marketplace\_%' OR table_name LIKE 'marketye\_%')
    UNION ALL SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND (table_name LIKE 'marketplace\_%' OR table_name LIKE 'marketye\_%')
    UNION ALL SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname LIKE 'marketye\_%'
  ) x WHERE nome ~* '(infrac|punic|sanc|democ|penal|castig)';
  IF COALESCE(array_length(v_achados, 1), 0) = 0 THEN
    r.situacao := 'passou'; r.obtido := 'Nenhum nome disciplinar no schema do MarketYE.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ' || array_to_string(v_achados, ', ');
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-008 — contestação com decisão humana
CREATE OR REPLACE FUNCTION public.qa_caso_mky_008()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_t uuid := public.qa_sandbox_tenant_id(); v_u uuid; v_claims text; v_status text; v_mod text; v_ct uuid; v_neg text := 'ok'; v_trilha int; v_resp text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_u := public.qa_mky_usuario_empresa(v_t, '008'); v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('008', '900.000.007-60');
  r.passo_ordem := 1; r.passo_acao := 'Superadmin rejeita com motivo'; r.esperado := 'bloqueado / rejeitado';
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'rejeitado', 'Documento ilegível (teste).', false);
  SELECT status::text, moderacao_resultado INTO v_status, v_mod FROM public.marketplace_profissionais WHERE id = e.prof_id;
  IF v_status <> 'bloqueado' OR v_mod <> 'rejeitado' THEN r.situacao := 'falhou'; r.obtido := format('ACHADO: rejeição deixou %s/%s', v_status, v_mod); PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;
  r.passo_ordem := 2; r.passo_acao := 'Especialista contesta'; r.esperado := 'aberta';
  PERFORM public.qa_mky_claims(e.uid);
  v_ct := (public.marketye_contestar('rejeicao_cadastro', e.prof_id, 'O documento enviado é legível; anexo nova cópia.')->>'id')::uuid;
  r.passo_ordem := 3; r.passo_acao := 'Usuário de empresa tenta decidir'; r.esperado := 'acesso negado';
  PERFORM public.qa_mky_claims(v_u);
  BEGIN PERFORM public.marketye_contestacao_decidir(v_ct, 'deferida', 'Tentativa indevida de decisão.'); v_neg := 'aceitou'; EXCEPTION WHEN OTHERS THEN v_neg := SQLERRM; END;
  IF v_neg NOT LIKE '%Acesso negado%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: usuário comum decidiu contestação (' || v_neg || ')'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;
  r.passo_ordem := 4; r.passo_acao := 'Superadmin defere'; r.esperado := 'pendente; trilha com 2 eventos';
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_contestacao_decidir(v_ct, 'deferida', 'Nova cópia conferida; cadastro volta à fila.');
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  SELECT status::text INTO v_status FROM public.marketplace_profissionais WHERE id = e.prof_id;
  SELECT jsonb_array_length(trilha), resposta INTO v_trilha, v_resp FROM public.marketplace_contestacoes WHERE id = v_ct;
  IF v_status = 'pendente' AND v_trilha = 2 AND v_resp IS NOT NULL THEN
    r.situacao := 'passou'; r.obtido := 'Rejeição contestada; só o superadmin decidiu; cadastro voltou a pendente com trilha de 2 eventos.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: status %s, trilha %s eventos, resposta %s', v_status, v_trilha, v_resp);
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-009 — exclusão LGPD
CREATE OR REPLACE FUNCTION public.qa_caso_mky_009()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_t uuid := public.qa_sandbox_tenant_id(); v_u uuid; v_claims text; v_an uuid; v_lead uuid; p record; v_n int; v_leads int; v_avals int;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_u := public.qa_mky_usuario_empresa(v_t, '009'); v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('009', '900.000.008-41');
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM public.qa_mky_claims(e.uid);
  v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Serviço MKY-009 exclusivo', 'descricao', 'Serviço fictício de teste do MarketYE para exclusão LGPD.', 'modalidade', 'online'))->>'id')::uuid;
  PERFORM public.marketye_anuncio_publicar(v_an);
  PERFORM public.qa_mky_claims(v_u);
  v_lead := (public.marketye_abrir_lead(e.prof_id, v_an, 'Quero contratar o serviço de teste.')->>'id')::uuid;
  PERFORM public.marketye_lead_status(v_lead, 'ganho');
  PERFORM public.marketye_avaliar('lead', v_lead, '{"pontualidade":5}'::jsonb, NULL);

  r.passo_ordem := 1; r.passo_acao := 'Especialista exclui o perfil'; r.esperado := 'anonimizado e fora da vitrine';
  PERFORM public.qa_mky_claims(e.uid);
  PERFORM public.marketye_excluir_meu_perfil('EXCLUIR');
  SELECT * INTO p FROM public.marketplace_profissionais WHERE id = e.prof_id;
  PERFORM public.qa_mky_claims(v_u);
  v_n := (public.marketye_buscar(jsonb_build_object('q', 'QA Serviço MKY-009', 'ignorar_uf_padrao', true))->>'total')::int;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  SELECT count(*) INTO v_leads FROM public.marketplace_leads WHERE profissional_id = e.prof_id;
  SELECT count(*) INTO v_avals FROM public.marketplace_avaliacoes WHERE profissional_id = e.prof_id;
  IF p.excluido_em IS NOT NULL AND p.status::text = 'bloqueado' AND p.cpf_cnpj IS NULL AND p.nome_completo = 'Especialista removido' AND p.email LIKE 'removido+%' AND v_n = 0 AND v_leads = 1 AND v_avals = 1 THEN
    r.situacao := 'passou'; r.obtido := 'Perfil anonimizado e fora da busca; lead e avaliação retidos.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: excluido_em %s, status %s, cpf %s, nome %s, busca %s, leads %s, avaliações %s', p.excluido_em, p.status, p.cpf_cnpj, p.nome_completo, v_n, v_leads, v_avals);
  END IF;
  -- A linha anonimizada não tem mais o marcador de e-mail: apaga pelo id (dependentes antes).
  DELETE FROM public.marketplace_audit_log WHERE profissional_id = e.prof_id;
  DELETE FROM public.marketplace_avaliacoes WHERE profissional_id = e.prof_id;
  DELETE FROM public.marketplace_leads WHERE profissional_id = e.prof_id;
  DELETE FROM public.marketplace_profissionais WHERE id = e.prof_id;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-010 — ajuste de nível com aviso e amortecedor; publicar continua livre
CREATE OR REPLACE FUNCTION public.qa_caso_mky_010()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_claims text; v_nivel text; v_aviso timestamptz; v_an uuid; v_st text;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('010', '900.000.009-22');
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  UPDATE public.marketplace_reputacao SET nivel = 'prata', nivel_aviso_em = NULL WHERE profissional_id = e.prof_id;

  r.passo_ordem := 1; r.passo_acao := 'Prata sem métricas; recalcular'; r.esperado := 'continua prata, com aviso';
  PERFORM public.marketye_recalcular_reputacao(e.prof_id);
  SELECT nivel, nivel_aviso_em INTO v_nivel, v_aviso FROM public.marketplace_reputacao WHERE profissional_id = e.prof_id;
  IF v_nivel <> 'prata' OR v_aviso IS NULL THEN r.situacao := 'falhou'; r.obtido := format('ACHADO: ajustou sem aviso (nível %s, aviso %s)', v_nivel, v_aviso); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 2; r.passo_acao := 'Aviso mais velho que o amortecedor; recalcular'; r.esperado := 'nível novo';
  UPDATE public.marketplace_reputacao SET nivel_aviso_em = now() - interval '40 days' WHERE profissional_id = e.prof_id;
  PERFORM public.marketye_recalcular_reputacao(e.prof_id);
  SELECT nivel INTO v_nivel FROM public.marketplace_reputacao WHERE profissional_id = e.prof_id;
  IF v_nivel <> 'novo' THEN r.situacao := 'falhou'; r.obtido := format('ACHADO: após o amortecedor o nível ficou %s', v_nivel); PERFORM public.qa_mky_limpar(); RETURN r; END IF;

  r.passo_ordem := 3; r.passo_acao := 'Publicar anúncio depois do ajuste'; r.esperado := 'publicado';
  PERFORM public.qa_mky_claims(e.uid);
  v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Serviço MKY-010', 'descricao', 'Serviço fictício de teste do MarketYE após ajuste de nível.', 'modalidade', 'online'))->>'id')::uuid;
  v_st := public.marketye_anuncio_publicar(v_an)->>'status';
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_st = 'publicado' THEN
    r.situacao := 'passou'; r.obtido := 'Aviso antes do ajuste; ajuste só após o amortecedor; publicar continuou permitido.';
  ELSE
    r.situacao := 'falhou'; r.obtido := 'ACHADO: ajuste de nível impediu publicar (' || COALESCE(v_st, 'nulo') || ')';
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-011 — trilha de autonomia
CREATE OR REPLACE FUNCTION public.qa_caso_mky_011()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_claims text; v_an uuid; v_n1 int; v_n2 int; ev record;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  SELECT * INTO e FROM public.qa_mky_especialista('011', '900.000.010-66');
  PERFORM public.qa_mky_claims(e.uid);
  r.passo_ordem := 1; r.passo_acao := 'Salvar anúncio com preço 300'; r.esperado := '1 evento';
  v_an := (public.marketye_anuncio_salvar(jsonb_build_object('nome', 'QA Serviço MKY-011', 'descricao', 'Serviço fictício de teste do MarketYE para a trilha de autonomia.', 'modalidade', 'online', 'tipo_preco', 'visita', 'preco_referencia', 300))->>'id')::uuid;
  SELECT count(*) INTO v_n1 FROM public.marketplace_autonomia_eventos WHERE profissional_id = e.prof_id AND referencia_id = v_an;
  r.passo_ordem := 2; r.passo_acao := 'Alterar para 350'; r.esperado := '2º evento com anterior/novo';
  PERFORM public.marketye_anuncio_salvar(jsonb_build_object('id', v_an, 'nome', 'QA Serviço MKY-011', 'descricao', 'Serviço fictício de teste do MarketYE para a trilha de autonomia.', 'modalidade', 'online', 'tipo_preco', 'visita', 'preco_referencia', 350));
  SELECT count(*) INTO v_n2 FROM public.marketplace_autonomia_eventos WHERE profissional_id = e.prof_id AND referencia_id = v_an;
  SELECT * INTO ev FROM public.marketplace_autonomia_eventos WHERE profissional_id = e.prof_id AND referencia_id = v_an AND anterior IS NOT NULL LIMIT 1;
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  IF v_n1 = 1 AND v_n2 = 2 AND (ev.anterior->>'preco_referencia')::numeric = 300 AND (ev.novo->>'preco_referencia')::numeric = 350 THEN
    r.situacao := 'passou'; r.obtido := 'Definição e alteração de preço registradas como eventos com anterior 300 e novo 350.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: eventos %s/%s, último anterior=%s novo=%s', v_n1, v_n2, ev.anterior->>'preco_referencia', ev.novo->>'preco_referencia');
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-012 — privilégios de leitura (somente leitura)
CREATE OR REPLACE FUNCTION public.qa_caso_mky_012()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; v_pii text[]; v_aval text[]; v_pol_antiga int; v_pol_sa int;
BEGIN
  r.passo_ordem := 1; r.passo_acao := 'Conferir colunas legíveis por authenticated'; r.esperado := 'sem PII';
  SELECT COALESCE(array_agg(column_name::text), '{}') INTO v_pii FROM information_schema.column_privileges
   WHERE table_schema = 'public' AND table_name = 'marketplace_profissionais' AND grantee = 'authenticated' AND privilege_type = 'SELECT'
     AND column_name IN ('email', 'telefone', 'cpf_cnpj', 'user_id', 'tenant_id');
  SELECT COALESCE(array_agg(column_name::text), '{}') INTO v_aval FROM information_schema.column_privileges
   WHERE table_schema = 'public' AND table_name = 'marketplace_avaliacoes' AND grantee = 'authenticated' AND privilege_type = 'SELECT' AND column_name IN ('avaliador_id', 'tenant_id');
  r.passo_ordem := 2; r.passo_acao := 'Conferir políticas'; r.esperado := 'sem admin por empresa; com superadmin';
  SELECT count(*) INTO v_pol_antiga FROM pg_policies WHERE tablename = 'marketplace_profissionais' AND policyname = 'Admins manage all professionals';
  SELECT count(*) INTO v_pol_sa FROM pg_policies WHERE tablename = 'marketplace_profissionais' AND policyname = 'marketplace_profissionais_superadmin';
  IF array_length(v_pii, 1) IS NULL AND array_length(v_aval, 1) IS NULL AND v_pol_antiga = 0 AND v_pol_sa = 1 THEN
    r.situacao := 'passou'; r.obtido := 'authenticated não lê e-mail/telefone/CPF/user_id nem avaliador_id; moderação só de superadmin.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: PII legível %s; avaliação %s; política antiga %s; superadmin %s', v_pii, v_aval, v_pol_antiga, v_pol_sa);
  END IF;
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- MKY-013 — guarda RN-021
CREATE OR REPLACE FUNCTION public.qa_caso_mky_013()
RETURNS public.qa_retorno LANGUAGE plpgsql AS $$
DECLARE r public.qa_retorno; e record; v_sa uuid; v_claims text; v_msg text := 'ok'; v_status text; v_selo boolean;
BEGIN
  PERFORM public.qa_mky_limpar();
  v_claims := current_setting('request.jwt.claims', true);
  v_sa := public.qa_mky_superadmin();
  SELECT * INTO e FROM public.qa_mky_especialista('013', '900.000.011-47');
  r.passo_ordem := 1; r.passo_acao := 'UPDATE direto de status pelo próprio especialista (papel authenticated)'; r.esperado := 'recusado pela guarda';
  PERFORM public.qa_mky_claims(e.uid);
  PERFORM set_config('app.qa_modo', 'off', true);  -- ver MKY-001: a trava do cercado não enxerga o cercado como authenticated
  SET LOCAL ROLE authenticated;
  BEGIN
    UPDATE public.marketplace_profissionais SET status = 'ativo', selo_verificado = true WHERE id = e.prof_id;
    v_msg := 'aceitou';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE; PERFORM set_config('app.qa_modo', 'on', true);
  IF v_msg NOT LIKE '%só mudam por função%' THEN r.situacao := 'falhou'; r.obtido := 'ACHADO: UPDATE direto passou (' || v_msg || ')'; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true); PERFORM public.qa_mky_limpar(); RETURN r; END IF;
  r.passo_ordem := 2; r.passo_acao := 'Superadmin aprova pela função'; r.esperado := 'ativo com selo';
  PERFORM public.qa_mky_claims(v_sa); PERFORM public.marketye_moderar_especialista(e.prof_id, 'aprovado', NULL, true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  SELECT status::text, selo_verificado INTO v_status, v_selo FROM public.marketplace_profissionais WHERE id = e.prof_id;
  IF v_status = 'ativo' AND v_selo THEN
    r.situacao := 'passou'; r.obtido := 'UPDATE direto recusado; a função de moderação ativou com selo.';
  ELSE
    r.situacao := 'falhou'; r.obtido := format('ACHADO: função deixou %s / selo %s', v_status, v_selo);
  END IF;
  PERFORM public.qa_mky_limpar();
  RETURN r;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE; PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  r.situacao := 'erro'; r.obtido := 'A rotina quebrou'; r.erro_tecnico := SQLERRM; RETURN r;
END $$;

-- ---------------------------------------------------------------------
-- 4) Registro das rotinas e ponte dos casos e2e
-- ---------------------------------------------------------------------
INSERT INTO public.qa_implementacoes (codigo, funcao_sql) VALUES
  ('MKY-001', 'qa_caso_mky_001'), ('MKY-002', 'qa_caso_mky_002'), ('MKY-003', 'qa_caso_mky_003'), ('MKY-004', 'qa_caso_mky_004'),
  ('MKY-005', 'qa_caso_mky_005'), ('MKY-006', 'qa_caso_mky_006'), ('MKY-007', 'qa_caso_mky_007'), ('MKY-008', 'qa_caso_mky_008'),
  ('MKY-009', 'qa_caso_mky_009'), ('MKY-010', 'qa_caso_mky_010'), ('MKY-011', 'qa_caso_mky_011'), ('MKY-012', 'qa_caso_mky_012'),
  ('MKY-013', 'qa_caso_mky_013')
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

INSERT INTO public.qa_cobertura_e2e (codigo, spec, teste)
SELECT v.codigo, v.spec, v.teste FROM (VALUES
  ('MKY-020', 'cypress/e2e/marketye.cy.ts', 'MKY-020: Cabeçalho: botão MarketYE abre a vitrine do marketplace de serviços'),
  ('MKY-021', 'cypress/e2e/marketye.cy.ts', 'MKY-021: Vitrine: filtrar por categoria lista anúncios; busca sem oferta oferece alternativas'),
  ('MKY-022', 'cypress/e2e/marketye.cy.ts', 'MKY-022: Página pública MarketYE: proposta ao especialista e caminho para o cadastro')
) AS v(codigo, spec, teste)
ON CONFLICT (codigo) DO NOTHING;


-- ---------------------------------------------------------------------
-- CONFERÊNCIA (único resultado exibido pelo editor)
-- ---------------------------------------------------------------------
WITH f AS MATERIALIZED (
  SELECT count(*) FILTER (WHERE p.proname = 'marketye_buscar') AS buscar,
         count(*) FILTER (WHERE p.proname = 'marketye_cadastrar_especialista_para') AS cadastro,
         count(*) FILTER (WHERE p.proname = 'marketye_avaliar') AS avaliar,
         count(*) FILTER (WHERE p.proname = 'marketye_meu_portal') AS portal,
         count(*) FILTER (WHERE p.proname = 'marketye_vitrine_publica') AS vitrine_publica,
         count(*) FILTER (WHERE p.proname = 'marketye_contestacao_decidir') AS contestacao,
         count(*) FILTER (WHERE p.proname = 'buscar_profissionais_proximos') AS antiga_com_pii
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
), c AS MATERIALIZED (
  SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'marketplace_leads') AS tabela_leads,
         EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'marketplace_profissionais' AND column_name = 'consentimento_versao') AS coluna_consentimento,
         EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'marketplace_servicos' AND column_name = 'status') AS coluna_status_anuncio,
         (SELECT count(*) FROM public.marketplace_config WHERE vigente) AS parametros_vigentes,
         (SELECT count(*) FROM public.marketplace_categorias WHERE pai_id IS NOT NULL) AS subcategorias,
         NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'marketplace_profissionais' AND policyname = 'Admins manage all professionals') AS politica_antiga_removida,
         NOT EXISTS (SELECT 1 FROM information_schema.column_privileges WHERE table_name = 'marketplace_profissionais' AND grantee = 'authenticated' AND privilege_type = 'SELECT' AND column_name IN ('email','telefone','cpf_cnpj')) AS pii_fechada,
         (SELECT count(*) FROM public.qa_casos_teste WHERE codigo LIKE 'MKY-%') AS casos_qa,
         (SELECT label FROM public.qa_modulos WHERE path = 'rede-parceiros') AS modulo_qa
), q AS MATERIALIZED (
  SELECT c.codigo, (public.qa_executar_descartavel('qa_caso_mky_' || c.codigo)).situacao AS situacao,
         (public.qa_executar_descartavel('qa_caso_mky_' || c.codigo)).erro_tecnico AS erro_tecnico
  FROM unnest(ARRAY['001','002','003','004','005','006','007','008','009','010','011','012','013']) AS c(codigo)
), qr AS MATERIALIZED (
  SELECT count(*) FILTER (WHERE situacao = 'passou') AS passaram, count(*) AS total,
         string_agg(codigo || ':' || situacao || COALESCE(' (' || left(erro_tecnico, 80) || ')', ''), '; ') FILTER (WHERE situacao <> 'passou') AS detalhes
  FROM q
)
SELECT CASE WHEN f.buscar = 1 AND f.cadastro = 1 AND f.avaliar = 1 AND f.portal = 1 AND f.vitrine_publica = 1 AND f.contestacao = 1 AND f.antiga_com_pii = 0
             AND c.tabela_leads AND c.coluna_consentimento AND c.coluna_status_anuncio AND c.parametros_vigentes >= 11 AND c.subcategorias >= 20
             AND c.politica_antiga_removida AND c.pii_fechada AND c.casos_qa >= 16 AND qr.passaram = qr.total
            THEN 'OK' ELSE 'REVISAR' END AS resultado,
       f.buscar, f.cadastro, f.avaliar, f.portal, f.vitrine_publica, f.contestacao, f.antiga_com_pii,
       c.tabela_leads, c.coluna_consentimento, c.coluna_status_anuncio, c.parametros_vigentes, c.subcategorias, c.politica_antiga_removida, c.pii_fechada,
       c.casos_qa, c.modulo_qa, qr.passaram || '/' || qr.total AS qa_mky, qr.detalhes AS erro_tecnico
FROM f, c, qr;
