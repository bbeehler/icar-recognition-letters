import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

// Bulk email for the I-CAR Gold Class certificate app.
// Picks the stores that match the Notify filters (same database function the staff screen uses),
// sends each one a personal email through Resend, and logs it in the store's contact history.
// Deployed with verify_jwt = false; the caller's session token is checked below (any active staff member).
// Secrets: RESEND_API_KEY, MAIL_FROM (e.g. "I-CAR Canada <collisiontraining@aiacanada.com>"), optional MAIL_REPLY_TO.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const MAX_RECIPIENTS = 2000;
const EMAIL_RX = /^[^@\s,;]+@[^@\s,;]+\.[^@\s,;]+$/;
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const fill = (t: string, v: Record<string, string>) =>
  String(t || "").replace(/\{\{\s*(\w+)\s*\}\}/g, (_m, k) => v[k] ?? "").replace(/ +,/g, ",").replace(/^(Hello|Bonjour) ,/m, "$1,");
const isFrench = (prov: string | null) => /^(qc|que|qu[eé]bec)/i.test(String(prov || "").trim());
const firstEmail = (s: string | null) => String(s || "").split(/[;,\s]+/).map((x) => x.trim().toLowerCase()).find((x) => EMAIL_RX.test(x)) || "";
const toHtml = (text: string) =>
  `<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;color:#222">${
    esc(text).replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1">$1</a>').replace(/\n/g, "<br>")
  }</div>`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const admin = createClient(url, service, { auth: { persistSession: false } });

  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Not signed in" }, 401);
  const { data: who, error: whoErr } = await admin.auth.getUser(token);
  if (whoErr || !who?.user) return json({ error: "Not signed in" }, 401);
  const { data: me } = await admin.from("staff").select("user_id, email, full_name, active").eq("user_id", who.user.id).maybeSingle();
  if (!me || !me.active) return json({ error: "Not authorized" }, 403);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Invalid request" }, 400); }
  const mode = ["preview", "test", "send"].includes(body?.mode) ? body.mode : "preview";
  const f = body?.filters || {};
  const filters = {
    status: String(f.status || "all"), q: String(f.q || ""), exp: /^\d{4}-\d{2}$/.test(f.exp || "") ? f.exp : null,
    level: ["gold", "aluminum"].includes(f.level) ? f.level : "all", skip_days: Math.max(0, Math.min(365, +f.skip_days || 0)),
  };
  const langMode = ["en", "fr"].includes(body?.lang) ? body.lang : "auto";
  const publicUrl = String(body?.public_url || "").replace(/[?#].*$/, "");
  if (!/^https:\/\//.test(publicUrl) && mode !== "preview") return json({ error: "Missing the public page address" }, 400);
  const tpl = {
    en: { subject: String(body?.subject_en || ""), body: String(body?.body_en || "") },
    fr: { subject: String(body?.subject_fr || ""), body: String(body?.body_fr || "") },
  };

  // Stores matching the filters, using the staff member's own session (same rules as the Notify screen)
  const asUser = createClient(url, anon, { auth: { persistSession: false }, global: { headers: { Authorization: `Bearer ${token}` } } });
  const rows: any[] = [];
  for (let i = 0; i < 20; i++) {
    const { data, error } = await asUser.rpc("get_customer_list", {
      p_program: "gold_class", p_q: filters.q, p_status: filters.status, p_limit: 500, p_offset: i * 500, p_expires: filters.exp,
    });
    if (error) return json({ error: error.message }, 400);
    rows.push(...(data?.rows || []));
    if ((data?.rows || []).length < 500) break;
  }
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "America/Toronto" });
  const cutoff = new Date(Date.now() - filters.skip_days * 864e5).toISOString();
  const current = rows.filter((r) => r.is_active !== false && !(r.expires_on && r.expires_on < today));
  const eligible = current.filter((r) => filters.level === "all" || (filters.level === "aluminum" ? r.aluminum : !r.aluminum));
  const recent = (r: any) => filters.skip_days > 0 && r.last_contact_method === "email" && r.last_contact_at && r.last_contact_at > cutoff;
  const withEmail = eligible.filter((r) => firstEmail(r.contact_email));
  const skippedRecent = withEmail.filter(recent);
  const recipients = withEmail.filter((r) => !recent(r));
  const langOf = (r: any) => (langMode === "auto" ? (isFrench(r.province) ? "fr" : "en") : langMode) as "en" | "fr";

  const summary = {
    matched: rows.length, eligible: eligible.length, with_email: withEmail.length,
    without_email: eligible.length - withEmail.length, skipped_recent: skippedRecent.length,
    excluded_expired_or_off: rows.length - current.length, other_level: current.length - eligible.length,
    recipients: recipients.length,
    english: recipients.filter((r) => langOf(r) === "en").length, french: recipients.filter((r) => langOf(r) === "fr").length,
    sample: recipients.slice(0, 8).map((r) => ({ name: r.display_name, icar_id: r.icar_id, email: firstEmail(r.contact_email), lang: langOf(r) })),
    configured: !!(Deno.env.get("RESEND_API_KEY") && Deno.env.get("MAIL_FROM")),
  };
  if (mode === "preview") return json({ ok: true, ...summary });

  const key = Deno.env.get("RESEND_API_KEY"), from = Deno.env.get("MAIL_FROM"), replyTo = Deno.env.get("MAIL_REPLY_TO") || undefined;
  if (!key || !from) return json({ error: "Email sending isn't set up yet. Add the RESEND_API_KEY and MAIL_FROM secrets in Supabase." }, 503);
  for (const l of ["en", "fr"] as const) {
    const needed = mode === "test" ? recipients.some((r) => langOf(r) === l) || langMode === l : recipients.some((r) => langOf(r) === l);
    if (needed && (!tpl[l].subject.trim() || !tpl[l].body.trim())) return json({ error: `Fill in the ${l === "fr" ? "French" : "English"} subject and message.` }, 400);
  }
  if (mode === "send" && !recipients.length) return json({ error: "No stores with an email address match these filters." }, 400);
  if (recipients.length > MAX_RECIPIENTS) return json({ error: `That's ${recipients.length} stores. Narrow the filters to ${MAX_RECIPIENTS} or fewer.` }, 400);

  const sender = me.full_name || "";
  const build = (r: any, l: "en" | "fr", to: string, test = false) => {
    const contact = String(r.contact_name || "").split(/\s+/)[0] || "";
    const link = `${publicUrl}?${new URLSearchParams({ id: r.icar_id, ...(l === "fr" ? { lang: "fr" } : {}) })}`;
    const program = r.aluminum ? (l === "fr" ? "Gold Class – Aluminium" : "Gold Class – Aluminum") : "Gold Class";
    const v = { contact, name: r.display_name, icar_id: r.icar_id, program, link, sender };
    const text = fill(tpl[l].body, v);
    return { from, to: [to], subject: (test ? "[TEST] " : "") + fill(tpl[l].subject, v), text, html: toHtml(text), ...(replyTo ? { reply_to: replyTo } : {}) };
  };
  const post = async (messages: any[]) => {
    const res = await fetch("https://api.resend.com/emails/batch", {
      method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" }, body: JSON.stringify(messages),
    });
    const out = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(out?.message || out?.error || `Resend error ${res.status}`);
    return out;
  };

  if (mode === "test") {
    const langs = langMode === "auto" ? (["en", "fr"] as const).filter((l) => recipients.some((r) => langOf(r) === l)) : [langMode];
    const pick = (l: string) => recipients.find((r) => langOf(r) === l) || recipients[0] ||
      { display_name: "Sample Collision Centre Ltd.", icar_id: "100001", contact_name: "Alex", aluminum: false };
    const msgs = (langs.length ? langs : ["en"]).map((l) => build(pick(l), l as "en" | "fr", me.email, true));
    try { await post(msgs); } catch (e) { return json({ error: (e as Error).message }, 502); }
    await admin.from("bulk_sends").insert({ created_by: me.user_id, filters, subject_en: tpl.en.subject, subject_fr: tpl.fr.subject, recipients: msgs.length, sent: msgs.length, is_test: true });
    return json({ ok: true, test: true, sent_to: me.email, messages: msgs.length });
  }

  // Real send, in batches of 100; each store that went out gets a contact-history entry
  const { data: rec } = await admin.from("bulk_sends").insert({ created_by: me.user_id, filters: { ...filters, lang: langMode }, subject_en: tpl.en.subject, subject_fr: tpl.fr.subject, recipients: recipients.length })
    .select("id").single();
  let sent = 0, failed = 0; const errors: string[] = [];
  for (let i = 0; i < recipients.length; i += 100) {
    const chunk = recipients.slice(i, i + 100);
    try {
      await post(chunk.map((r) => build(r, langOf(r), firstEmail(r.contact_email))));
      sent += chunk.length;
      await admin.from("customer_contacts").insert(chunk.map((r) => ({
        program: "gold_class", icar_id: r.icar_id, icar_id_norm: String(r.icar_id).toUpperCase().replace(/[^A-Z0-9]/g, ""),
        recipient_name: r.display_name, method: "email", contact_detail: firstEmail(r.contact_email),
        note: `Bulk email #${rec?.id ?? ""} (${langOf(r).toUpperCase()}): ${fill(tpl[langOf(r)].subject, { program: "Gold Class", name: r.display_name })}`.slice(0, 1000),
        contacted_by: me.user_id,
      })));
    } catch (e) { failed += chunk.length; errors.push((e as Error).message); }
  }
  if (rec?.id) await admin.from("bulk_sends").update({ sent, failed, error: errors.length ? errors.slice(0, 3).join(" | ").slice(0, 1000) : null }).eq("id", rec.id);
  return json({ ok: failed === 0, sent, failed, errors: errors.slice(0, 3), id: rec?.id, skipped_recent: summary.skipped_recent, without_email: summary.without_email });
});
