// supabase/functions/verify-email-otp/index.ts
// Checks the 6-digit code. If it is right, returns a one-time token that proves the
// email was verified; register-customer requires that token to create the account.

import { createClient } from "npm:@supabase/supabase-js@2";

const MAX_ATTEMPTS = 5;
const TOKEN_MINUTES = 30;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });

async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
const pepper = () => Deno.env.get("OTP_PEPPER") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function sameText(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // deno-lint-ignore no-explicit-any
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request." }, 400);
  }
  const email = String(body.email ?? "").trim().toLowerCase();
  const code = String(body.code ?? "").trim();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "Please enter a valid email address." }, 400);
  if (!/^\d{6}$/.test(code)) return json({ error: "Enter the 6-digit code from your email." }, 400);

  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: row } = await admin
      .from("email_otps")
      .select("id, code_hash, attempts, expires_at, verified_at")
      .eq("email", email)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!row || row.verified_at) return json({ error: "No active code. Please ask for a new code." }, 400);
    if (new Date(row.expires_at).getTime() < Date.now()) {
      return json({ error: "That code has expired. Please ask for a new code." }, 400);
    }
    if (row.attempts >= MAX_ATTEMPTS) {
      return json({ error: "Too many wrong tries. Please ask for a new code." }, 429);
    }

    const given = await sha256Hex(`${email}:${code}:${pepper()}`);
    if (!sameText(given, row.code_hash)) {
      await admin.from("email_otps").update({ attempts: row.attempts + 1 }).eq("id", row.id);
      const left = MAX_ATTEMPTS - (row.attempts + 1);
      return json({ error: left > 0 ? `Wrong code. ${left} ${left === 1 ? "try" : "tries"} left.` : "Too many wrong tries. Please ask for a new code." }, 400);
    }

    const tokenBytes = crypto.getRandomValues(new Uint8Array(32));
    const token = Array.from(tokenBytes).map((b) => b.toString(16).padStart(2, "0")).join("");
    const { error } = await admin
      .from("email_otps")
      .update({
        verified_at: new Date().toISOString(),
        token_hash: await sha256Hex(`${email}:${token}:${pepper()}`),
        token_expires_at: new Date(Date.now() + TOKEN_MINUTES * 60_000).toISOString(),
      })
      .eq("id", row.id);
    if (error) throw error;

    return json({ ok: true, token });
  } catch (e) {
    console.error("verify-email-otp error:", e);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
