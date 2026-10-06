// Trades a username + password for the account's email, so the app can then
// sign in with Supabase Auth (which only takes an email).
//
// The check and the rate limits live in the database function
// public.email_for_sign_in (schema.sql), which only this function may call.
// This function's job is to pass it the caller's real network address:
// Supabase's proxy sets cf-connecting-ip itself, while the app could put
// anything in x-forwarded-for's first entry, so that header is only a
// fallback, and then its last entry (the one the proxy appended).
//
// Request:  POST {"username": "...", "password": "..."}
// Response: 200 {"email": "..."} | 401 {"error": "invalid"}
//           | 429 {"error": "too_many_attempts"} | 400 / 500 {"error": ...}

import { createClient } from "jsr:@supabase/supabase-js@2";

const usernamePattern = /^[A-Za-z0-9_]{3,20}$/;

const headers = { "Content-Type": "application/json" };

function reply(status: number, body: Record<string, string>): Response {
  return new Response(JSON.stringify(body), { status, headers });
}

function callerIp(req: Request): string {
  const cf = req.headers.get("cf-connecting-ip")?.trim();
  if (cf) return cf;
  const forwarded = req.headers.get("x-forwarded-for")?.split(",");
  return forwarded?.[forwarded.length - 1]?.trim() ?? "";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply(405, { error: "method_not_allowed" });

  let username: unknown, password: unknown;
  try {
    ({ username, password } = await req.json());
  } catch {
    return reply(400, { error: "bad_request" });
  }
  if (
    typeof username !== "string" || !usernamePattern.test(username) ||
    typeof password !== "string" || password.length === 0 || password.length > 200
  ) {
    return reply(401, { error: "invalid" });
  }

  const ip = callerIp(req);
  if (!ip) return reply(400, { error: "no_address" });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
  const { data, error } = await admin.rpc("email_for_sign_in", {
    name: username,
    password,
    caller_ip: ip,
  });
  if (error) {
    if (error.message.includes("too_many_attempts")) {
      return reply(429, { error: "too_many_attempts" });
    }
    console.error("email_for_sign_in failed", error.code);
    return reply(500, { error: "server_error" });
  }
  if (typeof data !== "string") return reply(401, { error: "invalid" });
  return reply(200, { email: data });
});
