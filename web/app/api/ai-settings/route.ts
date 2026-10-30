import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { encryptSecret } from "@/lib/crypto";

export const runtime = "nodejs";
const providerSchema = z.enum(["groq", "openai", "xai"]);
const endpoints = {
  groq: "https://api.groq.com/openai/v1",
  openai: "https://api.openai.com/v1",
  xai: "https://api.x.ai/v1"
} as const;

async function getUser(request: NextRequest) {
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const url = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!token || !url || !anon) return null;
  const client = createClient(url, anon, { auth: { persistSession: false }, global: { headers: { Authorization: "Bearer " + token } } });
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) return null;
  return { user: data.user };
}

function adminClient() {
  const url = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("Server Supabase service credentials are not configured.");
  return createClient(url, key, { auth: { persistSession: false } });
}

async function availableModels(provider: keyof typeof endpoints, apiKey: string): Promise<string[]> {
  const response = await fetch(endpoints[provider] + "/models", {
    headers: { Authorization: "Bearer " + apiKey },
    signal: AbortSignal.timeout(12000), cache: "no-store"
  });
  if (!response.ok) throw new Error("Provider validation failed. Check the API key and provider account.");
  const body = await response.json();
  return (body.data || []).map((model: { id?: string }) => model.id).filter((id: unknown): id is string => typeof id === "string").slice(0, 100);
}

export async function GET(request: NextRequest) {
  const auth = await getUser(request);
  if (!auth) return NextResponse.json({ error: "Sign in to manage AI providers." }, { status: 401 });
  try {
    const db = adminClient();
    const { data, error } = await db.from("ai_provider_configs").select("provider,model,enabled,is_default,encrypted_credentials,updated_at").eq("user_id", auth.user.id);
    if (error) throw error;
    const configs = await Promise.all((data || []).map(async row => {
      let models: string[] = [];
      if (row.encrypted_credentials) {
        try {
          const secret = row.encrypted_credentials as { iv: string; tag: string; data: string };
          const { decryptSecret } = await import("@/lib/crypto");
          models = await availableModels(row.provider as keyof typeof endpoints, decryptSecret(secret));
        } catch { models = []; }
      }
      return { provider: row.provider, model: row.model, enabled: row.enabled, is_default: row.is_default, has_key: Boolean(row.encrypted_credentials), updated_at: row.updated_at, models };
    }));
    return NextResponse.json({ configs });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Could not load provider settings." }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  const auth = await getUser(request);
  if (!auth) return NextResponse.json({ error: "Sign in to manage AI providers." }, { status: 401 });
  const parsed = z.object({
    provider: providerSchema,
    apiKey: z.string().min(12).max(500).optional(),
    model: z.string().min(1).max(120),
    enabled: z.boolean().default(true),
    isDefault: z.boolean().default(false)
  }).safeParse(await request.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: "Choose a provider and enter a valid API key and model." }, { status: 400 });
  const { provider, apiKey, model, enabled, isDefault } = parsed.data;
  try {
    const db = adminClient();
    const { data: existing } = await db.from("ai_provider_configs").select("encrypted_credentials").eq("user_id", auth.user.id).eq("provider", provider).maybeSingle();
    let encrypted_credentials = existing?.encrypted_credentials;
    let models: string[] = [];
    if (apiKey) {
      models = await availableModels(provider, apiKey);
      encrypted_credentials = encryptSecret(apiKey);
    } else if (encrypted_credentials) {
      if (enabled) {
        const { decryptSecret } = await import("@/lib/crypto");
        models = await availableModels(provider, decryptSecret(encrypted_credentials as { iv: string; tag: string; data: string }));
      }
    } else {
      return NextResponse.json({ error: "Enter an API key before enabling this provider." }, { status: 400 });
    }
    if (isDefault) {
      const { error: resetError } = await db.from("ai_provider_configs").update({ is_default: false }).eq("user_id", auth.user.id);
      if (resetError) throw resetError;
    }
    const { error } = await db.from("ai_provider_configs").upsert({
      user_id: auth.user.id, provider, model, enabled, is_default: isDefault, encrypted_credentials, updated_at: new Date().toISOString()
    }, { onConflict: "user_id,provider" });
    if (error) throw error;
    return NextResponse.json({ ok: true, provider, model, enabled, is_default: isDefault, has_key: true, models });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Could not validate or save this provider." }, { status: 500 });
  }
}

export async function DELETE(request: NextRequest) {
  const auth = await getUser(request);
  if (!auth) return NextResponse.json({ error: "Sign in to manage AI providers." }, { status: 401 });
  const provider = providerSchema.safeParse(request.nextUrl.searchParams.get("provider"));
  if (!provider.success) return NextResponse.json({ error: "Choose a supported provider." }, { status: 400 });
  try {
    const db = adminClient();
    const { error } = await db.from("ai_provider_configs").delete().eq("user_id", auth.user.id).eq("provider", provider.data);
    if (error) throw error;
    return NextResponse.json({ ok: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Could not remove provider credentials." }, { status: 500 });
  }
}