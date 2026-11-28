// supabase/functions/send-email-otp/index.ts
// Sends a 6-digit verification code to the email address a customer is signing up with.
//
// Secrets (choose ONE way to send mail):
//   Gmail:  SMTP_USER (your Gmail address), SMTP_PASS (a Google "app password")
//           optional: SMTP_HOST (default smtp.gmail.com), SMTP_PORT (default 465)
//   Brevo:  BREVO_API_KEY and MAIL_FROM_EMAIL (a sender address verified in Brevo)
// Optional: MAIL_FROM_NAME (default "Wacky Water"), OTP_PEPPER (any long random text)

import { createClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const CODE_MINUTES = 10;
const RESEND_SECONDS = 60;
const MAX_PER_EMAIL_PER_HOUR = 5;
const MAX_PER_IP_PER_HOUR = 15;

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

function newCode(): string {
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000;
  return n.toString().padStart(6, "0");
}

async function sendMail(to: string, code: string): Promise<void> {
  const fromName = Deno.env.get("MAIL_FROM_NAME") ?? "Wacky Water";
  const subject = `Your Wacky Water verification code: ${code}`;
  const text =
    `Your Wacky Water verification code is ${code}.\n\nIt expires in ${CODE_MINUTES} minutes. ` +
    `If you did not try to create an account, you can ignore this email.`;
  const html =
    `<div style="font-family:Arial,sans-serif;max-width:420px;margin:auto;padding:24px">` +
    `<h2 style="color:#0369A1;margin:0 0 8px">Wacky Water</h2>` +
    `<p>Use this code to verify your email address:</p>` +
    `<p style="font-size:34px;font-weight:bold;letter-spacing:8px;background:#F0F9FF;padding:16px;text-align:center;border-radius:12px;margin:16px 0">${code}</p>` +
    `<p style="color:#64748B;font-size:13px">It expires in ${CODE_MINUTES} minutes. If you did not try to create an account, ignore this email.</p></div>`;

  const brevoKey = Deno.env.get("BREVO_API_KEY");
  if (brevoKey) {
    const fromEmail = Deno.env.get("MAIL_FROM_EMAIL");
    if (!fromEmail) throw new Error("MAIL_FROM_EMAIL is not set");
    const res = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": brevoKey, "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        sender: { name: fromName, email: fromEmail },
        to: [{ email: to }],
        subject,
        htmlContent: html,
        textContent: text,
      }),
    });
    if (!res.ok) throw new Error(`Brevo error ${res.status}: ${(await res.text()).slice(0, 200)}`);
    return;
  }

  const user = Deno.env.get("SMTP_USER");
  const pass = Deno.env.get("SMTP_PASS");
  if (!user || !pass) throw new Error("NOT_CONFIGURED");
  const port = Number(Deno.env.get("SMTP_PORT") ?? "465");
  const transporter = nodemailer.createTransport({
    host: Deno.env.get("SMTP_HOST") ?? "smtp.gmail.com",
    port,
    secure: port === 465,
    auth: { user, pass },
  });
  await transporter.sendMail({ from: `"${fromName}" <${user}>`, to, subject, text, html });
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
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 120) {
    return json({ error: "Please enter a valid email address." }, 400);
  }

  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: taken } = await admin.rpc("email_is_registered", { p_email: email });
    if (taken === true) {
      return json({ error: "An account with this email already exists. Please log in." }, 409);
    }

    const ip = (req.headers.get("x-forwarded-for") ?? "unknown").split(",")[0].trim();
    const hourAgo = new Date(Date.now() - 3600_000).toISOString();

    const { data: recent } = await admin
      .from("email_otps")
      .select("created_at")
      .eq("email", email)
      .gte("created_at", hourAgo)
      .order("created_at", { ascending: false });
    if ((recent?.length ?? 0) >= MAX_PER_EMAIL_PER_HOUR) {
      return json({ error: "Too many codes requested for this email. Please try again in an hour." }, 429);
    }
    if (recent && recent.length > 0) {
      const wait = RESEND_SECONDS - Math.floor((Date.now() - new Date(recent[0].created_at).getTime()) / 1000);
      if (wait > 0) return json({ error: `Please wait ${wait} seconds before asking for a new code.`, wait_seconds: wait }, 429);
    }
    const { count: ipCount } = await admin
      .from("email_otps").select("id", { count: "exact", head: true }).eq("ip", ip).gte("created_at", hourAgo);
    if ((ipCount ?? 0) >= MAX_PER_IP_PER_HOUR) {
      return json({ error: "Too many attempts from this device. Please try again later." }, 429);
    }

    const code = newCode();
    const { data: row, error: insErr } = await admin
      .from("email_otps")
      .insert({
        email,
        ip,
        code_hash: await sha256Hex(`${email}:${code}:${pepper()}`),
        expires_at: new Date(Date.now() + CODE_MINUTES * 60_000).toISOString(),
      })
      .select("id")
      .single();
    if (insErr || !row) throw insErr ?? new Error("insert failed");

    try {
      await sendMail(email, code);
    } catch (e) {
      await admin.from("email_otps").delete().eq("id", row.id); // do not use up the cooldown
      if (e instanceof Error && e.message === "NOT_CONFIGURED") {
        console.error("Email sending is not configured (set SMTP_USER/SMTP_PASS or BREVO_API_KEY).");
        return json({ error: "Email verification is not available right now. Please try again later." }, 503);
      }
      console.error("sending email failed:", e);
      return json({ error: "We could not send the email. Check the address and try again." }, 502);
    }

    return json({ ok: true, expires_in_minutes: CODE_MINUTES, resend_after_seconds: RESEND_SECONDS });
  } catch (e) {
    console.error("send-email-otp error:", e);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
