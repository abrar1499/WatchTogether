-- Pocket AI initial schema. Run with Supabase CLI or paste into SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  default_currency text not null default 'SAR',
  timezone text not null default 'Asia/Riyadh',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  account_type text not null default 'cash' check (account_type in ('cash','bank','savings','credit_card','custom')),
  currency text not null default 'SAR',
  opening_balance numeric(14,2) not null default 0,
  current_balance numeric(14,2) not null default 0,
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  unique (user_id, name)
);
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  icon text not null default 'dots',
  color text not null default '#a2adbd',
  kind text not null default 'both' check (kind in ('expense','income','both')),
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  unique (id, user_id),
  unique (user_id, name)
);
create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null,
  category_id uuid,
  description text not null,
  amount numeric(14,2) not null check (amount > 0),
  transaction_kind text not null check (transaction_kind in ('expense','income','transfer_out','transfer_in')),
  occurred_at timestamptz not null default now(),
  linked_transfer_id uuid,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (account_id, user_id) references public.accounts(id, user_id) on delete cascade,
  foreign key (category_id, user_id) references public.categories(id, user_id) on delete restrict
);
create index if not exists transactions_user_date_idx on public.transactions(user_id, occurred_at desc);
create index if not exists transactions_user_category_idx on public.transactions(user_id, category_id);

create table if not exists public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id uuid,
  name text not null,
  amount numeric(14,2) not null check (amount > 0),
  period text not null default 'monthly' check (period in ('weekly','monthly')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (category_id, user_id) references public.categories(id, user_id) on delete restrict,
  unique (user_id, name, period)
);
create table if not exists public.recurring_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null,
  category_id uuid,
  description text not null,
  amount numeric(14,2) not null check (amount > 0),
  transaction_kind text not null check (transaction_kind in ('expense','income')),
  frequency text not null check (frequency in ('weekly','monthly','yearly')),
  next_run_at timestamptz not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  foreign key (account_id, user_id) references public.accounts(id, user_id) on delete cascade,
  foreign key (category_id, user_id) references public.categories(id, user_id) on delete restrict
);
create table if not exists public.ai_provider_configs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (provider in ('groq','openai','xai')),
  model text not null,
  enabled boolean not null default true,
  is_default boolean not null default false,
  encrypted_credentials jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, provider)
);
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'Money assistant',
  created_at timestamptz not null default now()
);
create table if not exists public.conversation_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user','assistant')),
  content text not null,
  created_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;
create or replace function public.balance_delta(kind text, amount numeric)
returns numeric language sql immutable as $$
  select case when kind in ('income','transfer_in') then amount else -amount end;
$$;
create or replace function public.apply_transaction_balance()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    update public.accounts set current_balance = current_balance + public.balance_delta(new.transaction_kind, new.amount)
      where id = new.account_id and user_id = new.user_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.accounts set current_balance = current_balance - public.balance_delta(old.transaction_kind, old.amount)
      where id = old.account_id and user_id = old.user_id;
    return old;
  else
    update public.accounts set current_balance = current_balance - public.balance_delta(old.transaction_kind, old.amount)
      where id = old.account_id and user_id = old.user_id;
    update public.accounts set current_balance = current_balance + public.balance_delta(new.transaction_kind, new.amount)
      where id = new.account_id and user_id = new.user_id;
    return new;
  end if;
end;
$$;
drop trigger if exists transactions_balance_trigger on public.transactions;
create trigger transactions_balance_trigger after insert or update or delete on public.transactions
for each row execute function public.apply_transaction_balance();

create or replace function public.create_transfer(
  p_from_account uuid, p_to_account uuid, p_amount numeric, p_occurred_at timestamptz default now()
) returns uuid language plpgsql security invoker set search_path = public as $$
declare transfer_id uuid := gen_random_uuid(); owner_id uuid := auth.uid();
begin
  if owner_id is null then raise exception 'Authentication required'; end if;
  if p_amount <= 0 then raise exception 'Transfer amount must be positive'; end if;
  if p_from_account = p_to_account then raise exception 'Choose two different accounts'; end if;
  if (select count(*) from public.accounts where user_id = owner_id and id in (p_from_account,p_to_account) and archived = false) <> 2 then
    raise exception 'One or both accounts were not found';
  end if;
  insert into public.transactions(user_id,account_id,description,amount,transaction_kind,occurred_at,linked_transfer_id)
    values(owner_id,p_from_account,'Transfer out',p_amount,'transfer_out',p_occurred_at,transfer_id);
  insert into public.transactions(user_id,account_id,description,amount,transaction_kind,occurred_at,linked_transfer_id)
    values(owner_id,p_to_account,'Transfer in',p_amount,'transfer_in',p_occurred_at,transfer_id);
  return transfer_id;
end;
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, display_name) values(new.id, coalesce(new.raw_user_meta_data->>'name','')) on conflict (id) do nothing;
  insert into public.accounts(user_id,name,account_type,currency,opening_balance,current_balance)
    values(new.id,'Cash','cash','SAR',0,0) on conflict (user_id,name) do nothing;
  insert into public.categories(user_id,name,icon,color,kind) values
    (new.id,'Food & Drinks','coffee','#b6f36b','expense'),
    (new.id,'Transport','car','#8eb7ff','expense'),
    (new.id,'Bills','receipt','#d1a5ff','expense'),
    (new.id,'Shopping','bag','#ffbf8a','expense'),
    (new.id,'Health','heart','#ff9aa7','expense'),
    (new.id,'Subscriptions','card','#a5c8ff','expense'),
    (new.id,'Income','trend','#b6f36b','income'),
    (new.id,'Other','dots','#a2adbd','both')
  on conflict (user_id,name) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created_pocket_ai on auth.users;
create trigger on_auth_user_created_pocket_ai after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.accounts enable row level security;
alter table public.categories enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets enable row level security;
alter table public.recurring_rules enable row level security;
alter table public.ai_provider_configs enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_messages enable row level security;

create policy "profile owner can read and update" on public.profiles for all using (auth.uid() = id) with check (auth.uid() = id);
create policy "accounts owner" on public.accounts for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "categories owner" on public.categories for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "transactions owner" on public.transactions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "budgets owner" on public.budgets for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "recurring rules owner" on public.recurring_rules for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
-- Deliberately no authenticated-user policies on this table: encrypted provider credentials are server-only.
create policy "conversations owner" on public.conversations for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "conversation messages owner" on public.conversation_messages for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger accounts_updated_at before update on public.accounts for each row execute function public.set_updated_at();
create trigger categories_updated_at before update on public.categories for each row execute function public.set_updated_at();
create trigger transactions_updated_at before update on public.transactions for each row execute function public.set_updated_at();
create trigger budgets_updated_at before update on public.budgets for each row execute function public.set_updated_at();
create trigger ai_provider_configs_updated_at before update on public.ai_provider_configs for each row execute function public.set_updated_at();