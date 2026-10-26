import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

// Team management for the I-CAR Recognition Letters staff back end.
// Deployed with verify_jwt = false; the caller's session token is checked below.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

function tempPassword(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(14));
  let out = "";
  for (const b of bytes) out += chars[b % chars.length];
  return out.slice(0, 4) + "-" + out.slice(4, 9) + "-" + out.slice(9);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, service, { auth: { persistSession: false } });

  // Identify the caller from their session token and confirm they are an active admin
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Not signed in" }, 401);
  const { data: who, error: whoErr } = await admin.auth.getUser(token);
  if (whoErr || !who?.user) return json({ error: "Not signed in" }, 401);
  const { data: me } = await admin.from("staff").select("role, active").eq("user_id", who.user.id).maybeSingle();
  if (!me || !me.active || me.role !== "admin") return json({ error: "Only admins can manage the team" }, 403);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Invalid request" }, 400); }
  const action = body?.action;

  if (action === "create_user") {
    const email = String(body.email || "").trim().toLowerCase();
    const full_name = String(body.full_name || "").trim().slice(0, 200);
    const role = body.role === "admin" ? "admin" : "staff";
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "Enter a valid email" }, 400);
    const password = tempPassword();
    const { data, error } = await admin.auth.admin.createUser({
      email, password, email_confirm: true,
      user_metadata: { full_name, must_change_password: true },
    });
    if (error || !data.user) return json({ error: error?.message || "Could not create user" }, 400);
    const { error: insErr } = await admin.from("staff").insert({ user_id: data.user.id, email, full_name, role, active: true });
    if (insErr) {
      await admin.auth.admin.deleteUser(data.user.id);
      return json({ error: insErr.message }, 400);
    }
    return json({ ok: true, user_id: data.user.id, email, temp_password: password });
  }

  if (action === "reset_password") {
    const user_id = String(body.user_id || "");
    const { data: target } = await admin.from("staff").select("user_id, full_name").eq("user_id", user_id).maybeSingle();
    if (!target) return json({ error: "User not found" }, 404);
    const password = tempPassword();
    const { error } = await admin.auth.admin.updateUserById(user_id, {
      password, user_metadata: { full_name: target.full_name, must_change_password: true },
    });
    if (error) return json({ error: error.message }, 400);
    return json({ ok: true, temp_password: password });
  }

  if (action === "set_active") {
    const user_id = String(body.user_id || "");
    const active = !!body.active;
    if (user_id === who.user.id && !active) return json({ error: "You can't deactivate your own account" }, 400);
    const { error } = await admin.from("staff").update({ active }).eq("user_id", user_id);
    if (error) return json({ error: error.message }, 400);
    const { error: banErr } = await admin.auth.admin.updateUserById(user_id, { ban_duration: active ? "none" : "876000h" });
    if (banErr) return json({ error: banErr.message }, 400);
    return json({ ok: true });
  }

  return json({ error: "Unknown action" }, 400);
});
