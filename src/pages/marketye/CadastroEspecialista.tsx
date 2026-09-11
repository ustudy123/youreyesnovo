import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Loader2, ShieldCheck } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { supabase } from "@/integrations/supabase/client";
import { useAuthContext } from "@/contexts/AuthContext";
import { MarketYELayout } from "@/components/marketye/MarketYELayout";
import { useMarketYEPublico } from "./MarketYEPublico";
import { validateCpf } from "@/lib/cpf";
import { validateCnpj } from "@/lib/cnpj";
import { geocodeCidade } from "@/lib/nominatim";

const UFS = ["AC","AL","AP","AM","BA","CE","DF","ES","GO","MA","MT","MS","MG","PA","PB","PR","PE","PI","RJ","RN","RS","RO","RR","SC","SP","SE","TO"];
const CONSELHOS = ["CRM", "CREA", "CRP", "CREFITO", "CREF", "COREN", "OAB", "CRC", "CRA", "CRN", "CFFa", "MTE", "Outro", "Não se aplica"];

// Dois caminhos, um formulário (mesmo desenho do Programa de Parceiros):
//  * visitante sem conta → Edge Function marketye-cadastro (cria a conta e o cadastro);
//  * quem já está logado (cliente, parceiro) → função SQL marketye_cadastrar_especialista.
export default function CadastroEspecialista() {
  const navigate = useNavigate();
  const { user, especialistaId, signIn, loading: authLoading } = useAuthContext();
  const { data: publico } = useMarketYEPublico();
  const [f, setF] = useState({
    nome_completo: "", email: user?.email ?? "", senha: "", tipo_pessoa: "pf", cpf_cnpj: "", telefone: "", cidade: "", estado: "",
    categoria_slug: "", conselho: "", registro_profissional: "", uf_registro: "", bio: "", modalidades: ["presencial", "online"] as string[], aceite: false,
  });
  const [enviando, setEnviando] = useState(false);
  const set = (k: keyof typeof f, v: unknown) => setF((x) => ({ ...x, [k]: v }));
  const toggleMod = (m: string) => set("modalidades", f.modalidades.includes(m) ? f.modalidades.filter((x) => x !== m) : [...f.modalidades, m]);
  const versoes = publico?.termos_versoes ?? {};

  if (!authLoading && user && especialistaId) {
    return (
      <MarketYELayout>
        <div className="max-w-lg mx-auto text-center py-16 space-y-4">
          <h1 className="text-2xl font-bold text-white">Você já é especialista do MarketYE</h1>
          <Button asChild className="bg-[#FF8A00] hover:bg-[#e67a00] text-white"><Link to="/marketye/portal">Abrir meu portal</Link></Button>
        </div>
      </MarketYELayout>
    );
  }

  const docLimpo = f.cpf_cnpj.replace(/\D/g, "");
  const docValido = f.tipo_pessoa === "pj" ? validateCnpj(docLimpo) : validateCpf(docLimpo);

  const enviar = async () => {
    if (f.nome_completo.trim().length < 3) return toast.error("Informe o nome (mínimo 3 letras)");
    if (!docValido) return toast.error(f.tipo_pessoa === "pj" ? "CNPJ inválido: confira os dígitos" : "CPF inválido: confira os dígitos");
    if (f.modalidades.length === 0) return toast.error("Escolha ao menos uma modalidade de atendimento");
    if (!f.aceite) return toast.error("É preciso aceitar os Termos do Especialista e a Política de Privacidade");
    setEnviando(true);
    try {
      const geo = f.cidade && f.estado ? await geocodeCidade(f.cidade, f.estado) : null;
      const dados = {
        nome_completo: f.nome_completo.trim(), email: f.email.trim().toLowerCase(), tipo_pessoa: f.tipo_pessoa, cpf_cnpj: docLimpo, telefone: f.telefone || null,
        cidade: f.cidade || null, estado: f.estado || null, latitude: geo?.lat ?? null, longitude: geo?.lng ?? null,
        conselho: f.conselho && f.conselho !== "Não se aplica" ? f.conselho : null, registro_profissional: f.registro_profissional || null, uf_registro: f.uf_registro || null,
        bio: f.bio || null, modalidades: f.modalidades, especialidades: f.categoria_slug ? [publico?.categorias.flatMap((c) => [c, ...c.filhas]).find((c) => c.slug === f.categoria_slug)?.nome ?? f.categoria_slug] : [],
        aceite_termos: true, user_agent: navigator.userAgent, origem: "site",
      };
      if (user) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any).rpc("marketye_cadastrar_especialista", { _dados: dados });
        if (error) throw error;
        toast.success(data?.ja_existia ? "Você já tinha cadastro. Abrindo o portal…" : "Cadastro recebido. Agora complete o perfil e crie seu primeiro anúncio.");
        window.location.assign(`${import.meta.env.BASE_URL.replace(/\/$/, "")}/marketye/portal`);
        return;
      }
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(f.email)) return toast.error("E-mail inválido");
      if (f.senha.length < 6) return toast.error("A senha precisa ter ao menos 6 caracteres");
      const { data, error } = await supabase.functions.invoke("marketye-cadastro", { body: { ...dados, senha: f.senha } });
      const erro = error ? await extrairErro(error) : data?.error;
      if (erro) {
        if (/Já existe uma conta/i.test(erro)) { toast.warning(erro); navigate("/marketye/entrar"); return; }
        throw new Error(erro);
      }
      toast.success("Cadastro recebido. Entrando no seu portal…");
      const { error: loginErr } = await signIn(f.email.trim().toLowerCase(), f.senha);
      if (loginErr) { navigate("/marketye/entrar"); return; }
      navigate("/marketye/portal", { replace: true });
    } catch (e) {
      toast.error(e instanceof Error ? e.message.replace(/^.*?:\s*/, "") : "Não foi possível concluir o cadastro");
    } finally {
      setEnviando(false);
    }
  };

  const inputCls = "bg-black/20 border-white/15 text-white";
  return (
    <MarketYELayout titulo="Cadastro de especialista">
      <div className="max-w-2xl mx-auto" data-testid="marketye-cadastro">
        <h1 className="text-3xl font-bold text-white">Quero me cadastrar no MarketYE</h1>
        <p className="text-slate-300 mt-2">
          {user ? `Você está entrando com a conta ${user.email}. O cadastro de especialista fica ligado a ela (uma identidade, vários papéis).` : "Crie sua conta e seu perfil em um minuto. Já tem conta YourEyes (empresa ou parceiro)? "}
          {!user && <Link to="/marketye/entrar" className="text-[#60ABEF] hover:underline">Entre primeiro</Link>}
        </p>

        <div className="mt-6 rounded-2xl border border-white/10 bg-white/[0.04] p-5 grid grid-cols-2 gap-4">
          <div className="col-span-2"><Label className="text-slate-300">Nome completo ou razão social*</Label><Input data-testid="cad-nome" className={inputCls} value={f.nome_completo} onChange={(e) => set("nome_completo", e.target.value)} /></div>
          <div><Label className="text-slate-300">Pessoa</Label>
            <Select value={f.tipo_pessoa} onValueChange={(v) => set("tipo_pessoa", v)}><SelectTrigger className={inputCls}><SelectValue /></SelectTrigger><SelectContent><SelectItem value="pf">Física (CPF)</SelectItem><SelectItem value="pj">Jurídica (CNPJ)</SelectItem></SelectContent></Select>
          </div>
          <div><Label className="text-slate-300">{f.tipo_pessoa === "pj" ? "CNPJ*" : "CPF*"}</Label><Input data-testid="cad-documento" className={`${inputCls} ${f.cpf_cnpj && !docValido ? "border-red-400" : ""}`} value={f.cpf_cnpj} onChange={(e) => set("cpf_cnpj", e.target.value)} placeholder={f.tipo_pessoa === "pj" ? "00.000.000/0000-00" : "000.000.000-00"} /></div>
          <div><Label className="text-slate-300">Telefone / WhatsApp</Label><Input className={inputCls} value={f.telefone} onChange={(e) => set("telefone", e.target.value)} /></div>
          <div><Label className="text-slate-300">Área principal</Label>
            <Select value={f.categoria_slug} onValueChange={(v) => set("categoria_slug", v)}>
              <SelectTrigger className={inputCls}><SelectValue placeholder="Selecione" /></SelectTrigger>
              <SelectContent>{(publico?.categorias ?? []).map((c) => [<SelectItem key={c.id} value={c.slug}>{c.nome}</SelectItem>, ...c.filhas.map((s) => <SelectItem key={s.id} value={s.slug}>&nbsp;&nbsp;— {s.nome}</SelectItem>)])}</SelectContent>
            </Select>
          </div>
          <div><Label className="text-slate-300">Cidade</Label><Input className={inputCls} value={f.cidade} onChange={(e) => set("cidade", e.target.value)} /></div>
          <div><Label className="text-slate-300">UF</Label>
            <Select value={f.estado} onValueChange={(v) => set("estado", v)}><SelectTrigger className={inputCls}><SelectValue placeholder="UF" /></SelectTrigger><SelectContent>{UFS.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent></Select>
          </div>
          <div><Label className="text-slate-300">Conselho / registro</Label>
            <Select value={f.conselho} onValueChange={(v) => set("conselho", v)}><SelectTrigger className={inputCls}><SelectValue placeholder="Selecione" /></SelectTrigger><SelectContent>{CONSELHOS.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent></Select>
          </div>
          <div className="grid grid-cols-[1fr_80px] gap-2">
            <div><Label className="text-slate-300">Nº do registro</Label><Input className={inputCls} value={f.registro_profissional} onChange={(e) => set("registro_profissional", e.target.value)} /></div>
            <div><Label className="text-slate-300">UF</Label><Input className={inputCls} value={f.uf_registro} maxLength={2} onChange={(e) => set("uf_registro", e.target.value.toUpperCase())} /></div>
          </div>
          <div className="col-span-2">
            <Label className="text-slate-300">Como você atende</Label>
            <div className="flex gap-2 mt-1">
              {[["presencial", "Presencial"], ["online", "Remoto"], ["hibrido", "Híbrido"]].map(([m, l]) => (
                <button key={m} type="button" onClick={() => toggleMod(m)} className={`px-4 py-2 rounded-lg border text-sm transition ${f.modalidades.includes(m) ? "border-[#FF8A00] bg-[#FF8A00]/10 text-white" : "border-white/15 text-slate-300 hover:border-white/30"}`}>{l}</button>
              ))}
            </div>
          </div>
          <div className="col-span-2"><Label className="text-slate-300">Apresentação (opcional, a IA ajuda a escrever o anúncio depois)</Label><Textarea className={inputCls} rows={3} value={f.bio} onChange={(e) => set("bio", e.target.value)} placeholder="Ex.: engenheira de segurança com 8 anos em indústria; faço PGR, LTCAT e treinamentos NR." /></div>
          {!user && (
            <>
              <div><Label className="text-slate-300">E-mail de acesso*</Label><Input data-testid="cad-email" type="email" autoComplete="email" className={inputCls} value={f.email} onChange={(e) => set("email", e.target.value)} /></div>
              <div><Label className="text-slate-300">Senha*</Label><Input type="password" autoComplete="new-password" className={inputCls} value={f.senha} onChange={(e) => set("senha", e.target.value)} /></div>
            </>
          )}
          <div className="col-span-2 rounded-xl border border-white/10 bg-black/20 p-3 text-xs text-slate-300 flex gap-2">
            <ShieldCheck className="w-4 h-4 text-[#60ABEF] shrink-0 mt-0.5" />
            <p>Seu perfil público (nome, área, região, avaliações, selo) ficará visível para as empresas clientes do YourEyes. E-mail, telefone e documentos não aparecem: o contato só sai quando a empresa liberar, numa conversa registrada. Você pode exportar ou excluir seus dados a qualquer momento no portal.</p>
          </div>
          <div className="col-span-2 flex items-start gap-2 text-sm text-slate-300">
            <Checkbox id="aceite" data-testid="cad-aceite" checked={f.aceite} onCheckedChange={(v) => set("aceite", v === true)} className="mt-0.5 border-white/40" />
            <label htmlFor="aceite">Li e aceito os <Link to="/termos-de-uso" className="text-[#60ABEF] hover:underline" target="_blank">Termos do Especialista</Link> (versão {versoes.termos_especialista ?? "vigente"}), a <Link to="/politica-de-privacidade" className="text-[#60ABEF] hover:underline" target="_blank">Política de Privacidade</Link> (versão {versoes.privacidade_nao_usuario ?? "vigente"}) e o Código de Ética. Sem exclusividade: você define preço e horários e pode atender fora do MarketYE. O aceite fica registrado com data e versão.</label>
          </div>
          <div className="col-span-2 flex justify-end">
            <Button className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" disabled={enviando} onClick={enviar} data-testid="cad-enviar">{enviando && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}Concluir cadastro</Button>
          </div>
        </div>
      </div>
    </MarketYELayout>
  );
}

async function extrairErro(error: unknown): Promise<string> {
  const ctx = (error as { context?: Response }).context;
  if (ctx && typeof ctx.json === "function") {
    try { const b = await ctx.json(); if (b?.error) return String(b.error); } catch { /* segue */ }
  }
  return error instanceof Error ? error.message : "Falha ao cadastrar";
}
