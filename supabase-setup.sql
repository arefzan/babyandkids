-- Baby & Kids: pega todo esto en Supabase > SQL Editor > New query > Run (en el proyecto NUEVO).
create table public.bk_admins (user_id uuid primary key references auth.users(id) on delete cascade);
create table public.bk_settings (id integer primary key, data jsonb default '{}'::jsonb);
create table public.bk_products (id uuid primary key default gen_random_uuid(), name text not null, price numeric default 0, old_price numeric, category text default '', description text default '', images text[] default '{}', sizes text[] default '{}', featured boolean default false, active boolean default true, sold_out boolean default false, created_at timestamptz default now(), stock integer default 1);
create table public.bk_costs (product_id uuid primary key references public.bk_products(id) on delete cascade, cost numeric default 0);
create table public.bk_sales (id uuid primary key default gen_random_uuid(), product_id uuid references public.bk_products(id) on delete set null, product_name text, size text default '', qty integer default 1, price numeric default 0, cost numeric default 0, customer text default '', sold_on date default ((now() at time zone 'America/Caracas'))::date, created_at timestamptz default now());
create table public.bk_visits (id bigint generated always as identity primary key, at timestamptz default now(), kind text, visitor text default '', source text default 'directo', device text default '', product_id uuid);
create index on public.bk_sales(sold_on); create index on public.bk_sales(product_id); create index on public.bk_visits(at); create index on public.bk_visits(product_id);
insert into public.bk_settings(id,data) values (1,'{}');

create or replace function public.bk_is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.bk_admins where user_id = auth.uid())
$$;

create or replace function public.bk_stats() returns json language plpgsql stable security definer set search_path = public as $$
declare tz text := 'America/Caracas'; today date := (now() at time zone tz)::date; r json;
begin
  if not public.bk_is_admin() then raise exception 'no autorizado'; end if;
  select json_build_object(
    'today', (select count(*) from bk_visits where kind='view' and (at at time zone tz)::date = today),
    'today_unique', (select count(distinct visitor) from bk_visits where kind='view' and (at at time zone tz)::date = today),
    'week', (select count(*) from bk_visits where kind='view' and (at at time zone tz)::date > today - 7),
    'month', (select count(*) from bk_visits where kind='view' and (at at time zone tz)::date > today - 30),
    'unique_month', (select count(distinct visitor) from bk_visits where kind='view' and (at at time zone tz)::date > today - 30),
    'wa_month', (select count(*) from bk_visits where kind='wa' and (at at time zone tz)::date > today - 30),
    'total', (select count(*) from bk_visits where kind='view'),
    'daily', (select json_agg(json_build_object('d', to_char(g,'YYYY-MM-DD'), 'n',
        (select count(*) from bk_visits v where v.kind='view' and (v.at at time zone tz)::date = g::date)) order by g)
      from generate_series(today - 29, today, interval '1 day') g),
    'sources', (select coalesce(json_agg(json_build_object('s', source, 'n', n) order by n desc), '[]'::json)
      from (select source, count(*) n from bk_visits where kind='view' and (at at time zone tz)::date > today - 30 group by source) s),
    'top', (select coalesce(json_agg(json_build_object('name', name, 'n', n) order by n desc), '[]'::json)
      from (select p.name, count(*) n from bk_visits v join bk_products p on p.id = v.product_id
            where v.kind='product' and (v.at at time zone tz)::date > today - 30 group by p.name order by n desc limit 6) t)
  ) into r;
  return r;
end $$;
revoke execute on function public.bk_stats() from anon;

alter table public.bk_admins enable row level security;
alter table public.bk_settings enable row level security;
alter table public.bk_products enable row level security;
alter table public.bk_costs enable row level security;
alter table public.bk_sales enable row level security;
alter table public.bk_visits enable row level security;

create policy "bk ver ajustes" on public.bk_settings for select to anon, authenticated using (true);
create policy "bk editar ajustes" on public.bk_settings for update to authenticated using ((select public.bk_is_admin())) with check ((select public.bk_is_admin()));
create policy "bk ver prendas" on public.bk_products for select to anon, authenticated using (active or (select public.bk_is_admin()));
create policy "bk crear prendas" on public.bk_products for insert to authenticated with check ((select public.bk_is_admin()));
create policy "bk editar prendas" on public.bk_products for update to authenticated using ((select public.bk_is_admin())) with check ((select public.bk_is_admin()));
create policy "bk borrar prendas" on public.bk_products for delete to authenticated using ((select public.bk_is_admin()));
create policy "bk costos admin" on public.bk_costs for all to authenticated using ((select public.bk_is_admin())) with check ((select public.bk_is_admin()));
create policy "bk ventas admin" on public.bk_sales for all to authenticated using ((select public.bk_is_admin())) with check ((select public.bk_is_admin()));
create policy "bk registrar visita" on public.bk_visits for insert to anon, authenticated with check (at > now() - interval '1 minute' and at < now() + interval '1 minute');

insert into storage.buckets (id, name, public) values ('bk-products','bk-products', true) on conflict (id) do nothing;
create policy "bk subir fotos" on storage.objects for insert to authenticated with check (bucket_id = 'bk-products' and (select public.bk_is_admin()));
create policy "bk ver fotos admin" on storage.objects for select to authenticated using (bucket_id = 'bk-products' and (select public.bk_is_admin()));
create policy "bk borrar fotos" on storage.objects for delete to authenticated using (bucket_id = 'bk-products' and (select public.bk_is_admin()));

-- DESPUÉS: crea el usuario en Authentication > Users > Add user
--   correo: aref_daniel.com@hotmail.com  · contraseña: la que quieras · marca "Auto Confirm User"
-- y luego corre esta línea para hacerlo administrador:
-- insert into public.bk_admins(user_id) select id from auth.users where email = 'aref_daniel.com@hotmail.com';
