import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { Loader2, Sparkles, Star, MessageSquare, FileText, Activity, ShieldCheck, Gavel, Ticket, Download, Trash2, Send, Eye, PauseCircle, PlayCircle, Pencil, CheckCircle2, AlertTriangle, Clock, Users, Phone, Mail, Building2 } from "lucide-react";
import { toast } from "sonner";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Checkbox } from "@/components/ui/checkbox";
import { MarketYELayout } from "@/components/marketye/MarketYELayout";
import { useMarketYEPortal, usePortalMensagens, marketyeIA, TERMO_LABEL, type PortalAnuncio, type PortalLead } from "@/hooks/useMarketYEPortal";
import { useMarketYECategorias, NIVEL_LABEL, LEAD_STATUS_LABEL } from "@/hooks/useMarketYE";
import { AvaliacaoCriteriosModal, CRITERIOS_EMPRESA } from "@/components/marketplace/AvaliacaoCriteriosModal";

const statusPerfil: Record<string, { label: string; cor: string; texto: string }> = {
  pendente: { label: "Em verificação", cor: "bg-amber-500/20 text-amber-200", texto: "Estamos conferindo seus dados e registro. Enquanto isso, complete o perfil e prepare seus anúncios: eles entram na vitrine assim que a verificação concluir." },
  ativo: { label: "Ativo na vitrine", cor: "bg-emerald-500/20 text-emerald-200", texto: "Seu perfil está visível para as empresas clientes." },
  suspenso: { label: "Suspenso", cor: "bg-red-500/20 text-red-200", texto: "Seu perfil está fora da vitrine temporariamente. Você pode contestar pelo canal único abaixo." },
  bloqueado: { label: "Fora da vitrine", cor: "bg-slate-500/20 text-slate-200", texto: "Seu cadastro não foi aprovado ou foi encerrado. Veja o motivo e, se discordar, conteste." },
};
const saudeCor: Record<string, string> = { verde: "bg-emerald-500", amarelo: "bg-amber-400", vermelho: "bg-red-500", cinza: "bg-slate-400" };
const inputCls = "bg-black/20 border-white/15 text-white";

export default function PortalEspecialista() {
  const { portal, aceitarTermos, exportar, excluir } = useMarketYEPortal();
  const d = portal.data;
  const [confirmExcluir, setConfirmExcluir] = useState("");
  const [excluirAberto, setExcluirAberto] = useState(false);

  if (portal.isLoading || !d) {
    return <MarketYELayout titulo="Portal do especialista"><div className="py-20 flex justify-center"><Loader2 className="w-8 h-8 animate-spin text-[#60ABEF]" /></div></MarketYELayout>;
  }
  const st = statusPerfil[d.perfil.status] ?? statusPerfil.pendente;
  const rep = d.reputacao;

  return (
    <MarketYELayout titulo="Portal do especialista">
      <div className="space-y-6" data-testid="portal-especialista">
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div className="flex items-center gap-4">
            {d.perfil.foto_url ? <img src={d.perfil.foto_url} alt="" className="w-16 h-16 rounded-2xl object-cover" /> : <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-indigo-500 to-violet-600 flex items-center justify-center text-2xl font-bold">{d.perfil.nome_completo.charAt(0)}</div>}
            <div>
              <h1 className="text-2xl font-bold text-white" data-testid="portal-especialista-nome">{d.perfil.nome_completo}</h1>
              <div className="flex items-center gap-2 flex-wrap mt-1">
                <Badge className={st.cor}>{st.label}</Badge>
                {d.perfil.selo_verificado && <Badge className="bg-emerald-500/20 text-emerald-200"><ShieldCheck className="w-3 h-3 mr-1" />dados verificados</Badge>}
                <Badge className="bg-white/10 text-slate-200">Nível {NIVEL_LABEL[d.nivel.atual] ?? d.nivel.atual}</Badge>
                {rep && <span className="inline-flex items-center gap-1 text-xs text-slate-300"><span className={`w-2 h-2 rounded-full ${saudeCor[rep.saude_cor]}`} />saúde recente {Math.round(Number(rep.saude_score))}/100</span>}
              </div>
            </div>
          </div>
          <div className="text-right text-xs text-slate-400">
            <p>Perfil {d.completude}% completo</p>
            <div className="w-40 h-2 bg-white/10 rounded-full mt-1 overflow-hidden"><div className="h-full bg-[#60ABEF]" style={{ width: `${d.completude}%` }} /></div>
          </div>
        </div>
        <p className="text-sm text-slate-300">{st.texto}{d.perfil.moderacao_motivo && d.perfil.status !== "ativo" ? ` Motivo: ${d.perfil.moderacao_motivo}` : ""}</p>

        {d.termos_pendentes.length > 0 && (
          <div className="rounded-2xl border border-amber-400/30 bg-amber-500/10 p-4 space-y-2">
            <p className="text-sm text-amber-100 font-medium flex items-center gap-2"><AlertTriangle className="w-4 h-4" />Há termos com versão nova para aceitar</p>
            <div className="flex gap-2 flex-wrap">{d.termos_pendentes.map((t) => <Button key={t.tipo} size="sm" variant="outline" className="border-amber-300/40 text-amber-100 hover:bg-amber-500/20" onClick={() => aceitarTermos.mutate({ tipo: t.tipo, versao: t.versao })}>Aceitar {TERMO_LABEL[t.tipo] ?? t.tipo} ({t.versao})</Button>)}</div>
          </div>
        )}
        {d.nivel.aviso_em && (
          <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 text-sm text-slate-200"><Clock className="w-4 h-4 inline mr-1 text-amber-300" />{d.nivel.aviso_motivo}</div>
        )}

        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <Kpi label="Leads em 30 dias" value={d.metricas.leads_30d} />
          <Kpi label="Serviços combinados (30d)" value={d.metricas.leads_ganhos_30d} />
          <Kpi label="Aguardando sua resposta" value={d.metricas.sem_resposta} destaque={d.metricas.sem_resposta > 0} />
          <Kpi label="Avaliações" value={`${d.metricas.avaliacoes}${d.perfil.total_avaliacoes ? ` · ${Number(d.perfil.nota_media).toFixed(1)}★` : ""}`} />
        </div>

        <Tabs defaultValue={d.perfil.status === "ativo" && d.anuncios.length > 0 ? "conversas" : "anuncios"}>
          <TabsList className="bg-white/5 flex-wrap h-auto">
            <TabsTrigger value="anuncios"><FileText className="w-4 h-4 mr-1" />Anúncios</TabsTrigger>
            <TabsTrigger value="conversas"><MessageSquare className="w-4 h-4 mr-1" />Conversas</TabsTrigger>
            <TabsTrigger value="reputacao"><Activity className="w-4 h-4 mr-1" />Reputação e nível</TabsTrigger>
            <TabsTrigger value="perfil"><Pencil className="w-4 h-4 mr-1" />Meu perfil</TabsTrigger>
            <TabsTrigger value="cupons"><Ticket className="w-4 h-4 mr-1" />Cupons</TabsTrigger>
            <TabsTrigger value="conta"><Gavel className="w-4 h-4 mr-1" />Termos, contestação e dados</TabsTrigger>
          </TabsList>
          <TabsContent value="anuncios" className="mt-4"><AnunciosTab anuncios={d.anuncios} perfilAtivo={d.perfil.status === "ativo"} /></TabsContent>
          <TabsContent value="conversas" className="mt-4"><ConversasTab leads={d.leads} /></TabsContent>
          <TabsContent value="reputacao" className="mt-4"><ReputacaoTab d={d} /></TabsContent>
          <TabsContent value="perfil" className="mt-4"><PerfilTab d={d} /></TabsContent>
          <TabsContent value="cupons" className="mt-4"><CuponsTab cupons={d.cupons} /></TabsContent>
          <TabsContent value="conta" className="mt-4">
            <ContaTab d={d} onExportar={async () => { try { const j = await exportar(); const blob = new Blob([JSON.stringify(j, null, 2)], { type: "application/json" }); const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = "meus-dados-marketye.json"; a.click(); } catch (e) { toast.error(e instanceof Error ? e.message : "Falha ao exportar"); } }} onExcluir={() => setExcluirAberto(true)} />
          </TabsContent>
        </Tabs>
      </div>

      <Dialog open={excluirAberto} onOpenChange={setExcluirAberto}>
        <DialogContent>
          <DialogHeader><DialogTitle>Excluir meu perfil do MarketYE</DialogTitle></DialogHeader>
          <p className="text-sm text-muted-foreground">Seu perfil sairá da vitrine e será anonimizado (nome, e-mail, documento, foto). Registros de conversas e avaliações são retidos pelo prazo legal, sem seu nome. Digite <b>EXCLUIR</b> para confirmar.</p>
          <Input value={confirmExcluir} onChange={(e) => setConfirmExcluir(e.target.value)} />
          <Button variant="destructive" disabled={confirmExcluir !== "EXCLUIR" || excluir.isPending} onClick={() => excluir.mutate(confirmExcluir, { onSuccess: () => { setExcluirAberto(false); window.location.assign(`${import.meta.env.BASE_URL.replace(/\/$/, "")}/marketye`); } })}><Trash2 className="w-4 h-4 mr-1" />Excluir definitivamente</Button>
        </DialogContent>
      </Dialog>
    </MarketYELayout>
  );
}

function Kpi({ label, value, destaque }: { label: string; value: string | number; destaque?: boolean }) {
  return <div className={`rounded-2xl border p-4 ${destaque ? "border-[#FF8A00]/50 bg-[#FF8A00]/10" : "border-white/10 bg-white/[0.04]"}`}><p className="text-xs text-slate-400">{label}</p><p className="text-2xl font-bold text-white">{value}</p></div>;
}

// ---------------------------------------------------------------------
function AnunciosTab({ anuncios, perfilAtivo }: { anuncios: PortalAnuncio[]; perfilAtivo: boolean }) {
  const { publicarAnuncio, statusAnuncio } = useMarketYEPortal();
  const [editando, setEditando] = useState<PortalAnuncio | null | "novo">(null);
  const statusLabel: Record<string, string> = { rascunho: "Rascunho", publicado: "Publicado", pausado: "Pausado", removido: "Removido" };
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <p className="text-sm text-slate-300">Cada anúncio é um serviço. Você define preço, prazo e política; a IA ajuda a escrever.</p>
        <Button className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" onClick={() => setEditando("novo")} data-testid="portal-novo-anuncio"><Sparkles className="w-4 h-4 mr-1" />Novo anúncio</Button>
      </div>
      {!perfilAtivo && <p className="text-xs text-amber-200">Seu cadastro ainda está em verificação: salve os anúncios agora e publique assim que for aprovado.</p>}
      {anuncios.length === 0 ? <p className="text-sm text-slate-400 py-8 text-center">Nenhum anúncio ainda. Crie o primeiro: três campos e a IA faz o resto.</p> : (
        <div className="grid md:grid-cols-2 gap-3">
          {anuncios.map((a) => (
            <div key={a.id} className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
              <div className="flex items-start justify-between gap-2">
                <div><p className="font-semibold text-white">{a.nome}</p><p className="text-xs text-slate-400">{a.categoria_nome ?? "Sem categoria"} · {a.modalidade}</p></div>
                <Badge className="bg-white/10 text-slate-200">{statusLabel[a.status]}</Badge>
              </div>
              <p className="text-sm text-slate-300 line-clamp-2">{a.descricao}</p>
              <p className="text-xs text-slate-400">{a.tipo_preco === "sob_orcamento" ? "Sob orçamento" : `R$ ${Number(a.preco_referencia ?? 0).toFixed(2)} / ${a.tipo_preco}`}{a.promocao_percentual ? ` · promoção ${a.promocao_percentual}%` : ""}</p>
              <div className="flex gap-2 flex-wrap">
                <Button size="sm" variant="outline" className="border-white/20 bg-transparent text-slate-100 hover:bg-white/10" onClick={() => setEditando(a)}><Pencil className="w-3.5 h-3.5 mr-1" />Editar</Button>
                {a.status !== "publicado" && <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700 text-white" disabled={publicarAnuncio.isPending} onClick={() => publicarAnuncio.mutate(a.id)}><Eye className="w-3.5 h-3.5 mr-1" />Publicar</Button>}
                {a.status === "publicado" && <Button size="sm" variant="ghost" className="text-slate-300" onClick={() => statusAnuncio.mutate({ id: a.id, status: "pausado" })}><PauseCircle className="w-3.5 h-3.5 mr-1" />Pausar</Button>}
                {a.status === "pausado" && <Button size="sm" variant="ghost" className="text-slate-300" onClick={() => publicarAnuncio.mutate(a.id)}><PlayCircle className="w-3.5 h-3.5 mr-1" />Reativar</Button>}
                <Button size="sm" variant="ghost" className="text-slate-400" onClick={() => statusAnuncio.mutate({ id: a.id, status: "removido" })}><Trash2 className="w-3.5 h-3.5" /></Button>
              </div>
            </div>
          ))}
        </div>
      )}
      {editando && <AnuncioEditor anuncio={editando === "novo" ? null : editando} onClose={() => setEditando(null)} />}
    </div>
  );
}

function AnuncioEditor({ anuncio, onClose }: { anuncio: PortalAnuncio | null; onClose: () => void }) {
  const { salvarAnuncio, publicarAnuncio, portal } = useMarketYEPortal();
  const { data: cats } = useMarketYECategorias();
  const [f, setF] = useState({
    nome: anuncio?.nome ?? "", descricao: anuncio?.descricao ?? "", categoria_id: anuncio?.categoria_id ?? "", modalidade: anuncio?.modalidade ?? "presencial",
    tipo_preco: anuncio?.tipo_preco ?? "sob_orcamento", preco_referencia: anuncio?.preco_referencia?.toString() ?? "", preco_minimo: anuncio?.preco_minimo?.toString() ?? "", preco_maximo: anuncio?.preco_maximo?.toString() ?? "",
    prazo_tipico: anuncio?.prazo_tipico ?? "", politica_cancelamento: anuncio?.politica_cancelamento ?? "", tags: (anuncio?.tags ?? []).join(", "), base_legal: anuncio?.base_legal ?? "",
    promocao_percentual: anuncio?.promocao_percentual?.toString() ?? "", promocao_fim: anuncio?.promocao_fim ?? "", promocao_descricao: anuncio?.promocao_descricao ?? "",
    publico_alvo: anuncio?.publico_alvo ?? "", gerado_por_ia: anuncio?.gerado_por_ia ?? false,
  });
  const [ia, setIa] = useState({ oque: "", carregando: false, sugestaoPreco: "" });
  const set = (k: keyof typeof f, v: unknown) => setF((x) => ({ ...x, [k]: v }));
  const cat = cats?.todas.find((c) => c.id === f.categoria_id);

  const gerarIA = async () => {
    if (!ia.oque && !f.nome) return toast.error("Diga em uma frase o que você faz");
    setIa((s) => ({ ...s, carregando: true }));
    try {
      const r = await marketyeIA<{ titulo: string; descricao: string; tags: string[]; categoria_slug?: string; tipo_preco?: string; preco_sugerido?: number; preco_minimo?: number; preco_maximo?: number; justificativa_preco?: string; base_legal?: string; publico_alvo?: string }>("gerar_anuncio", {
        o_que_faz: ia.oque || f.nome, categoria: cat?.nome, conselho: portal.data?.perfil.conselho, cidade: portal.data?.perfil.cidade, uf: portal.data?.perfil.estado, modalidade: f.modalidade,
        categorias: (cats?.todas ?? []).map((c) => ({ slug: c.slug, nome: c.nome, obrigacao_legal: c.obrigacao_legal })),
      });
      const catSug = r.categoria_slug ? cats?.todas.find((c) => c.slug === r.categoria_slug) : undefined;
      setF((x) => ({
        ...x, nome: r.titulo || x.nome, descricao: r.descricao || x.descricao, tags: (r.tags ?? []).join(", ") || x.tags, categoria_id: x.categoria_id || catSug?.id || "",
        tipo_preco: r.tipo_preco || x.tipo_preco, preco_referencia: r.preco_sugerido != null ? String(r.preco_sugerido) : x.preco_referencia,
        preco_minimo: r.preco_minimo != null ? String(r.preco_minimo) : x.preco_minimo, preco_maximo: r.preco_maximo != null ? String(r.preco_maximo) : x.preco_maximo,
        base_legal: r.base_legal || x.base_legal, publico_alvo: r.publico_alvo || x.publico_alvo, gerado_por_ia: true,
      }));
      setIa((s) => ({ ...s, sugestaoPreco: r.justificativa_preco ?? "" }));
      toast.success("Rascunho gerado. Revise, ajuste o preço (ele é seu) e publique.");
    } catch (e) { toast.error(e instanceof Error ? e.message : "A IA não respondeu"); } finally { setIa((s) => ({ ...s, carregando: false })); }
  };

  const montar = () => ({
    id: anuncio?.id, nome: f.nome, descricao: f.descricao, categoria_id: f.categoria_id || null, modalidade: f.modalidade, tipo_preco: f.tipo_preco,
    preco_referencia: f.preco_referencia ? Number(f.preco_referencia) : null, preco_minimo: f.preco_minimo ? Number(f.preco_minimo) : null, preco_maximo: f.preco_maximo ? Number(f.preco_maximo) : null,
    prazo_tipico: f.prazo_tipico || null, politica_cancelamento: f.politica_cancelamento || null, tags: f.tags.split(",").map((t) => t.trim()).filter(Boolean), base_legal: f.base_legal || null,
    promocao_percentual: f.promocao_percentual ? Number(f.promocao_percentual) : null, promocao_inicio: f.promocao_percentual ? format(new Date(), "yyyy-MM-dd") : null, promocao_fim: f.promocao_fim || null,
    promocao_descricao: f.promocao_descricao || null, publico_alvo: f.publico_alvo || null, gerado_por_ia: f.gerado_por_ia,
  });
  const salvar = async (publicar: boolean) => {
    try {
      const r = await salvarAnuncio.mutateAsync(montar());
      if (publicar) await publicarAnuncio.mutateAsync(r.id);
      onClose();
    } catch { /* toasts já emitidos */ }
  };

  return (
    <Dialog open onOpenChange={(v) => { if (!v) onClose(); }}>
      <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader><DialogTitle>{anuncio ? "Editar anúncio" : "Novo anúncio"}</DialogTitle></DialogHeader>
        <div className="space-y-4">
          {!anuncio && (
            <div className="rounded-xl border border-violet-200 bg-violet-50 p-3 space-y-2">
              <Label className="text-violet-900 flex items-center gap-1"><Sparkles className="w-4 h-4" />Em uma frase: o que você faz?</Label>
              <div className="flex gap-2">
                <Input value={ia.oque} onChange={(e) => setIa((s) => ({ ...s, oque: e.target.value }))} placeholder="Ex.: faço laudo LTCAT e PGR para indústrias de médio porte no Paraná" />
                <Button type="button" onClick={gerarIA} disabled={ia.carregando}>{ia.carregando ? <Loader2 className="w-4 h-4 animate-spin" /> : "Gerar com IA"}</Button>
              </div>
              <p className="text-[11px] text-violet-800">A IA sugere título, descrição, tags, categoria e uma faixa de preço por categoria e região. O preço final é sempre seu.</p>
            </div>
          )}
          <div className="grid sm:grid-cols-2 gap-3">
            <div className="sm:col-span-2"><Label>Título*</Label><Input value={f.nome} onChange={(e) => set("nome", e.target.value)} /></div>
            <div className="sm:col-span-2"><Label>Descrição* (sem telefone, e-mail ou link)</Label><Textarea rows={5} value={f.descricao} onChange={(e) => set("descricao", e.target.value)} /></div>
            <div><Label>Categoria</Label>
              <Select value={f.categoria_id} onValueChange={(v) => set("categoria_id", v)}><SelectTrigger><SelectValue placeholder="Selecione" /></SelectTrigger>
                <SelectContent>{(cats?.raizes ?? []).map((r) => [<SelectItem key={r.id} value={r.id}>{r.nome}</SelectItem>, ...(r.filhas ?? []).map((c) => <SelectItem key={c.id} value={c.id}>&nbsp;&nbsp;— {c.nome}{c.exige_registro ? " (exige registro)" : ""}</SelectItem>)])}</SelectContent>
              </Select>
              {cat?.obrigacao_legal?.length ? <p className="text-[11px] text-muted-foreground mt-1">Amarrado a {cat.obrigacao_legal.join(", ")}: entra no matching dos alertas das empresas.</p> : null}
            </div>
            <div><Label>Modalidade</Label>
              <Select value={f.modalidade} onValueChange={(v) => set("modalidade", v)}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="presencial">Presencial</SelectItem><SelectItem value="online">Remoto</SelectItem><SelectItem value="hibrido">Híbrido</SelectItem></SelectContent></Select>
            </div>
            <div><Label>Tipo de preço</Label>
              <Select value={f.tipo_preco} onValueChange={(v) => set("tipo_preco", v)}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="sob_orcamento">Sob orçamento</SelectItem><SelectItem value="hora">Por hora</SelectItem><SelectItem value="visita">Por visita</SelectItem><SelectItem value="pacote">Pacote</SelectItem><SelectItem value="mensal">Mensal</SelectItem></SelectContent></Select>
            </div>
            <div><Label>Preço-base (R$)</Label><Input type="number" value={f.preco_referencia} onChange={(e) => set("preco_referencia", e.target.value)} disabled={f.tipo_preco === "sob_orcamento"} /></div>
            <div><Label>Faixa mínima (R$)</Label><Input type="number" value={f.preco_minimo} onChange={(e) => set("preco_minimo", e.target.value)} /></div>
            <div><Label>Faixa máxima (R$)</Label><Input type="number" value={f.preco_maximo} onChange={(e) => set("preco_maximo", e.target.value)} /></div>
            {ia.sugestaoPreco && <p className="sm:col-span-2 text-[11px] text-muted-foreground">Sugestão da IA: {ia.sugestaoPreco}</p>}
            <div><Label>Prazo típico</Label><Input value={f.prazo_tipico} onChange={(e) => set("prazo_tipico", e.target.value)} placeholder="Ex.: 10 dias úteis" /></div>
            <div><Label>Base legal</Label><Input value={f.base_legal} onChange={(e) => set("base_legal", e.target.value)} placeholder="Ex.: NR-1" /></div>
            <div className="sm:col-span-2"><Label>Tags (separadas por vírgula)</Label><Input value={f.tags} onChange={(e) => set("tags", e.target.value)} /></div>
            <div className="sm:col-span-2"><Label>Política de cancelamento</Label><Input value={f.politica_cancelamento} onChange={(e) => set("politica_cancelamento", e.target.value)} /></div>
            <div><Label>Promoção (%)</Label><Input type="number" value={f.promocao_percentual} onChange={(e) => set("promocao_percentual", e.target.value)} /></div>
            <div><Label>Promoção até</Label><Input type="date" value={f.promocao_fim} onChange={(e) => set("promocao_fim", e.target.value)} /></div>
            <div className="sm:col-span-2"><Label>Descrição da promoção</Label><Input value={f.promocao_descricao} onChange={(e) => set("promocao_descricao", e.target.value)} /></div>
          </div>
          <div className="flex justify-end gap-2">
            <Button variant="outline" disabled={salvarAnuncio.isPending} onClick={() => salvar(false)}>Salvar rascunho</Button>
            <Button className="bg-emerald-600 hover:bg-emerald-700 text-white" disabled={salvarAnuncio.isPending || publicarAnuncio.isPending} onClick={() => salvar(true)}>Salvar e publicar</Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------
function ConversasTab({ leads }: { leads: PortalLead[] }) {
  const [sel, setSel] = useState<PortalLead | null>(null);
  useEffect(() => { if (sel) { const a = leads.find((l) => l.id === sel.id); if (a && a !== sel) setSel(a); } }, [leads, sel]);
  if (leads.length === 0) return <p className="text-sm text-slate-400 py-8 text-center">Nenhuma conversa ainda. Publique anúncios: as empresas encontram você pela obrigação legal que precisam cumprir.</p>;
  return (
    <div className="grid md:grid-cols-[320px_1fr] gap-4">
      <div className="space-y-2 max-h-[70vh] overflow-y-auto pr-1">
        {leads.map((l) => (
          <button key={l.id} onClick={() => setSel(l)} className={`w-full text-left rounded-xl border p-3 transition ${sel?.id === l.id ? "border-[#60ABEF] bg-white/10" : "border-white/10 hover:bg-white/5"}`}>
            <div className="flex items-center justify-between gap-2"><span className="font-medium text-sm text-white truncate">{l.empresa_nome ?? "Empresa"}</span><Badge className="bg-white/10 text-slate-200 text-[10px]">{LEAD_STATUS_LABEL[l.status] ?? l.status}</Badge></div>
            <p className="text-xs text-slate-400 truncate">{l.servico_nome ?? "Contato direto"}{l.obrigacao_legal ? ` · ${l.obrigacao_legal}` : ""}</p>
            <p className="text-xs text-slate-500 truncate mt-1">{l.ultima_mensagem}</p>
            {l.status === "novo" && <p className="text-[10px] text-[#FF8A00] mt-1">aguardando sua resposta</p>}
          </button>
        ))}
      </div>
      <div className="rounded-2xl border border-white/10 bg-white/[0.03] p-4 min-h-[300px]">{sel ? <ThreadEspecialista lead={sel} /> : <p className="text-sm text-slate-400">Selecione uma conversa.</p>}</div>
    </div>
  );
}

function ThreadEspecialista({ lead }: { lead: PortalLead }) {
  const { data: mensagens = [] } = usePortalMensagens(lead.id);
  const { enviarMensagem, statusLead, avaliarEmpresa, contato } = useMarketYEPortal();
  const [texto, setTexto] = useState("");
  const [rascunhoIA, setRascunhoIA] = useState(false);
  const [avaliando, setAvaliando] = useState(false);
  const [contatoInfo, setContatoInfo] = useState<{ liberado: boolean; empresa?: string; solicitante?: string; email?: string; telefone?: string } | null>(null);
  const fim = useRef<HTMLDivElement>(null);
  useEffect(() => { fim.current?.scrollIntoView({ behavior: "smooth" }); }, [mensagens.length]);
  useEffect(() => { setContatoInfo(null); }, [lead.id]);
  const encerrado = lead.status === "perdido" || lead.status === "encerrado";

  const sugerirResposta = async () => {
    setRascunhoIA(true);
    try {
      const r = await marketyeIA<{ resposta: string }>("rascunho_resposta", { conversa: mensagens.map((m) => `${m.autor_tipo}: ${m.texto}`).join("\n"), servico: lead.servico_nome, obrigacao: lead.obrigacao_legal });
      setTexto(r.resposta);
    } catch (e) { toast.error(e instanceof Error ? e.message : "A IA não respondeu"); } finally { setRascunhoIA(false); }
  };
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-start justify-between gap-2 flex-wrap">
        <div>
          <p className="font-semibold text-white flex items-center gap-2"><Building2 className="w-4 h-4" />{lead.empresa_nome ?? "Empresa"}</p>
          <p className="text-xs text-slate-400">{lead.servico_nome ?? "Contato direto"} · {LEAD_STATUS_LABEL[lead.status] ?? lead.status}{lead.reputacao_empresa?.media ? ` · empresa ${lead.reputacao_empresa.media}★ (${lead.reputacao_empresa.total})` : ""}{lead.cupom_codigo ? ` · cupom ${lead.cupom_codigo}` : ""}</p>
        </div>
        <div className="flex gap-1.5 flex-wrap">
          {lead.contato_liberado && <Button size="sm" variant="outline" className="border-white/20 bg-transparent text-slate-100 hover:bg-white/10" onClick={async () => { try { setContatoInfo(await contato(lead.id)); } catch (e) { toast.error(e instanceof Error ? e.message : "Erro"); } }}><Phone className="w-3.5 h-3.5 mr-1" />Ver contato</Button>}
          {!encerrado && lead.status !== "ganho" && <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700 text-white" onClick={() => statusLead.mutate({ lead_id: lead.id, status: "ganho" })}><CheckCircle2 className="w-3.5 h-3.5 mr-1" />Serviço combinado</Button>}
          {!encerrado && <Button size="sm" variant="ghost" className="text-slate-300" onClick={() => statusLead.mutate({ lead_id: lead.id, status: "encerrado", motivo: "Encerrada pelo especialista (sem reflexo na reputação)." })}>Recusar / encerrar</Button>}
          {lead.status === "ganho" && !lead.avaliei && <Button size="sm" className="bg-amber-500 hover:bg-amber-600 text-white" onClick={() => setAvaliando(true)}><Star className="w-3.5 h-3.5 mr-1" />Avaliar empresa</Button>}
        </div>
      </div>
      {contatoInfo?.liberado && (
        <div className="rounded-xl bg-emerald-500/10 border border-emerald-400/30 p-3 text-sm space-y-1 text-emerald-100">
          <p className="font-medium">{contatoInfo.empresa}{contatoInfo.solicitante ? ` · ${contatoInfo.solicitante}` : ""}</p>
          {contatoInfo.email && <p className="flex items-center gap-1.5"><Mail className="w-3.5 h-3.5" />{contatoInfo.email}</p>}
          {contatoInfo.telefone && <p className="flex items-center gap-1.5"><Phone className="w-3.5 h-3.5" />{contatoInfo.telefone}</p>}
        </div>
      )}
      <div className="space-y-2 max-h-[40vh] overflow-y-auto pr-1">
        {mensagens.map((m) => (
          <div key={m.id} className={`text-sm rounded-xl px-3 py-2 max-w-[85%] ${m.autor_tipo === "especialista" ? "ml-auto bg-[#60ABEF]/20 text-white" : m.autor_tipo === "cliente" ? "bg-white/10 text-slate-100" : "mx-auto bg-amber-500/10 text-amber-100 text-xs text-center"}`}>
            <p className="whitespace-pre-wrap">{m.texto}</p>
            <p className="text-[10px] opacity-60 mt-0.5">{format(new Date(m.created_at), "dd/MM HH:mm", { locale: ptBR })}</p>
          </div>
        ))}
        <div ref={fim} />
      </div>
      {!encerrado && (
        <div className="space-y-2">
          <Textarea className={inputCls} value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} placeholder="Responda com prazos, escopo e valores. Contatos diretos ficam ocultos até a empresa liberar." />
          <div className="flex justify-between gap-2 flex-wrap">
            <Button size="sm" variant="ghost" className="text-slate-300" onClick={sugerirResposta} disabled={rascunhoIA}>{rascunhoIA ? <Loader2 className="w-3.5 h-3.5 mr-1 animate-spin" /> : <Sparkles className="w-3.5 h-3.5 mr-1" />}Rascunho com IA</Button>
            <Button size="sm" className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" disabled={enviarMensagem.isPending || !texto.trim()} onClick={() => { enviarMensagem.mutate({ lead_id: lead.id, texto: texto.trim() }); setTexto(""); }}><Send className="w-3.5 h-3.5 mr-1" />Enviar</Button>
          </div>
          <p className="text-[11px] text-slate-500">Responder rápido melhora sua saúde recente, mas não responder nunca gera penalidade: é sinal, não obrigação.</p>
        </div>
      )}
      <AvaliacaoCriteriosModal open={avaliando} onClose={() => setAvaliando(false)} titulo="Avaliar a empresa" subtitulo={lead.empresa_nome ?? undefined} criterios={CRITERIOS_EMPRESA} isLoading={avaliarEmpresa.isPending}
        onEnviar={(notas, comentario) => avaliarEmpresa.mutate({ lead_id: lead.id, notas, comentario }, { onSuccess: () => setAvaliando(false) })} />
    </div>
  );
}

// ---------------------------------------------------------------------
function ReputacaoTab({ d }: { d: NonNullable<ReturnType<typeof useMarketYEPortal>["portal"]["data"]> }) {
  const { responderAvaliacao, contestar } = useMarketYEPortal();
  const rep = d.reputacao;
  const req = d.nivel.requisitos_proximo;
  const [resp, setResp] = useState<Record<string, string>>({});
  const reqLabel: Record<string, string> = { servicos: "Serviços combinados", clientes_unicos: "Empresas distintas", media: "Média de avaliação", taxa_resposta: "Taxa de resposta", ocorrencias: "Ocorrências no período (máx.)" };
  const atual: Record<string, number | string> = { servicos: rep?.servicos_concluidos_total ?? 0, clientes_unicos: rep?.clientes_unicos_total ?? 0, media: Number(d.perfil.nota_media ?? 0).toFixed(1), taxa_resposta: rep?.taxa_resposta_90d != null ? Number(rep.taxa_resposta_90d).toFixed(2) : "—", ocorrencias: rep?.ocorrencias_90d ?? 0 };
  return (
    <div className="space-y-4">
      <div className="grid md:grid-cols-2 gap-4">
        <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
          <h3 className="font-semibold text-white flex items-center gap-2"><Activity className="w-4 h-4" />Eixo A · saúde recente (90 dias)</h3>
          <div className="flex items-center gap-3"><span className={`w-3 h-3 rounded-full ${saudeCor[rep?.saude_cor ?? "cinza"]}`} /><span className="text-2xl font-bold text-white">{rep ? Math.round(Number(rep.saude_score)) : "—"}<span className="text-sm text-slate-400">/100</span></span></div>
          <ul className="text-xs text-slate-300 space-y-1">
            <li>Média recente: {rep?.media_90d ?? "—"} ({rep?.avaliacoes_90d ?? 0} avaliações)</li>
            <li>Taxa de resposta: {rep?.taxa_resposta_90d != null ? `${Math.round(Number(rep.taxa_resposta_90d) * 100)}%` : "sem leads no período"}</li>
            <li>Tempo mediano de resposta: {rep?.tempo_resposta_mediano_min != null ? `${Math.round(rep.tempo_resposta_mediano_min)} min` : "—"}</li>
            <li>Cancelamentos: {rep?.taxa_cancelamento_90d != null ? `${Math.round(Number(rep.taxa_cancelamento_90d) * 100)}%` : "—"} · Ocorrências: {rep?.ocorrencias_90d ?? 0}</li>
            {rep?.abaixo_piso && <li className="text-amber-200">Abaixo do piso de nota: visibilidade orgânica reduzida até a média subir. Continua livre para trabalhar e precificar.</li>}
            {rep?.protegido_ate && new Date(rep.protegido_ate) > new Date() && <li className="text-[#60ABEF]">Proteção ao novato até {format(new Date(rep.protegido_ate), "dd/MM/yyyy")}: impulso de exploração na vitrine.</li>}
          </ul>
        </div>
        <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
          <h3 className="font-semibold text-white flex items-center gap-2"><Users className="w-4 h-4" />Eixo B · nível {NIVEL_LABEL[d.nivel.atual] ?? d.nivel.atual}</h3>
          <p className="text-xs text-slate-400">Sobe com todas as métricas ao mesmo tempo. Só afeta visibilidade e benefícios; nunca sua capacidade de trabalhar.</p>
          {req ? (
            <table className="w-full text-xs"><tbody>{Object.entries(req).map(([k, v]) => <tr key={k} className="border-t border-white/10"><td className="py-1 text-slate-300">{reqLabel[k] ?? k}</td><td className="py-1 text-right text-white">{String(atual[k] ?? "—")} <span className="text-slate-500">/ {k === "ocorrencias" ? `≤ ${v}` : `≥ ${v}`}</span></td></tr>)}</tbody></table>
          ) : <p className="text-xs text-slate-300">Você está no nível máximo.</p>}
          <p className="text-[11px] text-slate-500">Próximo nível: {d.nivel.proximo ? NIVEL_LABEL[d.nivel.proximo] : "—"}. Ordem: {d.nivel.ordem.map((n) => NIVEL_LABEL[n] ?? n).join(" → ")}.</p>
        </div>
      </div>
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-3">
        <h3 className="font-semibold text-white flex items-center gap-2"><Star className="w-4 h-4 text-amber-400" />Avaliações recebidas</h3>
        {d.avaliacoes.length === 0 ? <p className="text-xs text-slate-400">Nenhuma avaliação ainda.</p> : d.avaliacoes.map((a) => (
          <div key={a.id} className="border-t border-white/10 pt-2 space-y-1">
            <p className="text-sm text-white">{Number(a.nota_geral).toFixed(1)}★ <span className="text-xs text-slate-400">· {format(new Date(a.created_at), "dd/MM/yyyy")}</span></p>
            {a.comentario && <p className="text-sm text-slate-300">{a.comentario}</p>}
            {a.resposta ? <p className="text-xs text-slate-400 border-l-2 border-white/20 pl-2">Sua resposta: {a.resposta}</p> : (
              <div className="flex gap-2"><Input className={inputCls} placeholder="Direito de resposta (público)" value={resp[a.id] ?? ""} onChange={(e) => setResp((r) => ({ ...r, [a.id]: e.target.value }))} /><Button size="sm" variant="outline" className="border-white/20 bg-transparent text-slate-100" disabled={!(resp[a.id] ?? "").trim()} onClick={() => responderAvaliacao.mutate({ id: a.id, resposta: resp[a.id] })}>Responder</Button>
                <Button size="sm" variant="ghost" className="text-slate-400" onClick={() => contestar.mutate({ tipo: "avaliacao", referencia_id: a.id, motivo: `Contesto a avaliação ${a.id}: ` + (resp[a.id] || "avaliação abusiva ou fora dos critérios profissionais.") })}>Contestar</Button></div>
            )}
          </div>
        ))}
      </div>
      {d.ocorrencias.length > 0 && (
        <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
          <h3 className="font-semibold text-white">Ocorrências</h3>
          {d.ocorrencias.map((o) => <div key={o.id} className="text-xs text-slate-300 flex items-center justify-between gap-2 border-t border-white/10 pt-2"><span>{o.tipo}: {o.descricao ?? ""} · {format(new Date(o.created_at), "dd/MM/yyyy")}{o.reflexo_visibilidade ? " · reflete na visibilidade" : ""}</span><Button size="sm" variant="ghost" className="text-slate-400" onClick={() => contestar.mutate({ tipo: "reflexo_visibilidade", referencia_id: o.id, motivo: `Contesto a ocorrência ${o.id}: discordo do registro e peço revisão por uma pessoa.` })}>Contestar</Button></div>)}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------
function PerfilTab({ d }: { d: NonNullable<ReturnType<typeof useMarketYEPortal>["portal"]["data"]> }) {
  const { salvarPerfil } = useMarketYEPortal();
  const p = d.perfil;
  const [f, setF] = useState({
    telefone: p.telefone ?? "", bio: p.bio ?? "", formacao_academica: p.formacao_academica ?? "", registro_profissional: p.registro_profissional ?? "", conselho: p.conselho ?? "", uf_registro: p.uf_registro ?? "",
    registro_validade: p.registro_validade ?? "", especialidades: (p.especialidades ?? []).join(", "), certificacoes: (p.certificacoes ?? []).join(", "), cidade: p.cidade ?? "", estado: p.estado ?? "",
    modalidades: p.modalidades_atendimento ?? [], atende_remoto: p.atende_remoto, raio_atendimento_km: String(p.raio_atendimento_km ?? 100), politicas: p.politicas ?? "", site_url: p.site_url ?? "", video_url: p.video_url ?? "", foto_url: p.foto_url ?? "",
    disponibilidade: (p.disponibilidade as { dias?: string; horario?: string })?.dias ?? "", horario: (p.disponibilidade as { dias?: string; horario?: string })?.horario ?? "",
  });
  const set = (k: keyof typeof f, v: unknown) => setF((x) => ({ ...x, [k]: v }));
  const toggleMod = (m: string) => set("modalidades", f.modalidades.includes(m) ? f.modalidades.filter((x) => x !== m) : [...f.modalidades, m]);
  return (
    <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-5 grid sm:grid-cols-2 gap-4">
      <p className="sm:col-span-2 text-xs text-slate-400">E-mail: {p.email} · {p.tipo_pessoa === "pj" ? "CNPJ" : "CPF"}: {p.cpf_cnpj ?? "—"} (documento e e-mail não mudam aqui; fale com o atendimento). Preço, horários e políticas são seus e ficam registrados como trilha de autonomia ({d.autonomia_eventos} eventos).</p>
      <div><Label className="text-slate-300">Telefone</Label><Input className={inputCls} value={f.telefone} onChange={(e) => set("telefone", e.target.value)} /></div>
      <div><Label className="text-slate-300">Foto (URL)</Label><Input className={inputCls} value={f.foto_url} onChange={(e) => set("foto_url", e.target.value)} /></div>
      <div className="sm:col-span-2"><Label className="text-slate-300">Apresentação</Label><Textarea className={inputCls} rows={3} value={f.bio} onChange={(e) => set("bio", e.target.value)} /></div>
      <div><Label className="text-slate-300">Formação</Label><Input className={inputCls} value={f.formacao_academica} onChange={(e) => set("formacao_academica", e.target.value)} /></div>
      <div className="grid grid-cols-[1fr_1fr_70px] gap-2">
        <div><Label className="text-slate-300">Conselho</Label><Input className={inputCls} value={f.conselho} onChange={(e) => set("conselho", e.target.value)} /></div>
        <div><Label className="text-slate-300">Registro</Label><Input className={inputCls} value={f.registro_profissional} onChange={(e) => set("registro_profissional", e.target.value)} /></div>
        <div><Label className="text-slate-300">UF</Label><Input className={inputCls} maxLength={2} value={f.uf_registro} onChange={(e) => set("uf_registro", e.target.value.toUpperCase())} /></div>
      </div>
      <div><Label className="text-slate-300">Validade do registro</Label><Input type="date" className={inputCls} value={f.registro_validade} onChange={(e) => set("registro_validade", e.target.value)} /></div>
      <div><Label className="text-slate-300">Especialidades (vírgula)</Label><Input className={inputCls} value={f.especialidades} onChange={(e) => set("especialidades", e.target.value)} /></div>
      <div><Label className="text-slate-300">Certificações (vírgula)</Label><Input className={inputCls} value={f.certificacoes} onChange={(e) => set("certificacoes", e.target.value)} /></div>
      <div><Label className="text-slate-300">Cidade</Label><Input className={inputCls} value={f.cidade} onChange={(e) => set("cidade", e.target.value)} /></div>
      <div><Label className="text-slate-300">UF</Label><Input className={inputCls} maxLength={2} value={f.estado} onChange={(e) => set("estado", e.target.value.toUpperCase())} /></div>
      <div className="sm:col-span-2">
        <Label className="text-slate-300">Modalidades</Label>
        <div className="flex gap-2 mt-1 flex-wrap">
          {[["presencial", "Presencial"], ["online", "Remoto"], ["hibrido", "Híbrido"]].map(([m, l]) => <button key={m} type="button" onClick={() => toggleMod(m)} className={`px-3 py-1.5 rounded-lg border text-sm ${f.modalidades.includes(m) ? "border-[#FF8A00] bg-[#FF8A00]/10 text-white" : "border-white/15 text-slate-300"}`}>{l}</button>)}
          <label className="flex items-center gap-2 text-sm text-slate-300 ml-2"><Checkbox checked={f.atende_remoto} onCheckedChange={(v) => set("atende_remoto", v === true)} className="border-white/40" />Atendo remoto (ignora distância)</label>
        </div>
      </div>
      <div><Label className="text-slate-300">Raio de atendimento (km)</Label><Input type="number" className={inputCls} value={f.raio_atendimento_km} onChange={(e) => set("raio_atendimento_km", e.target.value)} /></div>
      <div><Label className="text-slate-300">Dias de atendimento</Label><Input className={inputCls} value={f.disponibilidade} onChange={(e) => set("disponibilidade", e.target.value)} placeholder="Ex.: seg a sex" /></div>
      <div><Label className="text-slate-300">Horário</Label><Input className={inputCls} value={f.horario} onChange={(e) => set("horario", e.target.value)} placeholder="Ex.: 8h às 18h" /></div>
      <div><Label className="text-slate-300">Site</Label><Input className={inputCls} value={f.site_url} onChange={(e) => set("site_url", e.target.value)} /></div>
      <div><Label className="text-slate-300">Vídeo de apresentação (URL)</Label><Input className={inputCls} value={f.video_url} onChange={(e) => set("video_url", e.target.value)} /></div>
      <div className="sm:col-span-2"><Label className="text-slate-300">Políticas (cancelamento, deslocamento, pagamento)</Label><Textarea className={inputCls} rows={2} value={f.politicas} onChange={(e) => set("politicas", e.target.value)} /></div>
      <div className="sm:col-span-2 flex justify-end">
        <Button className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" disabled={salvarPerfil.isPending} onClick={() => salvarPerfil.mutate({
          telefone: f.telefone, bio: f.bio, formacao_academica: f.formacao_academica, registro_profissional: f.registro_profissional, conselho: f.conselho, uf_registro: f.uf_registro, registro_validade: f.registro_validade || null,
          especialidades: f.especialidades.split(",").map((s) => s.trim()).filter(Boolean), certificacoes: f.certificacoes.split(",").map((s) => s.trim()).filter(Boolean), cidade: f.cidade, estado: f.estado,
          modalidades: f.modalidades, atende_remoto: f.atende_remoto, raio_atendimento_km: Number(f.raio_atendimento_km) || 100, politicas: f.politicas, site_url: f.site_url, video_url: f.video_url, foto_url: f.foto_url,
          disponibilidade: { dias: f.disponibilidade, horario: f.horario },
        })}>Salvar perfil</Button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------
function CuponsTab({ cupons }: { cupons: NonNullable<ReturnType<typeof useMarketYEPortal>["portal"]["data"]>["cupons"] }) {
  const { salvarCupom } = useMarketYEPortal();
  const [f, setF] = useState({ codigo: "", descricao: "", desconto_percentual: "10", validade: "", limite_uso: "" });
  return (
    <div className="grid md:grid-cols-2 gap-4">
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-3">
        <h3 className="font-semibold text-white">Novo cupom</h3>
        <p className="text-xs text-slate-400">O código aparece para a empresa quando ela abre uma conversa. Promoções e cupons sinalizam preço melhor, mas não mudam o ranking orgânico.</p>
        <div><Label className="text-slate-300">Código</Label><Input className={inputCls} value={f.codigo} onChange={(e) => setF({ ...f, codigo: e.target.value.toUpperCase() })} placeholder="PRIMEIRA10" /></div>
        <div><Label className="text-slate-300">Descrição</Label><Input className={inputCls} value={f.descricao} onChange={(e) => setF({ ...f, descricao: e.target.value })} /></div>
        <div className="grid grid-cols-3 gap-2">
          <div><Label className="text-slate-300">Desconto %</Label><Input type="number" className={inputCls} value={f.desconto_percentual} onChange={(e) => setF({ ...f, desconto_percentual: e.target.value })} /></div>
          <div><Label className="text-slate-300">Validade</Label><Input type="date" className={inputCls} value={f.validade} onChange={(e) => setF({ ...f, validade: e.target.value })} /></div>
          <div><Label className="text-slate-300">Limite de uso</Label><Input type="number" className={inputCls} value={f.limite_uso} onChange={(e) => setF({ ...f, limite_uso: e.target.value })} /></div>
        </div>
        <Button className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" disabled={!f.codigo || salvarCupom.isPending} onClick={() => salvarCupom.mutate({ codigo: f.codigo, descricao: f.descricao || null, desconto_percentual: Number(f.desconto_percentual), validade: f.validade || null, limite_uso: f.limite_uso ? Number(f.limite_uso) : null })}>Salvar cupom</Button>
      </div>
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
        <h3 className="font-semibold text-white">Meus cupons</h3>
        {cupons.length === 0 ? <p className="text-xs text-slate-400">Nenhum cupom.</p> : cupons.map((c) => (
          <div key={c.id} className="flex items-center justify-between gap-2 border-t border-white/10 pt-2 text-sm">
            <div><p className="text-white font-mono">{c.codigo} <span className="text-xs text-slate-400">-{c.desconto_percentual}%</span></p><p className="text-xs text-slate-400">{c.descricao ?? ""}{c.validade ? ` · até ${format(new Date(c.validade), "dd/MM/yyyy")}` : ""} · {c.usos} uso(s){c.limite_uso ? `/${c.limite_uso}` : ""}</p></div>
            <Button size="sm" variant="ghost" className="text-slate-300" onClick={() => salvarCupom.mutate({ codigo: c.codigo, descricao: c.descricao, desconto_percentual: c.desconto_percentual, validade: c.validade, limite_uso: c.limite_uso, ativo: !c.ativo })}>{c.ativo ? "Desativar" : "Reativar"}</Button>
          </div>
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------
function ContaTab({ d, onExportar, onExcluir }: { d: NonNullable<ReturnType<typeof useMarketYEPortal>["portal"]["data"]>; onExportar: () => void; onExcluir: () => void }) {
  const { contestar } = useMarketYEPortal();
  const [motivo, setMotivo] = useState("");
  const podeContestarCadastro = d.perfil.moderacao_resultado === "rejeitado" || d.perfil.status === "suspenso";
  const tipoLabel: Record<string, string> = { rejeicao_cadastro: "Rejeição do cadastro", suspensao: "Suspensão", remocao_anuncio: "Remoção de anúncio", ajuste_nivel: "Ajuste de nível", reflexo_visibilidade: "Reflexo na visibilidade", avaliacao: "Avaliação", outro: "Outro" };
  return (
    <div className="grid md:grid-cols-2 gap-4">
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
        <h3 className="font-semibold text-white flex items-center gap-2"><ShieldCheck className="w-4 h-4" />Termos aceitos</h3>
        <ul className="text-xs text-slate-300 space-y-1">{d.consentimentos.map((c) => <li key={c.id}>{TERMO_LABEL[c.tipo] ?? c.tipo} · versão {c.versao} · {format(new Date(c.aceito_em), "dd/MM/yyyy HH:mm")}</li>)}</ul>
        <p className="text-[11px] text-slate-500">Sem exclusividade. Você define preço, horários e políticas, pode atender fora do MarketYE e recusar leads sem reflexo. O YourEyes conecta; a execução do serviço é sua.</p>
        {d.parceiro && <p className="text-xs text-[#60ABEF]">Você também é parceiro do canal de vendas: <Link to="/parceiro" className="underline">Área do Parceiro</Link>. Comissões e leads ficam separados.</p>}
        {!d.parceiro && <p className="text-xs text-slate-400">Quer também indicar empresas e receber comissão? <Link to="/parceiros" className="underline">Programa de Parceiros</Link> (papel separado, mesma conta).</p>}
      </div>
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-2">
        <h3 className="font-semibold text-white flex items-center gap-2"><Gavel className="w-4 h-4" />Contestações (canal único)</h3>
        <p className="text-xs text-slate-400">Qualquer decisão sobre seu perfil (rejeição, suspensão, remoção, reflexo na visibilidade) pode ser contestada. Uma pessoa da YourEyes decide e responde aqui, com trilha.</p>
        {podeContestarCadastro && (
          <div className="space-y-2">
            <Textarea className={inputCls} rows={3} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Explique por que discorda da decisão e o que anexa como evidência." />
            <Button size="sm" className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" disabled={motivo.trim().length < 10 || contestar.isPending} onClick={() => contestar.mutate({ tipo: d.perfil.status === "suspenso" ? "suspensao" : "rejeicao_cadastro", referencia_id: d.perfil.id, motivo }, { onSuccess: () => setMotivo("") })}>Abrir contestação</Button>
          </div>
        )}
        {d.contestacoes.length === 0 ? <p className="text-xs text-slate-500">Nenhuma contestação.</p> : d.contestacoes.map((c) => (
          <div key={c.id} className="border-t border-white/10 pt-2 text-xs text-slate-300">
            <p><b className="text-white">{tipoLabel[c.decisao_tipo] ?? c.decisao_tipo}</b> · {c.status} · {format(new Date(c.created_at), "dd/MM/yyyy")}</p>
            <p>{c.motivo}</p>
            {c.resposta && <p className="text-slate-400 border-l-2 border-white/20 pl-2 mt-1">Resposta: {c.resposta}</p>}
          </div>
        ))}
      </div>
      <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-4 space-y-3 md:col-span-2">
        <h3 className="font-semibold text-white">Seus dados (LGPD)</h3>
        <p className="text-xs text-slate-400">Você pode exportar tudo o que o MarketYE guarda sobre você e pedir a exclusão do perfil. Registros de conversas e avaliações ficam pelo prazo legal, anonimizados.</p>
        <div className="flex gap-2 flex-wrap">
          <Button variant="outline" className="border-white/20 bg-transparent text-slate-100 hover:bg-white/10" onClick={onExportar}><Download className="w-4 h-4 mr-1" />Exportar meus dados</Button>
          <Button variant="outline" className="border-red-400/40 bg-transparent text-red-200 hover:bg-red-500/10" onClick={onExcluir}><Trash2 className="w-4 h-4 mr-1" />Excluir meu perfil</Button>
        </div>
      </div>
    </div>
  );
}
