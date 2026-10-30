export type Account = {
  id: string;
  name: string;
  account_type: string;
  currency: string;
  opening_balance: number;
  current_balance: number;
  created_at?: string;
};

export type Category = {
  id: string;
  name: string;
  icon: string;
  color: string;
  kind: "expense" | "income" | "both";
};

export type Transaction = {
  id: string;
  description: string;
  amount: number;
  transaction_kind: "expense" | "income" | "transfer_out" | "transfer_in";
  account_id: string;
  category_id: string | null;
  occurred_at: string;
  created_at?: string;
  linked_transfer_id?: string | null;
  accounts?: { name: string; currency: string } | null;
  categories?: { name: string; icon: string; color: string } | null;
};

export type Budget = {
  id: string;
  category_id: string | null;
  name: string;
  amount: number;
  period: "weekly" | "monthly";
};

export type FinanceData = {
  accounts: Account[];
  categories: Category[];
  transactions: Transaction[];
  budgets: Budget[];
};

export type CommandAction =
  | { type: "create_transaction"; transactionKind: "expense" | "income"; amount: number; description: string; accountName?: string; categoryName?: string; date?: string }
  | { type: "create_account"; name?: string; accountType?: string }
  | { type: "list_accounts" }
  | { type: "list_transactions"; period?: "today" | "week" | "month" | "all"; category?: string; limit?: number }
  | { type: "summary"; period: "today" | "month" | "last_month" }
  | { type: "update_last_amount"; amount: number }
  | { type: "delete_last" }
  | { type: "undo_last" }
  | { type: "transfer"; amount: number; fromAccount?: string; toAccount?: string }
  | { type: "set_budget"; name: string; amount: number }
  | { type: "budget_remaining" }
  | { type: "create_category"; name: string }
  | { type: "rename_account"; from: string; to: string }
  | { type: "rename_category"; from: string; to: string }
  | { type: "delete_transaction"; query: string }
  | { type: "delete_account"; name: string; confirmed: boolean }
  | { type: "update_last_account"; accountName: string }
  | { type: "update_last_date"; date: "today" | "yesterday" }
  | { type: "set_opening_balance"; amount: number; accountName?: string }
  | { type: "delete_all_month"; confirmed: boolean }
  | { type: "help" };