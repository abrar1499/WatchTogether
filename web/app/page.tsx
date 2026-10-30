 "use client";

import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import {
  ArrowDownLeft, ArrowUpRight, Wallet, Sparkles, Send, Sun, Moon,
  Settings2, Download, Plus, Coffee, CarFront, ShoppingBag, HeartPulse, Receipt,
  CreditCard, Landmark, MoreHorizontal, X, Check, ShieldCheck, ChevronRight,
  TrendingUp, LoaderCircle, LogOut, PiggyBank, Trash2
} from "lucide-react";
import { getSupabase, isSupabaseConfigured } from "@/lib/supabase";
import { parseCommand, inferCategory } from "@/lib/commands";
import type { Account, Budget, Category, CommandAction, FinanceData, Transaction } from "@/lib/types";

type ChatMessage = { id: string; role: "user" | "assistant"; text: string; time: string };
type Provider = "groq" | "openai" | "xai";
type ProviderConfig = { provider: Provider; model: string; enabled: boolean; is_default?: boolean; has_key: boolean; models?: string[] };

const DEMO_KEY = "pocket-ai-demo-v1";
const CHAT_KEY = "pocket-ai-chat-v1";
const money = (amount: number, currency = "SAR") => new Intl.NumberFormat("en", { style: "currency", currency, maximumFractionDigits: 2 }).format(amount || 0);
const today = () => new Date().toISOString().slice(0, 10);
const uid = () => Math.random().toString(36).slice(2, 10);
const icons: Record<string, typeof Coffee> = {
  "Food & Drinks": Coffee, Transport: CarFront, Shopping: ShoppingBag, Health: HeartPulse,
  Bills: Receipt, Subscriptions: CreditCard, Income: TrendingUp, Other: MoreHorizontal
};

function freshDemo(): FinanceData {
  const cash: Account = { id: "demo-cash", name: "Cash", account_type: "cash", currency: "SAR", opening_balance: 1200, current_balance: 1200 };
  const bank: Account = { id: "demo-bank", name: "Main Bank", account_type: "bank", currency: "SAR", opening_balance: 8500, current_balance: 8500 };
  const categories: Category[] = [
    { id: "c-food", name: "Food & Drinks", icon: "coffee", color: "#b6f36b", kind: "expense" },
    { id: "c-transport", name: "Transport", icon: "car", color: "#8eb7ff", kind: "expense" },
    { id: "c-bills", name: "Bills", icon: "receipt", color: "#d1a5ff", kind: "expense" },
    { id: "c-shopping", name: "Shopping", icon: "bag", color: "#ffbf8a", kind: "expense" },
    { id: "c-health", name: "Health", icon: "heart", color: "#ff9aa7", kind: "expense" },
    { id: "c-income", name: "Income", icon: "trend", color: "#b6f36b", kind: "income" },
    { id: "c-other", name: "Other", icon: "dots", color: "#a2adbd", kind: "both" }
  ];
  const date = today();
  const tx: Transaction[] = [
    { id: "demo-1", description: "Coffee & breakfast", amount: 28, transaction_kind: "expense", account_id: cash.id, category_id: "c-food", occurred_at: date + "T08:20:00.000Z", accounts: { name: cash.name, currency: "SAR" }, categories: { name: "Food & Drinks", icon: "coffee", color: "#b6f36b" } },
    { id: "demo-2", description: "Monthly salary", amount: 8500, transaction_kind: "income", account_id: bank.id, category_id: "c-income", occurred_at: date + "T07:00:00.000Z", accounts: { name: bank.name, currency: "SAR" }, categories: { name: "Income", icon: "trend", color: "#b6f36b" } },
    { id: "demo-3", description: "Fuel", amount: 95, transaction_kind: "expense", account_id: bank.id, category_id: "c-transport", occurred_at: new Date(Date.now() - 86400000).toISOString(), accounts: { name: bank.name, currency: "SAR" }, categories: { name: "Transport", icon: "car", color: "#8eb7ff" } },
    { id: "demo-4", description: "Netflix", amount: 45, transaction_kind: "expense", account_id: bank.id, category_id: "c-bills", occurred_at: new Date(Date.now() - 2 * 86400000).toISOString(), accounts: { name: bank.name, currency: "SAR" }, categories: { name: "Bills", icon: "receipt", color: "#d1a5ff" } }
  ];
  cash.current_balance -= 28;
  bank.current_balance += 8500 - 95 - 45;
  return { accounts: [cash, bank], categories, transactions: tx, budgets: [{ id: "budget-food", category_id: "c-food", name: "Food & Drinks", amount: 1000, period: "monthly" }] };
}

function dateFor(date?: string) {
  return date === "yesterday" ? new Date(Date.now() - 86400000).toISOString() : new Date().toISOString();
}
function transactionCategory(tx: Transaction, categories: Category[]) {
  return categories.find(c => c.id === tx.category_id)?.name || tx.categories?.name || "Other";
}
function friendlyTime(value: string) {
  const d = new Date(value);
  if (d.toDateString() === new Date().toDateString()) return "Today";
  if (d.toDateString() === new Date(Date.now() - 86400000).toDateString()) return "Yesterday";
  return d.toLocaleDateString("en", { month: "short", day: "numeric" });
}

export default function Home() {
  const [data, setData] = useState<FinanceData>({ accounts: [], categories: [], transactions: [], budgets: [] });
  const [demo, setDemo] = useState(false);
  const [session, setSession] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [input, setInput] = useState("");
  const [messages, setMessages] = useState<ChatMessage[]>([
    { id: "welcome", role: "assistant", text: "Hi. I'm your money assistant. Tell me what happened — for example, “Coffee 15 cash” or “How much spent this month?”", time: "now" }
  ]);
  const [theme, setTheme] = useState<"dark" | "light">("dark");
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [authMode, setAuthMode] = useState<"signin" | "signup">("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [toast, setToast] = useState("");
  const [authError, setAuthError] = useState("");
  const supabase = getSupabase();

  const notify = useCallback((message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(""), 2800);
  }, []);

  const loadCloud = useCallback(async () => {
    if (!supabase) return;
    const [accounts, categories, transactions, budgets] = await Promise.all([
      supabase.from("accounts").select("*").eq("archived", false).order("created_at"),
      supabase.from("categories").select("*").order("name"),
      supabase.from("transactions").select("*, accounts(name,currency), categories(name,icon,color)").order("occurred_at", { ascending: false }).limit(30),
      supabase.from("budgets").select("*").eq("period", "monthly")
    ]);
    const errors = [accounts.error, categories.error, transactions.error, budgets.error].filter(Boolean);
    if (errors.length) throw errors[0];
    setData({ accounts: (accounts.data || []) as Account[], categories: (categories.data || []) as Category[], transactions: (transactions.data || []) as Transaction[], budgets: (budgets.data || []) as Budget[] });
  }, [supabase]);

  useEffect(() => {
    const savedTheme = localStorage.getItem("pocket-ai-theme");
    if (savedTheme === "light" || savedTheme === "dark") setTheme(savedTheme);
    const savedChat = localStorage.getItem(CHAT_KEY);
    if (savedChat) { try { setMessages(JSON.parse(savedChat)); } catch { /* ignore invalid local cache */ } }
    if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => undefined);
    if (!supabase) { setLoading(false); return; }
    supabase.auth.getSession().then(async ({ data: auth }) => {
      setSession(auth.session);
      if (auth.session) {
        try { await loadCloud(); } catch (error) { notify(error instanceof Error ? error.message : "Could not load your data."); }
      }
      setLoading(false);
    });
    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      if (!nextSession) setData({ accounts: [], categories: [], transactions: [], budgets: [] });
      else window.setTimeout(() => loadCloud().catch(() => notify("Could not refresh your data.")), 0);
    });
    return () => listener.subscription.unsubscribe();
  }, [supabase, loadCloud, notify]);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    localStorage.setItem("pocket-ai-theme", theme);
  }, [theme]);
  useEffect(() => { localStorage.setItem(CHAT_KEY, JSON.stringify(messages.slice(-30))); }, [messages]);

  const isReady = demo || Boolean(session);
  const currency = data.accounts[0]?.currency || "SAR";
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const monthTransactions = data.transactions.filter(t => new Date(t.occurred_at).getTime() >= monthStart && !t.transaction_kind.startsWith("transfer"));
  const todayTransactions = data.transactions.filter(t => new Date(t.occurred_at).getTime() >= todayStart && !t.transaction_kind.startsWith("transfer"));
  const totalBalance = data.accounts.reduce((sum, account) => sum + Number(account.current_balance || 0), 0);
  const monthlyIncome = monthTransactions.filter(t => t.transaction_kind === "income").reduce((sum, t) => sum + Number(t.amount), 0);
  const monthlyExpense = monthTransactions.filter(t => t.transaction_kind === "expense").reduce((sum, t) => sum + Number(t.amount), 0);
  const todayExpense = todayTransactions.filter(t => t.transaction_kind === "expense").reduce((sum, t) => sum + Number(t.amount), 0);
  const budgetTotal = data.budgets.reduce((sum, budget) => sum + Number(budget.amount), 0);
  const budgetSpent = data.budgets.reduce((sum, budget) => sum + monthTransactions.filter(t =>
    t.transaction_kind === "expense" && (budget.category_id ? t.category_id === budget.category_id : true)
  ).reduce((subtotal, t) => subtotal + Number(t.amount), 0), 0);
  const budgetRemaining = budgetTotal - budgetSpent;
  const categoryTotals = useMemo(() => {
    const map = new Map<string, number>();
    monthTransactions.filter(t => t.transaction_kind === "expense").forEach(t => {
      const name = transactionCategory(t, data.categories);
      map.set(name, (map.get(name) || 0) + Number(t.amount));
    });
    return [...map.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5);
  }, [monthTransactions, data.categories]);

  const saveDemo = (next: FinanceData) => {
    setData(next);
    localStorage.setItem(DEMO_KEY, JSON.stringify(next));
  };

  const runDemo = (action: CommandAction): string => {
    const next: FinanceData = JSON.parse(JSON.stringify(data));
    const sorted = [...next.transactions].sort((a, b) => new Date(b.occurred_at).getTime() - new Date(a.occurred_at).getTime());
    const findAccount = (name?: string) => {
      if (!name) return next.accounts.find(a => a.account_type === "cash") || next.accounts[0];
      const exact = next.accounts.find(a => a.name.toLowerCase() === name.toLowerCase());
      if (exact) return exact;
      if (/cash/i.test(name)) return next.accounts.find(a => a.account_type === "cash");
      if (/bank/i.test(name)) return next.accounts.find(a => a.account_type === "bank");
      if (/card|credit/i.test(name)) return next.accounts.find(a => a.account_type === "credit_card");
      return next.accounts.find(a => a.name.toLowerCase().includes(name.toLowerCase()));
    };
    if (action.type === "create_transaction") {
      let account = findAccount(action.accountName);
      if (!account) return "I couldn't find that account. Create it first with “New account " + action.accountName + "”.";
      let category = next.categories.find(c => c.name.toLowerCase() === (action.categoryName || "Other").toLowerCase());
      if (!category) {
        category = { id: uid(), name: action.categoryName || inferCategory(action.description), icon: "dots", color: "#a2adbd", kind: action.transactionKind };
        next.categories.push(category);
      }
      const tx: Transaction = {
        id: uid(), description: action.description, amount: action.amount, transaction_kind: action.transactionKind,
        account_id: account.id, category_id: category.id, occurred_at: dateFor(action.date), created_at: new Date().toISOString(),
        accounts: { name: account.name, currency: account.currency },
        categories: { name: category.name, icon: category.icon, color: category.color }
      };
      next.transactions.unshift(tx);
      account.current_balance += action.transactionKind === "income" ? action.amount : -action.amount;
      saveDemo(next);
      return "✓ Added " + money(action.amount, account.currency) + " · " + action.description + " · " + account.name + " · " + category.name + ".";
    }
    if (action.type === "create_account") {
      const name = action.name?.trim();
      if (!name) return "What should I call the new account?";
      if (next.accounts.some(a => a.name.toLowerCase() === name.toLowerCase())) return "You already have an account called " + name + ".";
      const type = /cash/i.test(name) ? "cash" : /saving/i.test(name) ? "savings" : /card|credit/i.test(name) ? "credit_card" : "bank";
      next.accounts.push({ id: uid(), name, account_type: type, currency: "SAR", opening_balance: 0, current_balance: 0 });
      saveDemo(next);
      return action.name + " account created.";
    }
    if (action.type === "list_accounts") return next.accounts.map(a => a.name + ": " + money(a.current_balance, a.currency)).join("\n") || "No accounts yet. Try “New account Cash”.";
    if (action.type === "update_last_amount") {
      const last = sorted.find(t => t.transaction_kind === "expense" || t.transaction_kind === "income");
      if (!last) return "There isn't a recent transaction to update.";
      const old = next.transactions.find(t => t.id === last.id)!;
      const account = next.accounts.find(a => a.id === old.account_id);
      if (account) account.current_balance += old.transaction_kind === "income" ? -old.amount + action.amount : old.amount - action.amount;
      old.amount = action.amount;
      saveDemo(next);
      return "Updated " + old.description + " to " + money(action.amount, account?.currency || "SAR") + ".";
    }
    if (action.type === "undo_last") {
      const last = [...next.transactions].sort((a, b) => new Date(b.created_at || b.occurred_at).getTime() - new Date(a.created_at || a.occurred_at).getTime())[0];
      if (!last) return "There isn't a recent transaction to undo.";
      const affected = last.linked_transfer_id ? next.transactions.filter(t => t.linked_transfer_id === last.linked_transfer_id) : [last];
      affected.forEach(tx => {
        const account = next.accounts.find(a => a.id === tx.account_id);
        if (account) account.current_balance -= tx.transaction_kind === "income" || tx.transaction_kind === "transfer_in" ? tx.amount : -tx.amount;
      });
      const ids = new Set(affected.map(tx => tx.id));
      next.transactions = next.transactions.filter(tx => !ids.has(tx.id));
      saveDemo(next);
      return "Undid the last transaction" + (affected.length > 1 ? " transfer" : "") + ".";
    }
    if (action.type === "delete_last") {
      const last = sorted.find(t => t.transaction_kind === "expense" || t.transaction_kind === "income");
      if (!last) return "There isn't a recent transaction to delete.";
      const account = next.accounts.find(a => a.id === last.account_id);
      if (account) account.current_balance += last.transaction_kind === "income" ? -last.amount : last.amount;
      next.transactions = next.transactions.filter(t => t.id !== last.id);
      saveDemo(next);
      return "Deleted " + last.description + ".";
    }
    if (action.type === "transfer") {
      const from = findAccount(action.fromAccount);
      const to = findAccount(action.toAccount);
      if (!from || !to) return "I couldn't find both accounts. Try “Transfer 100 from Cash to Main Bank”.";
      if (from.id === to.id) return "Choose two different accounts for a transfer.";
      from.current_balance -= action.amount; to.current_balance += action.amount;
      const transferId = uid();
      next.transactions.unshift(
        { id: uid(), description: "Transfer to " + to.name, amount: action.amount, transaction_kind: "transfer_out", account_id: from.id, category_id: null, occurred_at: new Date().toISOString(), created_at: new Date().toISOString(), linked_transfer_id: transferId, accounts: { name: from.name, currency: from.currency } },
        { id: uid(), description: "Transfer from " + from.name, amount: action.amount, transaction_kind: "transfer_in", account_id: to.id, category_id: null, occurred_at: new Date().toISOString(), created_at: new Date().toISOString(), linked_transfer_id: transferId, accounts: { name: to.name, currency: to.currency } }
      );
      saveDemo(next);
      return "Moved " + money(action.amount, from.currency) + " from " + from.name + " to " + to.name + ".";
    }
    if (action.type === "set_budget") {
      const existing = next.budgets.find(b => b.name.toLowerCase() === action.name.toLowerCase());
      if (existing) existing.amount = action.amount;
      else next.budgets.push({ id: uid(), category_id: next.categories.find(c => c.name.toLowerCase().includes(action.name.toLowerCase()))?.id || null, name: action.name, amount: action.amount, period: "monthly" });
      saveDemo(next);
      return action.name + " budget set to " + money(action.amount) + " per month.";
    }
    if (action.type === "budget_remaining") return budgetTotal ? "You have " + money(budgetRemaining) + " left across your monthly budgets." : "No monthly budget yet. Try “Set food budget 1000”.";
    if (action.type === "create_category") {
      if (next.categories.some(c => c.name.toLowerCase() === action.name.toLowerCase())) return "That category already exists.";
      next.categories.push({ id: uid(), name: action.name, icon: "dots", color: "#a2adbd", kind: "expense" });
      saveDemo(next);
      return "Created the " + action.name + " category.";
    }
    if (action.type === "rename_account") {
      const account = findAccount(action.from);
      if (!account) return "I couldn't find the " + action.from + " account.";
      const oldName = account.name;
      account.name = action.to;
      next.transactions.forEach(t => { if (t.account_id === account.id && t.accounts) t.accounts.name = action.to; });
      saveDemo(next);
      return "Renamed " + oldName + " to " + action.to + ".";
    }
    if (action.type === "delete_transaction") {
      const target = sorted.find(t => (t.transaction_kind === "expense" || t.transaction_kind === "income") && t.description.toLowerCase().includes(action.query.toLowerCase()));
      if (!target) return "I couldn't find a transaction matching " + action.query + ".";
      const account = next.accounts.find(a => a.id === target.account_id);
      if (account) account.current_balance += target.transaction_kind === "income" || target.transaction_kind === "transfer_in" ? -target.amount : target.amount;
      next.transactions = next.transactions.filter(t => t.id !== target.id);
      saveDemo(next);
      return "Deleted " + target.description + ".";
    }
    if (action.type === "delete_account") {
      if (!action.confirmed) return "Delete " + action.name + "? The account must have a zero balance. Type “confirm delete account " + action.name + "” to continue.";
      const account = findAccount(action.name);
      if (!account) return "I couldn't find the " + action.name + " account.";
      if (Math.abs(account.current_balance) > 0.009) return account.name + " still has a balance of " + money(account.current_balance, account.currency) + ". Transfer or reconcile it before deleting the account.";
      next.accounts = next.accounts.filter(a => a.id !== account.id);
      saveDemo(next);
      return "Deleted the empty " + account.name + " account. Its transaction history remains in this demo.";
    }
    if (action.type === "rename_category") {
      const category = next.categories.find(c => c.name.toLowerCase() === action.from.toLowerCase() || c.name.toLowerCase().includes(action.from.toLowerCase()));
      if (!category) return "I couldn't find the " + action.from + " category.";
      category.name = action.to;
      next.transactions.forEach(t => { if (t.category_id === category.id && t.categories) t.categories.name = action.to; });
      saveDemo(next);
      return "Renamed category " + action.from + " to " + action.to + ".";
    }
    if (action.type === "update_last_account") {
      const last = sorted.find(t => t.transaction_kind === "expense" || t.transaction_kind === "income");
      const target = findAccount(action.accountName);
      if (!last) return "There isn't a recent transaction to move.";
      if (!target) return "I couldn't find the " + action.accountName + " account.";
      const old = next.accounts.find(a => a.id === last.account_id);
      if (old?.id === target.id) return "That transaction is already in " + target.name + ".";
      if (old) old.current_balance += last.transaction_kind === "income" ? -last.amount : last.amount;
      target.current_balance += last.transaction_kind === "income" ? last.amount : -last.amount;
      last.account_id = target.id;
      last.accounts = { name: target.name, currency: target.currency };
      saveDemo(next);
      return "Moved " + last.description + " to " + target.name + ".";
    }
    if (action.type === "update_last_date") {
      const last = sorted.find(t => t.transaction_kind === "expense" || t.transaction_kind === "income");
      if (!last) return "There isn't a recent transaction to move.";
      last.occurred_at = dateFor(action.date);
      saveDemo(next);
      return "Moved " + last.description + " to " + action.date + ".";
    }
    if (action.type === "set_opening_balance") {
      if (!action.accountName && next.accounts.length > 1) return "Which account should receive that opening balance?";
      const account = findAccount(action.accountName);
      if (!account) return "Which account should receive that opening balance?";
      const activity = next.transactions.filter(t => t.account_id === account.id).reduce((sum, t) => sum + (t.transaction_kind === "income" || t.transaction_kind === "transfer_in" ? t.amount : -t.amount), 0);
      account.opening_balance = action.amount;
      account.current_balance = action.amount + activity;
      saveDemo(next);
      return "Opening balance for " + account.name + " set to " + money(action.amount, account.currency) + ".";
    }
    if (action.type === "delete_all_month") {
      if (!action.confirmed) return "This will permanently delete this month's transactions. Type “confirm delete all transactions this month” to continue.";
      next.transactions = next.transactions.filter(t => new Date(t.occurred_at).getTime() < monthStart);
      next.accounts.forEach(a => {
        const activity = next.transactions.filter(t => t.account_id === a.id).reduce((sum, t) => sum + (t.transaction_kind === "income" || t.transaction_kind === "transfer_in" ? t.amount : -t.amount), 0);
        a.current_balance = a.opening_balance + activity;
      });
      saveDemo(next);
      return "Deleted this month's transactions.";
    }
    if (action.type === "list_transactions") {
      let filtered = sorted;
      if (action.period === "today") filtered = filtered.filter(t => new Date(t.occurred_at).getTime() >= todayStart);
      if (action.period === "month") filtered = filtered.filter(t => new Date(t.occurred_at).getTime() >= monthStart);
      if (action.category === "uncategorized") filtered = filtered.filter(t => !t.category_id);
      else if (action.category) filtered = filtered.filter(t => transactionCategory(t, next.categories).toLowerCase().includes(action.category!.toLowerCase()));
      return filtered.slice(0, action.limit || 20).map(t => t.description + " · " + money(t.amount) + " · " + friendlyTime(t.occurred_at)).join("\n") || "No matching transactions.";
    }
    if (action.type === "summary") {
      const start = action.period === "today" ? todayStart : action.period === "last_month" ? new Date(now.getFullYear(), now.getMonth() - 1, 1).getTime() : monthStart;
      const end = action.period === "last_month" ? monthStart : Date.now() + 1;
      const items = next.transactions.filter(t => {
        const time = new Date(t.occurred_at).getTime();
        return time >= start && time < end && !t.transaction_kind.startsWith("transfer");
      });
      const spent = items.filter(t => t.transaction_kind === "expense").reduce((sum, t) => sum + t.amount, 0);
      const earned = items.filter(t => t.transaction_kind === "income").reduce((sum, t) => sum + t.amount, 0);
      const groups = new Map<string, number>();
      items.filter(t => t.transaction_kind === "expense").forEach(t => {
        const name = transactionCategory(t, next.categories);
        groups.set(name, (groups.get(name) || 0) + t.amount);
      });
      return "Income: " + money(earned) + "\nExpenses: " + money(spent) + "\nNet: " + money(earned - spent) + "\n" + [...groups.entries()].map(([name, amount]) => name + ": " + money(amount)).join("\n");
    }
    if (action.type === "help") return "Try: “Coffee 15 cash”, “Salary 8000 bank”, “New account SABB”, “Transfer 100 from Cash to Main Bank”, “Set food budget 1000”, “Monthly report”, or “Edit last to 50”.";
    return "I couldn't complete that command yet. Try a shorter command or open Settings to connect an AI provider.";
  };

  const addMessage = (role: "user" | "assistant", text: string) => {
    setMessages(prev => [...prev, { id: uid(), role, text, time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) }].slice(-30));
  };

  const sendCommand = async (raw = input) => {
    const text = raw.trim();
    if (!text || busy) return;
    setInput("");
    addMessage("user", text);
    setBusy(true);
    try {
      if (demo) {
        const action = parseCommand(text);
        const reply = action ? runDemo(action) : "I didn't quite understand that. Try “Coffee 15 cash”, “New account SABB”, or “Monthly report”.";
        addMessage("assistant", reply);
      } else if (session && supabase) {
        const { data: auth } = await supabase.auth.getSession();
        const response = await fetch("/api/command", {
          method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer " + (auth.session?.access_token || "") },
          body: JSON.stringify({ text, history: messages.slice(-10).map(message => ({ role: message.role, content: message.text })) })
        });
        const result = await response.json();
        if (!response.ok) throw new Error(result.error || "The command could not be completed.");
        if (result.refresh) await loadCloud();
        addMessage("assistant", result.reply || "Done.");
      } else addMessage("assistant", "Sign in or start demo mode to save transactions.");
    } catch (error) {
      addMessage("assistant", error instanceof Error ? error.message : "Something went wrong. Your data was not changed.");
    } finally { setBusy(false); }
  };

  const signIn = async (event: FormEvent) => {
    event.preventDefault(); setAuthError("");
    if (!supabase) return;
    setBusy(true);
    const result = authMode === "signup" ? await supabase.auth.signUp({ email, password }) : await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (result.error) setAuthError(result.error.message);
    else if (authMode === "signup" && !result.data.session) setAuthError("Check your email to confirm your account, then sign in.");
  };

  const startDemo = () => {
    let saved: FinanceData;
    try { saved = JSON.parse(localStorage.getItem(DEMO_KEY) || "null") || freshDemo(); } catch { saved = freshDemo(); }
    setData(saved); setDemo(true); setSession(null);
    notify("Demo mode · data stays on this device");
  };
  const signOut = async () => {
    if (demo) { setDemo(false); setData({ accounts: [], categories: [], transactions: [], budgets: [] }); }
    else if (supabase) await supabase.auth.signOut();
  };
  const exportCsv = () => {
    const header = ["Date", "Description", "Type", "Amount", "Currency", "Account", "Category"];
    const rows = data.transactions.map(t => [t.occurred_at, t.description, t.transaction_kind, t.amount, t.accounts?.currency || currency, t.accounts?.name || data.accounts.find(a => a.id === t.account_id)?.name || "", transactionCategory(t, data.categories)]);
    const csv = [header, ...rows].map(row => row.map(value => '"' + String(value ?? "").replace(/"/g, '""') + '"').join(",")).join("\n");
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a"); link.href = url; link.download = "pocket-ai-transactions.csv"; link.click(); URL.revokeObjectURL(url);
    notify("CSV export ready.");
  };

  if (loading) return <div className="auth-wrap"><div className="brand"><span className="brand-mark"><Wallet size={20}/></span> Pocket AI</div></div>;
  if (!isReady) return <main className="auth-wrap"><section className="panel auth-card">
    <div className="brand"><span className="brand-mark"><Wallet size={20}/></span><span>Pocket AI<small>PERSONAL FINANCE</small></span></div>
    <h1>Your money, in one conversation.</h1>
    <p>A calmer way to manage your finances. Add expenses, move money, set budgets and understand your spending with a simple sentence.</p>
    {isSupabaseConfigured ? <form onSubmit={signIn}>
      <label className="form-label">Email</label><input className="field" type="email" value={email} onChange={e => setEmail(e.target.value)} required placeholder="you@example.com"/>
      <label className="form-label">Password</label><input className="field" type="password" minLength={8} value={password} onChange={e => setPassword(e.target.value)} required placeholder="At least 8 characters"/>
      {authError && <p className="helper" style={{color:"var(--red)"}}>{authError}</p>}
      <button className="primary-button" style={{width:"100%",marginTop:18}} disabled={busy}>{busy ? <LoaderCircle size={16} className="animate-spin"/> : null}{authMode === "signin" ? "Sign in" : "Create account"}</button>
      <button type="button" className="quiet-button" style={{width:"100%",marginTop:9}} onClick={() => setAuthMode(authMode === "signin" ? "signup" : "signin")}>{authMode === "signin" ? "Create a new account" : "I already have an account"}</button>
    </form> : <div className="helper" style={{padding:"12px 0 18px"}}>Cloud sync is not configured yet. Explore in private demo mode; demo records stay only on this device.</div>}
    <button className="primary-button" style={{width:"100%",marginTop:isSupabaseConfigured?14:0}} onClick={startDemo}><Sparkles size={16}/> Explore demo mode</button>
    <div className="footer-note" style={{marginTop:18}}><ShieldCheck size={12} style={{display:"inline",verticalAlign:"-2px",marginRight:5}}/>Your financial data belongs to you.</div>
  </section></main>;

  return <main className="app-shell">
    <header className="topbar">
      <div className="brand"><span className="brand-mark"><Wallet size={20}/></span><span>Pocket AI<small>{demo ? "PRIVATE DEMO" : "PERSONAL FINANCE"}</small></span></div>
      <div className="top-actions">
        <button className="quiet-button hide-mobile" onClick={exportCsv}><Download size={15}/> Export</button>
        <button className="icon-button" aria-label="Toggle theme" onClick={() => setTheme(theme === "dark" ? "light" : "dark")}>{theme === "dark" ? <Sun size={17}/> : <Moon size={17}/>}</button>
        <button className="icon-button" aria-label="Settings" onClick={() => setSettingsOpen(true)}><Settings2 size={17}/></button>
        <button className="icon-button" aria-label="Sign out" onClick={signOut}><LogOut size={16}/></button>
      </div>
    </header>
    <div className="page-heading">
      <div><div className="eyebrow">{now.toLocaleDateString("en", { weekday:"long", month:"long", day:"numeric" })}</div><h1>Good to see you.</h1><p>Your finances, clear at a glance. What would you like to do?</p></div>
      <button className="quiet-button" onClick={() => void sendCommand("Monthly report")}><TrendingUp size={15}/> Monthly report <ChevronRight size={14}/></button>
    </div>
    <div className="dashboard-grid">
      <section className="main-column">
        <div className="panel balance-panel">
          <div className="balance-label"><Wallet size={14}/> Total balance across accounts</div>
          <div className="balance-value">{money(totalBalance, currency)}</div>
          <div className="balance-footer"><div className="balance-stat"><span className="stat-dot"/> Income <strong>{money(monthlyIncome, currency)}</strong></div><div className="balance-stat"><span className="stat-dot red"/> Expenses <strong>{money(monthlyExpense, currency)}</strong></div></div>
        </div>
        <div className="metric-grid">
          <div className="panel metric-card"><div className="metric-top">Today's spending <span className="metric-icon"><ArrowUpRight size={15}/></span></div><div className="metric-value">{money(todayExpense, currency)}</div><div className="metric-caption">Across all accounts</div></div>
          <div className="panel metric-card"><div className="metric-top">Monthly income <span className="metric-icon"><ArrowDownLeft size={15}/></span></div><div className="metric-value">{money(monthlyIncome, currency)}</div><div className="metric-caption">Money received this month</div></div>
          <div className="panel metric-card"><div className="metric-top">Budget remaining <span className="metric-icon"><PiggyBank size={15}/></span></div><div className="metric-value">{budgetTotal ? money(budgetRemaining, currency) : "—"}</div><div className="metric-caption">{budgetTotal ? "Of " + money(budgetTotal, currency) + " planned" : "Set a budget in chat"}</div></div>
        </div>
        <section className="panel chat-panel">
          <div className="section-title"><div><h2>Money assistant</h2><span>Natural language · instant actions</span></div><span className="pill on"><span style={{display:"inline-block",width:6,height:6,borderRadius:10,background:"var(--green)",marginRight:5}}/>{demo ? "Demo" : "Ready"}</span></div>
          <div className="chat-messages">{messages.slice(-7).map(message => <div className={"chat-message " + message.role} key={message.id}><div className="chat-bubble">{message.text}</div><div className="chat-time">{message.time}</div></div>)}{busy && <div className="chat-message assistant"><div className="chat-bubble"><LoaderCircle size={14} className="animate-spin" style={{display:"inline",verticalAlign:"-2px",marginRight:7}}/>Working…</div></div>}</div>
          <form className="command-box" onSubmit={e => { e.preventDefault(); void sendCommand(); }}>
            <Sparkles size={17} color="var(--accent)"/><input value={input} onChange={e => setInput(e.target.value)} placeholder='Try “Coffee 15 cash” or “How much spent this month?”' aria-label="Ask your money assistant"/>
            <button className="send-button" type="submit" disabled={busy || !input.trim()} aria-label="Send command"><Send size={16}/></button>
          </form>
          <div className="prompt-row">{["Coffee 15 cash","New account SABB","Monthly report","Budget remaining"].map(prompt => <button className="prompt-chip" key={prompt} onClick={() => void sendCommand(prompt)}>{prompt}</button>)}</div>
        </section>
        <section className="panel list-panel">
          <div className="section-title"><h2>Recent transactions</h2><span>{data.transactions.length} shown</span></div>
          <div className="transaction-list">{data.transactions.slice(0, 7).map(tx => {
            const kind = tx.transaction_kind; const category = transactionCategory(tx, data.categories); const Icon = icons[category] || Receipt;
            const isIncome = kind === "income" || kind === "transfer_in";
            return <div className="transaction-row" key={tx.id}><div className="transaction-icon"><Icon size={17}/></div><div className="transaction-info"><strong>{tx.description}</strong><small>{category} · {tx.accounts?.name || data.accounts.find(a => a.id === tx.account_id)?.name || "Account"} · {friendlyTime(tx.occurred_at)}</small></div><div className={"transaction-amount " + (isIncome ? "income" : "expense")}>{isIncome ? "+" : kind === "transfer_out" ? "↗ " : "−"}{money(tx.amount, tx.accounts?.currency || currency)}</div></div>;
          })}{!data.transactions.length && <div className="empty-state">Your transactions will appear here. Try saying “Coffee 15 cash”.</div>}</div>
        </section>
      </section>
      <aside className="side-column">
        <section className="panel list-panel"><div className="section-title"><h2>Your accounts</h2><button className="prompt-chip" onClick={() => { setInput("New account "); document.querySelector<HTMLInputElement>('[aria-label="Ask your money assistant"]')?.focus(); }}><Plus size={12} style={{display:"inline",verticalAlign:"-2px"}}/> Add</button></div>
          <div className="account-list">{data.accounts.map(account => <div className="account-row" key={account.id}><div className="account-symbol">{account.account_type === "cash" ? <Wallet size={16}/> : account.account_type === "savings" ? <PiggyBank size={16}/> : <Landmark size={16}/>}</div><div className="account-meta"><strong>{account.name}</strong><small>{account.account_type.replace("_"," ")} · {account.currency}</small></div><div className="account-balance">{money(account.current_balance, account.currency)}</div></div>)}{!data.accounts.length && <div className="empty-state">Create your first account in chat.</div>}</div>
        </section>
        <section className="panel list-panel"><div className="section-title"><h2>Spending by category</h2><span>This month</span></div>
          <div className="category-list">{categoryTotals.map(([name, amount]) => <div className="category-line" key={name}><div className="category-line-top"><span>{name}</span><span>{money(amount, currency)}</span></div><div className="progress-track"><div className="progress-fill" style={{width:Math.min(100, amount / Math.max(monthlyExpense, 1) * 100) + "%"}}/></div></div>)}{!categoryTotals.length && <div className="empty-state">Category insights appear after your first expense.</div>}</div>
        </section>
        <section className="panel budget-card"><div className="section-title"><h2>Monthly budget</h2><PiggyBank size={17} color="var(--muted)"/></div>{budgetTotal ? <><div className="eyebrow">Remaining to spend</div><div className="budget-amount">{money(budgetRemaining, currency)}</div><div className="progress-track"><div className="progress-fill" style={{width:Math.max(0,Math.min(100,budgetSpent / budgetTotal * 100)) + "%"}}/></div><div className="budget-foot"><span>{money(budgetSpent, currency)} spent</span><span>{money(budgetTotal, currency)} total</span></div></> : <><div className="budget-amount">Set your limit</div><p className="helper">Say “Set food budget 1000” to start keeping your spending on track.</p></>}</section>
      </aside>
    </div>
    <div className="footer-note">Pocket AI · Your money stays yours {demo ? "· Demo data is stored on this device" : "· Secured by your Supabase account"}</div>
    {settingsOpen && <SettingsModal onClose={() => setSettingsOpen(false)} session={session} demo={demo} notify={notify}/>}
    {toast && <div className="toast">{toast}</div>}
  </main>;
}

function SettingsModal({ onClose, session, demo, notify }: { onClose: () => void; session: any; demo: boolean; notify: (message: string) => void }) {
  const [provider, setProvider] = useState<Provider>("groq");
  const [apiKey, setApiKey] = useState("");
  const [model, setModel] = useState("llama-3.3-70b-versatile");
  const [enabled, setEnabled] = useState(true);
  const [isDefault, setIsDefault] = useState(true);
  const [configs, setConfigs] = useState<ProviderConfig[]>([]);
  const [models, setModels] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const supabase = getSupabase();
  const defaults: Record<Provider, string> = { groq: "llama-3.3-70b-versatile", openai: "gpt-4.1-mini", xai: "grok-3-mini" };

  const refresh = async () => {
    if (!session || !supabase) return;
    const { data } = await supabase.auth.getSession();
    const response = await fetch("/api/ai-settings", { headers: { Authorization: "Bearer " + (data.session?.access_token || "") } });
    const body = await response.json();
    if (response.ok) {
      const items = body.configs || [];
      setConfigs(items);
      const current = items.find((item: ProviderConfig) => item.provider === provider);
      if (current) { setModel(current.model); setEnabled(current.enabled); setIsDefault(Boolean(current.is_default)); setModels(current.models || []); }
    }
  };
  useEffect(() => { void refresh(); }, []);

  const save = async () => {
    setSaving(true); setError("");
    try {
      const { data } = await supabase!.auth.getSession();
      const response = await fetch("/api/ai-settings", {
        method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer " + (data.session?.access_token || "") },
        body: JSON.stringify({ provider, apiKey: apiKey || undefined, model, enabled, isDefault })
      });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error || "Could not save provider.");
      setModels(body.models || []); setApiKey(""); await refresh(); notify("AI provider connected securely.");
    } catch (e) { setError(e instanceof Error ? e.message : "Could not save provider."); }
    finally { setSaving(false); }
  };
  const remove = async () => {
    setSaving(true); setError("");
    try {
      const { data } = await supabase!.auth.getSession();
      const response = await fetch("/api/ai-settings?provider=" + provider, { method:"DELETE", headers:{ Authorization:"Bearer " + (data.session?.access_token || "") } });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error || "Could not remove key.");
      await refresh(); setApiKey(""); setModels([]); notify("Provider credentials removed.");
    } catch (e) { setError(e instanceof Error ? e.message : "Could not remove provider."); }
    finally { setSaving(false); }
  };
  const selected = configs.find(c => c.provider === provider);
  const changeProvider = (next: Provider) => {
    setProvider(next); setApiKey(""); setError("");
    const config = configs.find(c => c.provider === next);
    setModel(config?.model || defaults[next]); setEnabled(config?.enabled ?? true); setIsDefault(Boolean(config?.is_default) || configs.length === 0); setModels(config?.models || []);
  };

  return <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) onClose(); }}>
    <section className="modal">
      <div className="modal-header"><div><div className="eyebrow">Preferences</div><h2>AI & app settings</h2></div><button className="icon-button" onClick={onClose} aria-label="Close"><X size={17}/></button></div>
      <div className="provider-row"><div><strong style={{fontSize:13}}>AI command assistant</strong><div className="helper">Simple commands work without an AI key.</div></div><span className={"pill " + (selected?.enabled && selected.has_key ? "on" : "")}>{selected?.enabled && selected.has_key ? "Connected" : "Optional"}</span></div>
      <label className="form-label">AI provider</label>
      <select className="field" value={provider} onChange={e => changeProvider(e.target.value as Provider)}><option value="groq">Groq · Fast inference</option><option value="openai">OpenAI · GPT</option><option value="xai">xAI · Grok</option></select>
      <label className="form-label">API key</label>
      <input className="field" type="password" autoComplete="new-password" value={apiKey} onChange={e => setApiKey(e.target.value)} placeholder={selected?.has_key ? "Saved securely · enter to replace" : "Paste your provider API key"}/>
      <label className="form-label">Model</label>
      {models.length ? <select className="field" value={model} onChange={e => setModel(e.target.value)}>{models.map(name => <option key={name} value={name}>{name}</option>)}</select> : <input className="field" value={model} onChange={e => setModel(e.target.value)} placeholder="Model ID"/>}
      <label className="form-label" style={{display:"flex",alignItems:"center",gap:9}}><input type="checkbox" checked={enabled} onChange={e => setEnabled(e.target.checked)}/> Enable this provider</label>
      <label className="form-label" style={{display:"flex",alignItems:"center",gap:9}}><input type="checkbox" checked={isDefault} onChange={e => setIsDefault(e.target.checked)}/> Use as my default AI provider</label>
      <p className="helper"><ShieldCheck size={13} style={{display:"inline",verticalAlign:"-2px",marginRight:5}}/>Keys are validated before saving and encrypted on the server. They are never written to browser storage or returned to the app.</p>
      {demo && <p className="helper">Connect a Supabase account to securely save provider credentials. Demo mode never stores API keys.</p>}
      {error && <p className="helper" style={{color:"var(--red)"}}>{error}</p>}
      <div style={{display:"flex",gap:9,marginTop:19}}><button className="primary-button" style={{flex:1}} disabled={saving || demo || !session || (!apiKey && !selected?.has_key)} onClick={save}>{saving ? <LoaderCircle size={15} className="animate-spin"/> : <Check size={15}/>} {selected?.has_key ? "Update & validate" : "Connect provider"}</button><button className="quiet-button" disabled={saving || demo || !selected?.has_key} onClick={remove}><Trash2 size={14}/> Remove</button></div>
      <div style={{borderTop:"1px solid var(--line)",marginTop:20,paddingTop:14}}><div className="section-title"><h2>Data & privacy</h2></div><p className="helper">Your cloud records are protected by Supabase Row Level Security. Demo data stays in this browser only. Export a CSV any time from the dashboard.</p></div>
    </section>
  </div>;
}