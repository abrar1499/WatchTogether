import type { CommandAction } from "./types";

const money = "(\\d+(?:[,.]\\d{1,2})?)";

export function parseCommand(input: string): CommandAction | null {
  const text = input.trim();
  if (!text) return null;
  if (/^(help|what can i say|commands)$/i.test(text)) return { type: "help" };
  if (/^(show )?(all )?accounts$|^list accounts$/i.test(text)) return { type: "list_accounts" };
  if (/^(budget remaining|how much.*budget|what.*left.*budget)$/i.test(text)) return { type: "budget_remaining" };
  if (/^delete all transactions this month$/i.test(text)) return { type: "delete_all_month", confirmed: false };
  if (/^(confirm delete all transactions this month|yes, delete all transactions this month)$/i.test(text)) return { type: "delete_all_month", confirmed: true };
  if (/^(delete|remove) last transaction$|^delete last expense$/i.test(text)) return { type: "delete_last" };
  if (/^(undo|undo last action|undo last transaction)$/i.test(text)) return { type: "undo_last" };

  if (/^new account$/i.test(text)) return { type: "create_account" };
  const createAccount = text.match(/^new account\\s+(.+)$/i);
  if (createAccount) return { type: "create_account", name: createAccount[1].trim(), accountType: /cash/i.test(createAccount[1]) ? "cash" : /saving/i.test(createAccount[1]) ? "savings" : /card|credit/i.test(createAccount[1]) ? "credit_card" : "bank" };
  const renameAccount = text.match(/^rename\\s+(.+?)\\s+to\\s+(.+)$/i);
  if (renameAccount) {
    const from = renameAccount[1].replace(/ account$/i, "").trim();
    const to = renameAccount[2].trim();
    if (/food|transport|bills|shopping|health|subscription|other|income/i.test(from)) return { type: "rename_category", from, to };
    return { type: "rename_account", from, to };
  }
  const deleteAccount = text.match(/^delete account\\s+(.+)$/i);
  if (deleteAccount) return { type: "delete_account", name: deleteAccount[1].trim(), confirmed: false };
  const confirmAccount = text.match(/^confirm delete account\\s+(.+)$/i);
  if (confirmAccount) return { type: "delete_account", name: confirmAccount[1].trim(), confirmed: true };
  const deleteEntry = text.match(/^(?:delete|remove)\\s+(.+?)\\s+entry$/i);
  if (deleteEntry) return { type: "delete_transaction", query: deleteEntry[1].trim() };
  const changeAccount = text.match(/^change account to\\s+(.+)$/i);
  if (changeAccount) return { type: "update_last_account", accountName: changeAccount[1].trim() };
  if (/^move yesterday'?s expense to today$/i.test(text)) return { type: "update_last_date", date: "today" };
  if (/^move last expense to yesterday$/i.test(text)) return { type: "update_last_date", date: "yesterday" };
  const opening = text.match(new RegExp("^set opening balance " + money + "(?:\\s+(?:in|for)\\s+(.+))?$", "i"));
  if (opening) return { type: "set_opening_balance", amount: Number(opening[1].replace(",", "")), accountName: opening[2]?.trim() };

  const transfer = text.match(new RegExp("^(?:transfer|move) " + money + " (?:from )?(.+?) to (.+)$", "i"));
  if (transfer) return { type: "transfer", amount: Number(transfer[1].replace(",", "")), fromAccount: transfer[2].trim(), toAccount: transfer[3].trim() };

  const budget = text.match(new RegExp("^set (.+?) budget " + money + "$", "i"));
  if (budget) return { type: "set_budget", name: budget[1].trim(), amount: Number(budget[2].replace(",", "")) };
  const monthlyBudget = text.match(new RegExp("^change monthly budget to " + money + "$", "i"));
  if (monthlyBudget) return { type: "set_budget", name: "Monthly", amount: Number(monthlyBudget[1].replace(",", "")) };
  const category = text.match(/^create category\\s+(.+)$/i);
  if (category) return { type: "create_category", name: category[1].trim() };

  const update = text.match(new RegExp("^(?:actually |change last (?:expense|transaction) to |update last to |edit last to )?" + money + "$", "i"));
  if (update && /^(actually|change last|update last|edit last)/i.test(text)) return { type: "update_last_amount", amount: Number(update[1].replace(",", "")) };
  const edit = text.match(new RegExp("^edit (.+?) to " + money + "$", "i"));
  if (edit) return { type: "update_last_amount", amount: Number(edit[2].replace(",", "")) };

  if (/^(how much spent this month|monthly report|where did my money go|show this month|compare this month with last month)\\??$/i.test(text)) return { type: "summary", period: "month" };
  if (/^(show )?today'?s expenses$|^how much did i spend today\\??$/i.test(text)) return { type: "summary", period: "today" };
  if (/^(show )?last month'?s expenses$|^last month report$/i.test(text)) return { type: "summary", period: "last_month" };
  const last = text.match(/^last (\\d+) transactions$/i);
  if (last) return { type: "list_transactions", period: "all", limit: Math.min(50, Number(last[1])) };
  const food = text.match(/^show (.+?) expenses$/i);
  if (food) return { type: "list_transactions", period: "month", category: food[1].trim(), limit: 20 };
  if (/^show uncategorized expenses$/i.test(text)) return { type: "list_transactions", period: "month", category: "uncategorized", limit: 20 };

  // Prefix amount forms: "Spent 200 groceries yesterday", "Salary 8000 bank", "Received 500 cash".
  const spentFirst = text.match(new RegExp("^spent " + money + " (.+?)(?:\\s+(yesterday|today))?$", "i"));
  if (spentFirst) return {
    type: "create_transaction", transactionKind: "expense", amount: Number(spentFirst[1].replace(",", "")),
    description: spentFirst[2].trim(), categoryName: inferCategory(spentFirst[2]), date: spentFirst[3]?.toLowerCase()
  };
  const incomeFirst = text.match(new RegExp("^(salary|received|freelance|income) " + money + "(?:\\s+(cash|card|bank|savings|credit|[a-z][a-z0-9 &-]*))?$", "i"));
  if (incomeFirst) return {
    type: "create_transaction", transactionKind: "income", amount: Number(incomeFirst[2].replace(",", "")),
    description: incomeFirst[1].charAt(0).toUpperCase() + incomeFirst[1].slice(1).toLowerCase(),
    accountName: incomeFirst[3]?.trim(), categoryName: "Income"
  };
  const addFirst = text.match(new RegExp("^add " + money + " (.+)$", "i"));
  if (addFirst) return {
    type: "create_transaction", transactionKind: "expense", amount: Number(addFirst[1].replace(",", "")),
    description: addFirst[2].trim(), categoryName: inferCategory(addFirst[2])
  };

  // Description first forms: "Coffee 15 cash", "Fuel 100", "Netflix 45".
  const transaction = text.match(new RegExp("^(.+?)\\s+" + money + "(?:\\s+(cash|card|bank|savings|credit))?(?:\\s+(yesterday|today))?$", "i"));
  if (transaction) {
    const description = transaction[1].trim();
    const amount = Number(transaction[2].replace(",", ""));
    if (!description || !Number.isFinite(amount) || amount <= 0) return null;
    return {
      type: "create_transaction",
      transactionKind: "expense",
      amount,
      description,
      accountName: transaction[3]?.trim(),
      categoryName: inferCategory(description),
      date: transaction[4]?.toLowerCase()
    };
  }
  if (/^(how much left|show balance|account balance)\\??$/i.test(text)) return { type: "list_accounts" };
  return null;
}

export function inferCategory(description: string, income = false): string {
  if (income) return "Income";
  const value = description.toLowerCase();
  if (/coffee|lunch|dinner|breakfast|restaurant|food|grocery|groceries|snack|cafe|pizza|burger/.test(value)) return "Food & Drinks";
  if (/fuel|petrol|uber|taxi|bus|metro|parking|car/.test(value)) return "Transport";
  if (/netflix|spotify|subscription|prime|icloud|youtube premium/.test(value)) return "Subscriptions";
  if (/rent|electric|water|internet|bill|maintenance/.test(value)) return "Bills";
  if (/shopping|clothes|amazon|store/.test(value)) return "Shopping";
  if (/doctor|pharmacy|medicine|gym|health/.test(value)) return "Health";
  if (/salary|freelance|invoice|payment/.test(value)) return "Income";
  return "Other";
}