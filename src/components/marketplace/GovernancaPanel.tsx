import { useState } from "react";
import { Scale, Gavel, SlidersHorizontal, BarChart3, Megaphone, FileBarChart } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import { useMarketYEModeracao, useMarketYECategorias } from "@/hooks/useMarketYE";

interface Contestacao { id: string; especialista: string; especialista_status: string; decisao_tipo: string; motivo: string; status: string; resposta: string | null; created_at: string; trilha: { evento: string; em: string; por: string }[] }

const tipoLabel: Record<string, string> = {
  rejeicao_cadastro: "Rejeição do cadastro", suspensao: "Suspensão", remocao_anuncio: "Remoção de anúncio", ajuste_nivel: "Ajuste de nível", reflexo_visibilidade: "Reflexo na visibilidade", avaliacao: "Avaliação", outro: "Outro",
};

export function ContestacoesPanel({ ativo }: { ativo: boolean }) {
  const { contestacoes, decidirContestacao } = useMarketYEModeracao(ativo);
  const [resposta, setResposta] = useState<Record<string, string>>({});
  const lista = (contestacoes.data ?? []) as Contestacao[];
  return (
    <div className="space-y-4">
      <div className="p-3 bg-indigo-50 border border-indigo-200 rounded-xl text-xs text-indigo-800 flex gap-2"><Gavel className="h-4 w-4 mt-0.5 shrink-0" /><p>Canal único de contestação (devido processo + revisão de decisão automatizada). A decisão é sempre de uma pessoa e fica com trilha de evidência.</p></div>
      {lista.length === 0 ? <p className="text-sm text-muted-foreground text-center py-6">Nenhuma contestação.</p> : lista.map((c) => (
        <div key={c.id} className="rounded-2xl border border-border p-4 space-y-2">
          <div className="flex items-center justify-between gap-2 flex-wrap">
            <div><p className="font-medium">{c.especialista} <span className="text-xs text-muted-foreground">({c.especialista_status})</span></p><p className="text-xs text-muted-foreground">{tipoLabel[c.decisao_tipo] ?? c.decisao_tipo} · {format(new Date(c.created_at), "dd/MM/yyyy HH:mm", { locale: ptBR })}</p></div>
            <Badge variant="secondary">{c.status}</Badge>
          </div>
          <p className="text-sm">{c.motivo}</p>
          {c.resposta && <p className="text-sm text-muted-foreground border-l-2 pl-2">Resposta: {c.resposta}</p>}
          {(c.status === "aberta" || c.status === "em_analise") && (
            <div className="space-y-2">
              <Textarea rows={2} placeholder="Resposta ao especialista (obrigatória, vira trilha de evidência)" value={resposta[c.id] ?? ""} onChange={(e) => setResposta((r) => ({ ...r, [c.id]: e.target.value }))} />
              <div className="flex gap-2 justify-end">
                {c.status === "aberta" && <Button size="sm" variant="ghost" onClick={() => decidirContestacao.mutate({ id: c.id, resultado: "em_analise", resposta: resposta[c.id] ?? "" })}>Marcar em análise</Button>}
                <Button size="sm" variant="outline" className="text-red-600" disabled={(resposta[c.id] ?? "").trim().length < 10} onClick={() => decidirContestacao.mutate({ id: c.id, resultado: "indeferida", resposta: resposta[c.id] })}>Indeferir</Button>
                <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700 text-white" disabled={(resposta[c.id] ?? "").trim().length < 10} onClick={() => decidirContestacao.mutate({ id: c.id, resultado: "deferida", resposta: resposta[c.id] })}>Deferir</Button>
              </div>
            </div>
          )}
          <details className="text-[11px] text-muted-foreground"><summary>Trilha ({c.trilha?.length ?? 0})</summary><ul>{(c.trilha ?? []).map((t, i) => <li key={i}>{t.evento} · {t.por} · {format(new Date(t.em), "dd/MM HH:mm")}</li>)}</ul></details>
        </div>
      ))}
    </div>
  );
}

export function ParametrosPanel({ ativo }: { ativo: boolean }) {
  const { config, salvarConfig } = useMarketYEModeracao(ativo);
  const [editando, setEditando] = useState<Record<string, string>>({});
  const itens = config.data ?? [];
  return (
    <div className="space-y-4">
      <div className="p-3 bg-indigo-50 border border-indigo-200 rounded-xl text-xs text-indigo-800 flex gap-2"><SlidersHorizontal className="h-4 w-4 mt-0.5 shrink-0" /><p>Regra viva: pesos de relevância, piso de nota, níveis, proteção ao novato, célula mínima e versões dos termos mudam aqui, por versão, sem publicar código. Cada salvamento cria uma nova versão; a anterior fica no histórico.</p></div>
      {itens.map((c) => {
        const atual = editando[c.chave] ?? JSON.stringify(c.valor, null, 2);
        let valido = true; try { JSON.parse(atual); } catch { valido = false; }
        return (
          <div key={c.chave} className="rounded-2xl border border-border p-4 space-y-2">
            <div className="flex items-center justify-between gap-2"><p className="font-medium font-mono text-sm">{c.chave}</p><Badge variant="outline">versão {c.versao}</Badge></div>
            {c.descricao && <p className="text-xs text-muted-foreground">{c.descricao}</p>}
            <Textarea className="font-mono text-xs" rows={Math.min(10, atual.split("\n").length + 1)} value={atual} onChange={(e) => setEditando((s) => ({ ...s, [c.chave]: e.target.value }))} />
            <div className="flex justify-end gap-2">
              {editando[c.chave] !== undefined && <Button size="sm" variant="ghost" onClick={() => setEditando((s) => { const n = { ...s }; delete n[c.chave]; return n; })}>Descartar</Button>}
              <Button size="sm" disabled={!valido || editando[c.chave] === undefined || salvarConfig.isPending} onClick={() => salvarConfig.mutate({ chave: c.chave, valor: JSON.parse(atual), descricao: c.descricao ?? undefined }, { onSuccess: () => setEditando((s) => { const n = { ...s }; delete n[c.chave]; return n; }) })}>Salvar nova versão</Button>
            </div>
          </div>
        );
      })}
    </div>
  );
}

export function LiquidezPanel({ ativo }: { ativo: boolean }) {
  const { painel, transparencia } = useMarketYEModeracao(ativo);
  const p = painel.data as {
    especialistas: { ativos: number; pendentes: number; novos_30d: number; excluidos_30d: number }; anuncios_publicados: number;
    densidade: { categoria: string; uf: string | null; especialistas: number }[]; cobertura: { celulas_total: number; celulas_densas: number };
    leads: { abertos_30d: number; respondidos_30d: number; ganhos_30d: number; tempo_resposta_mediano_min: number | null };
    demanda_latente: { categoria: string; uf: string | null; empresas: number; avisar: boolean }[]; tempo_ate_primeira_venda_dias: number | null; contestacoes_abertas: number;
  } | null | undefined;
  const t = transparencia.data as Record<string, unknown> | null | undefined;
  if (!p) return <p className="text-sm text-muted-foreground">Carregando painel...</p>;
  const Kpi = ({ label, value, hint }: { label: string; value: string | number; hint?: string }) => (
    <div className="rounded-2xl border border-border p-4"><p className="text-xs text-muted-foreground">{label}</p><p className="text-2xl font-bold">{value}</p>{hint && <p className="text-[11px] text-muted-foreground">{hint}</p>}</div>
  );
  const taxaResp = p.leads.abertos_30d ? Math.round((p.leads.respondidos_30d / p.leads.abertos_30d) * 100) : null;
  const conv = p.leads.abertos_30d ? Math.round((p.leads.ganhos_30d / p.leads.abertos_30d) * 100) : null;
  return (
    <div className="space-y-6">
      <div className="p-3 bg-indigo-50 border border-indigo-200 rounded-xl text-xs text-indigo-800 flex gap-2"><BarChart3 className="h-4 w-4 mt-0.5 shrink-0" /><p>Métrica-mãe: liquidez por célula (categoria × UF). A meta do MVP é ≥ 3 especialistas por célula-alvo e resposta em até 4 h úteis.</p></div>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <Kpi label="Especialistas ativos" value={p.especialistas.ativos} hint={`${p.especialistas.pendentes} em verificação · ${p.especialistas.novos_30d} novos em 30d`} />
        <Kpi label="Anúncios publicados" value={p.anuncios_publicados} />
        <Kpi label="Cobertura de células" value={`${p.cobertura.celulas_densas}/${p.cobertura.celulas_total}`} hint="células com ≥ 3 especialistas" />
        <Kpi label="Leads em 30 dias" value={p.leads.abertos_30d} hint={`${taxaResp ?? "—"}% respondidos · ${conv ?? "—"}% viraram serviço`} />
        <Kpi label="1ª resposta (mediana)" value={p.leads.tempo_resposta_mediano_min != null ? `${Math.round(p.leads.tempo_resposta_mediano_min)} min` : "—"} />
        <Kpi label="Tempo até 1ª venda" value={p.tempo_ate_primeira_venda_dias != null ? `${p.tempo_ate_primeira_venda_dias} d` : "—"} hint="mediana por especialista" />
        <Kpi label="Churn de oferta (30d)" value={p.especialistas.excluidos_30d} hint="perfis excluídos" />
        <Kpi label="Contestações abertas" value={p.contestacoes_abertas} />
      </div>
      <div className="grid md:grid-cols-2 gap-4">
        <div className="rounded-2xl border border-border p-4">
          <h4 className="font-medium mb-2">Densidade por célula</h4>
          {p.densidade.length === 0 ? <p className="text-xs text-muted-foreground">Sem anúncios publicados.</p> : (
            <table className="w-full text-xs"><tbody>{p.densidade.slice(0, 20).map((d, i) => <tr key={i} className="border-t"><td className="py-1">{d.categoria}</td><td className="py-1">{d.uf ?? "—"}</td><td className="py-1 text-right font-medium">{d.especialistas}</td></tr>)}</tbody></table>
          )}
        </div>
        <div className="rounded-2xl border border-border p-4">
          <h4 className="font-medium mb-2">Buscas sem oferta (30 dias)</h4>
          {p.demanda_latente.length === 0 ? <p className="text-xs text-muted-foreground">Nenhuma busca sem oferta registrada.</p> : (
            <table className="w-full text-xs"><tbody>{p.demanda_latente.slice(0, 20).map((d, i) => <tr key={i} className="border-t"><td className="py-1">{d.categoria}</td><td className="py-1">{d.uf ?? "—"}</td><td className="py-1 text-right font-medium">{d.empresas} empresa(s){d.avisar ? " · pediram aviso" : ""}</td></tr>)}</tbody></table>
          )}
          <p className="text-[11px] text-muted-foreground mt-2">Onde captar oferta primeiro. Na página pública só aparecem células com 5+ empresas.</p>
        </div>
      </div>
      {t && (
        <div className="rounded-2xl border border-border p-4">
          <h4 className="font-medium mb-2 flex items-center gap-2"><FileBarChart className="h-4 w-4" />Transparência {String(t.ano)}</h4>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2 text-xs">
            <p>Denúncias recebidas: <b>{String(t.denuncias_recebidas)}</b></p><p>Procedentes: <b>{String(t.denuncias_procedentes)}</b></p>
            <p>Cadastros aprovados: <b>{String(t.cadastros_aprovados)}</b></p><p>Rejeitados: <b>{String(t.cadastros_rejeitados)}</b></p>
            <p>Anúncios publicados: <b>{String(t.anuncios_publicados)}</b></p><p>Impulsionamentos: <b>{String(t.impulsionamentos)}</b></p>
            <p>Exclusões LGPD: <b>{String(t.exclusoes_lgpd)}</b></p><p>Contestações: <b>{JSON.stringify(t.contestacoes)}</b></p>
          </div>
        </div>
      )}
    </div>
  );
}

export function DestaquesPanel({ ativo }: { ativo: boolean }) {
  const { criarDestaque } = useMarketYEModeracao(ativo);
  const { data: cats } = useMarketYECategorias();
  const [f, setF] = useState({ profissional_id: "", tipo: "categoria", categoria_id: "", uf: "", inicio: format(new Date(), "yyyy-MM-dd"), fim: "", valor: "" });
  return (
    <div className="space-y-4 max-w-xl">
      <div className="p-3 bg-amber-50 border border-amber-200 rounded-xl text-xs text-amber-800 flex gap-2"><Megaphone className="h-4 w-4 mt-0.5 shrink-0" /><p>Destaque pago é camada aditiva e rotulada "Patrocinado". Não passa por cima do piso de nota nem ultrapassa o teto por categoria. A cobrança em si fica para a próxima onda; aqui só se registra o período.</p></div>
      <div className="grid gap-3">
        <div><Label>ID do especialista</Label><Input value={f.profissional_id} onChange={(e) => setF({ ...f, profissional_id: e.target.value })} placeholder="uuid (copie da fila de moderação)" /></div>
        <div><Label>Tipo</Label>
          <Select value={f.tipo} onValueChange={(v) => setF({ ...f, tipo: v })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="categoria">Na categoria</SelectItem><SelectItem value="regiao">Na região (UF)</SelectItem><SelectItem value="topo">Topo geral</SelectItem></SelectContent></Select>
        </div>
        {f.tipo === "categoria" && <div><Label>Categoria</Label>
          <Select value={f.categoria_id} onValueChange={(v) => setF({ ...f, categoria_id: v })}><SelectTrigger><SelectValue placeholder="Selecione" /></SelectTrigger><SelectContent>{(cats?.todas ?? []).map((c) => <SelectItem key={c.id} value={c.id}>{c.pai_id ? "— " : ""}{c.nome}</SelectItem>)}</SelectContent></Select>
        </div>}
        {f.tipo === "regiao" && <div><Label>UF</Label><Input value={f.uf} onChange={(e) => setF({ ...f, uf: e.target.value.toUpperCase() })} maxLength={2} /></div>}
        <div className="grid grid-cols-2 gap-2"><div><Label>Início</Label><Input type="date" value={f.inicio} onChange={(e) => setF({ ...f, inicio: e.target.value })} /></div><div><Label>Fim</Label><Input type="date" value={f.fim} onChange={(e) => setF({ ...f, fim: e.target.value })} /></div></div>
        <div><Label>Valor (registro)</Label><Input type="number" value={f.valor} onChange={(e) => setF({ ...f, valor: e.target.value })} /></div>
        <Button disabled={!f.profissional_id || !f.fim || criarDestaque.isPending} onClick={() => criarDestaque.mutate({ profissional_id: f.profissional_id, tipo: f.tipo as "categoria" | "regiao" | "topo", categoria_id: f.categoria_id || null, uf: f.uf || null, inicio: f.inicio, fim: f.fim, valor: f.valor ? Number(f.valor) : null })}><Scale className="h-4 w-4 mr-1" />Registrar destaque</Button>
      </div>
    </div>
  );
}
