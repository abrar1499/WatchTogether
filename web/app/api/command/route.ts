import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { parseCommand, inferCategory } from "@/lib/commands";
import { decryptSecret, type EncryptedSecret } from "@/lib/crypto";
import type { CommandAction } from "@/lib/types";

export const runtime = "nodejs";

const actionSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("create_transaction"), transactionKind: z.enum(["expense","income"]), amount: z.number().positive().max(100000000), description: z.string().min(1).max(160), accountName: z.string().max(80).optional(), categoryName: z.string().max(80).optional(), date: z.enum(["today","yesterday"]).optional() }),
  z.object({ type: z.literal("create_account"), name: z.string().min(1).max(80).optional(), accountType: z.enum(["cash","bank","savings","credit_card","custom"]).optional() }),
  z.object({ type: z.literal("list_accounts") }),
  z.object({ type: z.literal("list_transactions"), period: z.enum(["today","week","month","all"]).optional(), category: z.string().max(80).optional(), limit: z.number().int().min(1).max(50).optional() }),
  z.object({ type: z.literal("summary"), period: z.enum(["today","month","last_month"]) }),
  z.object({ type: z.literal("update_last_amount"), amount: z.number().positive().max(100000000) }),
  z.object({ type: z.literal("delete_last") }),
  z.object({ type: z.literal("undo_last") }),
  z.object({ type: z.literal("transfer"), amount: z.number().positive().max(100000000), fromAccount: z.string().max(80).optional(), toAccount: z.string().max(80).optional() }),
  z.object({ type: z.literal("set_budget"), name: z.string().min(1).max(80), amount: z.number().positive().max(100000000) }),
  z.object({ type: z.literal("budget_remaining") }),
  z.object({ type: z.literal("create_category"), name: z.string().min(1).max(80) }),
  z.object({ type: z.literal("rename_account"), from: z.string().min(1).max(80), to: z.string().min(1).max(80) }),
  z.object({ type: z.literal("rename_category"), from: z.string().min(1).max(80), to: z.string().min(1).max(80) }),
  z.object({ type: z.literal("delete_transaction"), query: z.string().min(1).max(100) }),
  z.object({ type: z.literal("delete_account"), name: z.string().min(1).max(80), confirmed: z.boolean() }),
  z.object({ type: z.literal("update_last_account"), accountName: z.string().min(1).max(80) }),
  z.object({ type: z.literal("update_last_date"), date: z.enum(["today","yesterday"]) }),
  z.object({ type: z.literal("set_opening_balance"), amount: z.number().min(0).max(100000000), accountName: z.string().max(80).optional() }),
  z.object({ type: z.literal("delete_all_month"), confirmed: z.boolean() }),
  z.object({ type: z.literal("help") })
]);

const providerUrls = { groq: "https://api.groq.com/openai/v1", openai: "https://api.openai.com/v1", xai: "https://api.x.ai/v1" } as const;

async function authenticate(request: NextRequest) {
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const url = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!token || !url || !anon) return null;
  const db = createClient(url, anon, { auth: { persistSession: false }, global: { headers: { Authorization: "Bearer " + token } } });
  const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) return null;
  return { db, user: data.user };
}

async function aiInterpret(userId: string, text: string, history: { role: "user" | "assistant"; content: string }[]): Promise<CommandAction | null> {
  const url = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey || !process.env.CREDENTIALS_ENCRYPTION_KEY) return null;
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data } = await admin.from("ai_provider_configs").select("provider,model,enabled,is_default,encrypted_credentials").eq("user_id", userId).eq("enabled", true).order("is_default", { ascending: false }).order("updated_at", { ascending: false }).limit(1).maybeSingle();
  if (!data?.encrypted_credentials) return null;
  const provider = data.provider as keyof typeof providerUrls;
  if (!providerUrls[provider]) return null;
  const key = decryptSecret(data.encrypted_credentials as EncryptedSecret);
  const system = [
    "You are a finance command parser. Return only one JSON object, never SQL, code, explanations, or multiple actions.",
    "Allowed JSON actions: create_transaction {type,transactionKind,amount,description,accountName?,categoryName?,date?}; create_account {type,name?,accountType?}; list_accounts {type}; list_transactions {type,period?,category?,limit?}; summary {type,period}; update_last_amount {type,amount}; delete_last {type}; undo_last {type}; transfer {type,amount,fromAccount?,toAccount?}; set_budget {type,name,amount}; budget_remaining {type}; create_category {type,name}; rename_account {type,from,to}; rename_category {type,from,to}; delete_transaction {type,query}; delete_account {type,name,confirmed}; update_last_account {type,accountName}; update_last_date {type,date}; set_opening_balance {type,amount,accountName?}; delete_all_month {type,confirmed}; help {type}.",
    "Amounts must be positive numbers. Dates are today or yesterday. Never invent account names; omit unknown accountName. If the request is unclear, return {type:'help'}. Transfers must not be classified as expenses or income.",
    "User command: " + text
  ].join("\n");
  const response = await fetch(providerUrls[provider] + "/chat/completions", {
    method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer " + key },
    body: JSON.stringify({ model: data.model, temperature: 0, response_format: { type: "json_object" }, messages: [{ role: "system", content: system }] }),
    signal: AbortSignal.timeout(18000), cache: "no-store"
  });
  if (!response.ok) throw new Error("The connected AI provider could not interpret this command.");
  const body = await response.json();
  const content = body.choices?.[0]?.message?.content;
  if (typeof content !== "string") return null;
  let json: unknown;
  try { json = JSON.parse(content); } catch { return null; }
  const validated = actionSchema.safeParse(json);
  return validated.success ? validated.data as CommandAction : null;
}

function dateRange(period: "today" | "month" | "last_month" | "week" | "all") {
  const now = new Date();
  if (period === "today") return { start: new Date(now.getFullYear(), now.getMonth(), now.getDate()), end: now };
  if (period === "last_month") return { start: new Date(now.getFullYear(), now.getMonth() - 1, 1), end: new Date(now.getFullYear(), now.getMonth(), 1) };
  if (period === "week") return { start: new Date(now.getTime() - 7 * 86400000), end: now };
  if (period === "month") return { start: new Date(now.getFullYear(), now.getMonth(), 1), end: now };
  return { start: new Date(0), end: now };
}
const fmt = (value: number, currency = "SAR") => new Intl.NumberFormat("en", { style: "currency", currency, maximumFractionDigits: 2 }).format(value);

async function execute(db: any, userId: string, action: CommandAction): Promise<{ reply: string; refresh?: boolean }> {
  const accountQuery = () => db.from("accounts").select("*").eq("user_id", userId).eq("archived", false);
  const accountsResult = await accountQuery().order("created_at");
  if (accountsResult.error) throw accountsResult.error;
  const accounts: any[] = accountsResult.data || [];
  const getAccount = (name?: string) => {
    if (!name) return accounts.find(a => a.account_type === "cash") || accounts[0];
    const exact = accounts.find(a => a.name.toLowerCase() === name.toLowerCase());
    if (exact) return exact;
    if (/cash/i.test(name)) return accounts.find(a => a.account_type === "cash");
    if (/bank/i.test(name)) return accounts.find(a => a.account_type === "bank");
    if (/saving/i.test(name)) return accounts.find(a => a.account_type === "savings");
    if (/card|credit/i.test(name)) return accounts.find(a => a.account_type === "credit_card");
    return accounts.find(a => a.name.toLowerCase().includes(name.toLowerCase()));
  };

  if (action.type === "create_transaction") {
    const account = getAccount(action.accountName);
    if (!account) return { reply: "Create an account first. Try “New account Cash”." };
    let categoryName = action.categoryName || inferCategory(action.description, action.transactionKind === "income");
    const { data: category } = await db.from("categories").select("id,name").eq("user_id", userId).ilike("name", categoryName).limit(1).maybeSingle();
    const occurred = action.date === "yesterday" ? new Date(Date.now() - 86400000).toISOString() : new Date().toISOString();
    const { error } = await db.from("transactions").insert({
      user_id: userId, account_id: account.id, category_id: category?.id || null,
      description: action.description, amount: action.amount, transaction_kind: action.transactionKind, occurred_at: occurred
    });
    if (error) throw error;
    return { reply: "✓ Added " + fmt(action.amount, account.currency) + " · " + action.description + " · " + account.name + " · " + categoryName + ".", refresh: true };
  }
  if (action.type === "create_account") {
    const name = action.name?.trim();
    if (!name) return { reply: "What should I call the new account?" };
    if (accounts.some(a => a.name.toLowerCase() === name.toLowerCase())) return { reply: "You already have an account called " + name + "." };
    const { error } = await db.from("accounts").insert({ user_id: userId, name, account_type: action.accountType || "bank", currency: "SAR", opening_balance: 0, current_balance: 0 });
    if (error) throw error;
    return { reply: action.name + " account created.", refresh: true };
  }
  if (action.type === "list_accounts") return { reply: accounts.map(a => a.name + " · " + fmt(Number(a.current_balance), a.currency)).join("\n") || "No accounts yet. Try “New account Cash”." };
  if (action.type === "update_last_amount") {
    const { data: last, error } = await db.from("transactions").select("id,amount,transaction_kind,description").eq("user_id", userId).in("transaction_kind", ["expense","income"]).order("occurred_at", { ascending: false }).limit(1).maybeSingle();
    if (error) throw error;
    if (!last) return { reply: "There isn't a recent transaction to update." };
    const { error: updateError } = await db.from("transactions").update({ amount: action.amount }).eq("id", last.id).eq("user_id", userId);
    if (updateError) throw updateError;
    return { reply: "✓ Updated " + last.description + " to " + fmt(action.amount) + ".", refresh: true };
  }
  if (action.type === "undo_last") {
    const { data: last, error } = await db.from("transactions").select("id,description,linked_transfer_id").eq("user_id", userId).order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (error) throw error;
    if (!last) return { reply: "There isn't a recent transaction to undo." };
    let deleteQuery = db.from("transactions").delete().eq("user_id", userId);
    deleteQuery = last.linked_transfer_id ? deleteQuery.eq("linked_transfer_id", last.linked_transfer_id) : deleteQuery.eq("id", last.id);
    const { error: deleteError } = await deleteQuery;
    if (deleteError) throw deleteError;
    return { reply: "✓ Undid the last transaction" + (last.linked_transfer_id ? " transfer" : "") + ".", refresh: true };
  }
  if (action.type === "delete_last") {
    const { data: last, error } = await db.from("transactions").select("id,description").eq("user_id", userId).in("transaction_kind", ["expense","income"]).order("occurred_at", { ascending: false }).limit(1).maybeSingle();
    if (error) throw error;
    if (!last) return { reply: "There isn't a recent transaction to delete." };
    const { error: deleteError } = await db.from("transactions").delete().eq("id", last.id).eq("user_id", userId);
    if (deleteError) throw deleteError;
    return { reply: "✓ Deleted " + last.description + ".", refresh: true };
  }
  if (action.type === "transfer") {
    const from = getAccount(action.fromAccount);
    const to = action.toAccount ? getAccount(action.toAccount) : undefined;
    if (!from || !to) return { reply: "Which accounts should I move the money between? Say “Transfer 100 from Cash to Main Bank”." };
    if (from.id === to.id) return { reply: "Choose two different accounts for a transfer." };
    const { error } = await db.rpc("create_transfer", { p_from_account: from.id, p_to_account: to.id, p_amount: action.amount, p_occurred_at: new Date().toISOString() });
    if (error) throw error;
    return { reply: "✓ Moved " + fmt(action.amount, from.currency) + " from " + from.name + " to " + to.name + ".", refresh: true };
  }
  if (action.type === "set_budget") {
    const { data: category } = await db.from("categories").select("id").eq("user_id", userId).ilike("name", "%" + action.name + "%").limit(1).maybeSingle();
    const { error } = await db.from("budgets").upsert({
      user_id: userId, category_id: category?.id || null, name: action.name,
      amount: action.amount, period: "monthly"
    }, { onConflict: "user_id,name,period" });
    if (error) throw error;
    return { reply: "✓ " + action.name + " budget set to " + fmt(action.amount) + " per month.", refresh: true };
  }
  if (action.type === "budget_remaining") {
    const { data: budgets, error } = await db.from("budgets").select("amount,category_id").eq("user_id", userId).eq("period", "monthly");
    if (error) throw error;
    const start = dateRange("month").start.toISOString();
    const budgetRows: any[] = budgets || [];
    const { data: categorizedExpenses, error: categoryError } = await db.from("transactions").select("amount,category_id").eq("user_id", userId).eq("transaction_kind", "expense").gte("occurred_at", start);
    if (categoryError) throw categoryError;
    const expenseRows: any[] = categorizedExpenses || [];
    const spent = budgetRows.reduce((total: number, budget: any) => total + expenseRows.filter((row: any) => budget.category_id ? row.category_id === budget.category_id : true).reduce((sum: number, row: any) => sum + Number(row.amount), 0), 0);
    const remaining = budgetRows.reduce((s: number, b: any) => s + Number(b.amount), 0) - spent;
    return { reply: budgets?.length ? "You have " + fmt(remaining) + " left across your monthly budgets." : "No monthly budget yet. Try “Set food budget 1000”." };
  }
  if (action.type === "create_category") {
    const { error } = await db.from("categories").insert({ user_id: userId, name: action.name, icon: "dots", color: "#a2adbd", kind: "expense" });
    if (error?.code === "23505") return { reply: "That category already exists." };
    if (error) throw error;
    return { reply: "✓ Created the " + action.name + " category.", refresh: true };
  }
  if (action.type === "rename_account") {
    const account = getAccount(action.from);
    if (!account) return { reply: "I couldn't find the " + action.from + " account." };
    const { error } = await db.from("accounts").update({ name: action.to }).eq("id", account.id).eq("user_id", userId);
    if (error) throw error;
    return { reply: "✓ Renamed " + action.from + " to " + action.to + ".", refresh: true };
  }
  if (action.type === "delete_transaction") {
    const { data: target, error } = await db.from("transactions").select("id,description").eq("user_id", userId).in("transaction_kind", ["expense","income"]).ilike("description", "%" + action.query + "%").order("occurred_at", { ascending: false }).limit(1).maybeSingle();
    if (error) throw error;
    if (!target) return { reply: "I couldn't find a transaction matching " + action.query + "." };
    const { error: deleteError } = await db.from("transactions").delete().eq("id", target.id).eq("user_id", userId);
    if (deleteError) throw deleteError;
    return { reply: "✓ Deleted " + target.description + ".", refresh: true };
  }
  if (action.type === "delete_account") {
    if (!action.confirmed) return { reply: "Delete " + action.name + "? The account must have a zero balance. Type “confirm delete account " + action.name + "” to continue." };
    const account = getAccount(action.name);
    if (!account) return { reply: "I couldn't find the " + action.name + " account." };
    if (Math.abs(Number(account.current_balance)) > 0.009) return { reply: account.name + " still has a balance of " + fmt(Number(account.current_balance), account.currency) + ". Transfer or reconcile it before deleting the account." };
    const { error } = await db.from("accounts").update({ archived: true }).eq("id", account.id).eq("user_id", userId);
    if (error) throw error;
    return { reply: "✓ Archived the empty " + account.name + " account. Its transaction history is retained.", refresh: true };
  }
  if (action.type === "rename_category") {
    const { data: category, error: findError } = await db.from("categories").select("id,name").eq("user_id", userId).ilike("name", "%" + action.from + "%").limit(1).maybeSingle();
    if (findError) throw findError;
    if (!category) return { reply: "I couldn't find the " + action.from + " category." };
    const { error } = await db.from("categories").update({ name: action.to }).eq("id", category.id).eq("user_id", userId);
    if (error?.code === "23505") return { reply: "A category with that name already exists." };
    if (error) throw error;
    return { reply: "✓ Renamed category " + category.name + " to " + action.to + ".", refresh: true };
  }
  if (action.type === "update_last_account") {
    const target = getAccount(action.accountName);
    if (!target) return { reply: "I couldn't find the " + action.accountName + " account." };
    const { data: last, error } = await db.from("transactions").select("id,description,amount,transaction_kind,account_id").eq("user_id", userId).in("transaction_kind", ["expense","income"]).order("occurred_at", { ascending: false }).limit(1).maybeSingle();
    if (error) throw error;
    if (!last) return { reply: "There isn't a recent transaction to move." };
    if (last.account_id === target.id) return { reply: "That transaction is already in " + target.name + "." };
    const { error: updateError } = await db.from("transactions").update({ account_id: target.id }).eq("id", last.id).eq("user_id", userId);
    if (updateError) throw updateError;
    return { reply: "✓ Moved " + last.description + " to " + target.name + ".", refresh: true };
  }
  if (action.type === "update_last_date") {
    const { data: last, error } = await db.from("transactions").select("id,description").eq("user_id", userId).in("transaction_kind", ["expense","income"]).order("occurred_at", { ascending: false }).limit(1).maybeSingle();
    if (error) throw error;
    if (!last) return { reply: "There isn't a recent transaction to move." };
    const occurred_at = action.date === "yesterday" ? new Date(Date.now() - 86400000).toISOString() : new Date().toISOString();
    const { error: updateError } = await db.from("transactions").update({ occurred_at }).eq("id", last.id).eq("user_id", userId);
    if (updateError) throw updateError;
    return { reply: "✓ Moved " + last.description + " to " + action.date + ".", refresh: true };
  }
  if (action.type === "set_opening_balance") {
    if (!action.accountName && accounts.length > 1) return { reply: "Which account should receive that opening balance?" };
    const account = getAccount(action.accountName);
    if (!account) return { reply: "Which account should receive that opening balance?" };
    const { data: tx, error: txError } = await db.from("transactions").select("amount,transaction_kind").eq("user_id", userId).eq("account_id", account.id);
    if (txError) throw txError;
    const txRows: any[] = tx || [];
    const activity = txRows.reduce((sum: number, row: any) => sum + (row.transaction_kind === "income" || row.transaction_kind === "transfer_in" ? Number(row.amount) : -Number(row.amount)), 0);
    const { error } = await db.from("accounts").update({ opening_balance: action.amount, current_balance: action.amount + activity }).eq("id", account.id).eq("user_id", userId);
    if (error) throw error;
    return { reply: "✓ Opening balance for " + account.name + " set to " + fmt(action.amount, account.currency) + ".", refresh: true };
  }
  if (action.type === "delete_all_month") {
    if (!action.confirmed) return { reply: "This will permanently delete this month's transactions. Type “confirm delete all transactions this month” to continue." };
    const { error } = await db.from("transactions").delete().eq("user_id", userId).gte("occurred_at", dateRange("month").start.toISOString());
    if (error) throw error;
    return { reply: "✓ Deleted this month's transactions.", refresh: true };
  }
  if (action.type === "list_transactions") {
    const period = action.period || "all";
    const range = dateRange(period);
    let query = db.from("transactions").select("description,amount,transaction_kind,occurred_at,accounts(name,currency),categories(name)").eq("user_id", userId).order("occurred_at", { ascending: false }).limit(action.limit || 20);
    if (period !== "all") query = query.gte("occurred_at", range.start.toISOString()).lt("occurred_at", range.end.toISOString());
    if (action.category && action.category !== "uncategorized") {
      const { data: categories } = await db.from("categories").select("id").eq("user_id", userId).ilike("name", "%" + action.category + "%");
      const categoryRows: any[] = categories || [];
      const ids = categoryRows.map((c: any) => c.id);
      if (!ids.length) return { reply: "No category named " + action.category + " was found." };
      query = query.in("category_id", ids);
    } else if (action.category === "uncategorized") query = query.is("category_id", null);
    const { data, error } = await query;
    if (error) throw error;
    const transactionRows: any[] = data || [];
    return { reply: transactionRows.map((t: any) => t.description + " · " + fmt(Number(t.amount), (t.accounts as any)?.currency || "SAR") + " · " + new Date(t.occurred_at).toLocaleDateString()).join("\n") || "No matching transactions." };
  }
  if (action.type === "summary") {
    const range = dateRange(action.period);
    const { data, error } = await db.from("transactions").select("amount,transaction_kind,categories(name)").eq("user_id", userId).gte("occurred_at", range.start.toISOString()).lt("occurred_at", range.end.toISOString()).in("transaction_kind", ["expense","income"]);
    if (error) throw error;
    const summaryRows: any[] = data || [];
    const income = summaryRows.filter((t: any) => t.transaction_kind === "income").reduce((s: number, t: any) => s + Number(t.amount), 0);
    const expense = summaryRows.filter((t: any) => t.transaction_kind === "expense").reduce((s: number, t: any) => s + Number(t.amount), 0);
    const byCategory = new Map<string, number>();
    summaryRows.filter((t: any) => t.transaction_kind === "expense").forEach((t: any) => {
      const name = (t.categories as any)?.name || "Other";
      byCategory.set(name, (byCategory.get(name) || 0) + Number(t.amount));
    });
    const title = action.period === "today" ? "Today" : action.period === "last_month" ? "Last month" : "This month";
    return { reply: title + " · Income " + fmt(income) + " · Expenses " + fmt(expense) + " · Net " + fmt(income - expense) + "\n" + [...byCategory.entries()].sort((a,b) => b[1]-a[1]).map(([name, amount]) => name + ": " + fmt(amount)).join("\n") };
  }
  if (action.type === "help") return { reply: "Try “Coffee 15 cash”, “Salary 8000 bank”, “New account SABB”, “Transfer 100 from Cash to Main Bank”, “Set food budget 1000”, “Monthly report”, or “Edit last to 50”." };
  return { reply: "I couldn't complete that command. Try a shorter phrase or connect an AI provider in Settings." };
}

export async function POST(request: NextRequest) {
  const auth = await authenticate(request);
  if (!auth) return NextResponse.json({ error: "Your session expired. Sign in again." }, { status: 401 });
  const body = z.object({
    text: z.string().min(1).max(500),
    history: z.array(z.object({ role: z.enum(["user","assistant"]), content: z.string().max(500) })).max(10).optional()
  }).safeParse(await request.json().catch(() => null));
  if (!body.success) return NextResponse.json({ error: "Enter a command of 1–500 characters." }, { status: 400 });
  try {
    let action = parseCommand(body.data.text);
    if (!action) action = await aiInterpret(auth.user.id, body.data.text, body.data.history || []);
    if (!action) return NextResponse.json({ reply: "I couldn't understand that command. Try “Coffee 15 cash”, “Monthly report”, or connect an AI provider in Settings." });
    const validated = actionSchema.safeParse(action);
    if (!validated.success) return NextResponse.json({ error: "That action did not pass validation. No data was changed." }, { status: 400 });
    const result = await execute(auth.db, auth.user.id, validated.data as CommandAction);
    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "The command failed. No success was recorded." }, { status: 500 });
  }
}