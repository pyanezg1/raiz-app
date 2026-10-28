-- =====================================================================
-- Raíz Rutas · esquema del servidor (Supabase / Postgres)
-- Pegar completo en Supabase → SQL Editor → New query → Run.
-- Se puede volver a ejecutar: borra y recrea las funciones, no los datos.
-- =====================================================================

-- ---------- Tablas ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null default '',
  role        text not null default 'visitante'
              check (role in ('visitante','anfitrion_pendiente','anfitrion','admin')),
  wants_stop  text,
  created_at  timestamptz not null default now()
);

create table if not exists public.routes (
  id    text primary key,
  name  text not null,
  place text,
  km    int,
  days  text,
  mode  text
);

create table if not exists public.stops (
  id           text primary key,
  route_id     text not null references public.routes(id) on delete cascade,
  n            int  not null,
  name         text not null,
  sector       text,
  x            real not null,
  y            real not null,
  glyph        text not null default 'inicio',
  open_hours   text,
  story        text[] not null default '{}',
  word         text,
  word_meaning text,
  host_id      uuid references public.profiles(id) on delete set null,
  host_name    text,
  host_role    text,
  is_open      boolean not null default true,
  boat         boolean not null default false
);

create table if not exists public.offers (
  id          text primary key default ('x' || substr(md5(random()::text || clock_timestamp()::text), 1, 10)),
  stop_id     text not null references public.stops(id) on delete cascade,
  type        text not null check (type in ('producto','experiencia','servicio')),
  name        text not null,
  unit        text not null default '',
  price       int  not null check (price > 0),
  slots       text[],
  cap         int  check (cap is null or cap between 1 and 60),
  pay         text check (pay is null or pay in ('total','abono')),
  pct         int  check (pct is null or pct between 1 and 100),
  cancel      text check (cancel is null or cancel in ('flexible','moderada')),
  descr       text,
  incl        text,
  glyph       text,
  active      boolean not null default true,
  status      text not null default 'pendiente' check (status in ('aprobada','pendiente','rechazada')),
  review_note text,
  created_by  uuid references public.profiles(id) on delete set null,
  sort        int not null default 100,
  created_at  timestamptz not null default now()
);

create table if not exists public.bookings (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique,
  user_id        uuid references public.profiles(id) on delete set null,
  who            text,
  offer_id       text not null references public.offers(id),
  stop_id        text not null references public.stops(id),
  qty            int  not null check (qty between 1 and 60),
  slot           text,
  day            date not null,
  total          int  not null,
  paid           int  not null,
  due            int  not null default 0,
  method         text not null check (method in ('tarjeta','transferencia','efectivo')),
  status         text not null check (status in ('reservada','entregado','atendida','cancelada')),
  refund         int  not null default 0,
  payment_status text not null default 'simulado',
  created_at     timestamptz not null default now()
);
create index if not exists bookings_offer_day on public.bookings(offer_id, day, slot);
create index if not exists bookings_stop on public.bookings(stop_id, day);
create index if not exists bookings_user on public.bookings(user_id);

create table if not exists public.visits (
  user_id    uuid references public.profiles(id) on delete cascade,
  stop_id    text references public.stops(id) on delete cascade,
  visited_at timestamptz not null default now(),
  primary key (user_id, stop_id)
);

-- ---------- Seguridad ----------
-- Las tablas no se leen ni escriben directamente desde la app: todo pasa por las
-- funciones de abajo, que revisan quién llama. RLS activo y sin políticas = cerrado.
alter table public.profiles enable row level security;
alter table public.routes   enable row level security;
alter table public.stops    enable row level security;
alter table public.offers   enable row level security;
alter table public.bookings enable row level security;
alter table public.visits   enable row level security;

-- ---------- Perfil automático al crear una cuenta ----------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, role, wants_stop)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'name', ''),
          case when new.raw_user_meta_data->>'role' = 'anfitrion' then 'anfitrion_pendiente' else 'visitante' end,
          nullif(new.raw_user_meta_data->>'wants_stop', ''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Ayudas internas ----------
create or replace function public.today_cl() returns date
language sql stable as $$ select (now() at time zone 'America/Santiago')::date $$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
$$;

create or replace function public.my_stop() returns text
language sql stable security definer set search_path = public as $$
  select id from public.stops where host_id = auth.uid() order by n limit 1
$$;

create or replace function public.require_login() returns uuid
language plpgsql stable as $$
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión.' using errcode = '28000'; end if;
  return auth.uid();
end $$;

create or replace function public.booking_json(b public.bookings) returns json
language sql stable as $$
  select json_build_object('id', b.id, 'code', b.code, 'stop', b.stop_id, 'offer', b.offer_id, 'qty', b.qty,
    'slot', b.slot, 'day', b.day, 'total', b.total, 'paid', b.paid, 'due', b.due, 'method', b.method,
    'status', b.status, 'refund', b.refund, 'who', b.who, 'payment', b.payment_status, 'ts', b.created_at)
$$;

create or replace function public.offer_json(o public.offers) returns json
language sql stable as $$
  select json_build_object('id', o.id, 'type', o.type, 'name', o.name, 'unit', o.unit, 'price', o.price,
    'slots', o.slots, 'cap', o.cap, 'pay', o.pay, 'pct', o.pct, 'cancel', o.cancel, 'desc', o.descr,
    'incl', o.incl, 'g', o.glyph, 'active', o.active, 'status', o.status, 'note', o.review_note,
    'mine', o.created_by is not null and o.created_by = auth.uid())
$$;

-- ---------- Lectura pública ----------
create or replace function public.get_route(p_route text default 'budi') returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'route', (select json_build_object('id', r.id, 'name', r.name, 'place', r.place, 'km', r.km, 'days', r.days, 'mode', r.mode)
              from public.routes r where r.id = p_route),
    'stops', coalesce((
      select json_agg(json_build_object(
        'id', s.id, 'n', s.n, 'name', s.name, 'sector', s.sector, 'x', s.x, 'y', s.y, 'g', s.glyph,
        'open', s.open_hours, 'story', s.story, 'word', json_build_object('w', s.word, 'm', s.word_meaning),
        'host', case when s.host_name is null then null else json_build_object('name', s.host_name, 'role', s.host_role) end,
        'isOpen', s.is_open, 'boat', s.boat, 'mine', (s.host_id is not null and s.host_id = auth.uid()),
        'offers', coalesce((
          select json_agg(public.offer_json(o) order by o.sort, o.created_at)
          from public.offers o
          where o.stop_id = s.id
            and (o.status = 'aprobada' or s.host_id = auth.uid() or public.is_admin())
        ), '[]'::json)
      ) order by s.n)
      from public.stops s where s.route_id = p_route
    ), '[]'::json)
  )
$$;

create or replace function public.slot_usage(p_offer text, p_day date) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_object_agg(slot, used), '{}'::json)
  from (select slot, sum(qty)::int as used from public.bookings
        where offer_id = p_offer and day = p_day and status <> 'cancelada' and slot is not null
        group by slot) t
$$;

-- ---------- Cuenta ----------
create or replace function public.my_profile() returns json
language sql stable security definer set search_path = public as $$
  select case when auth.uid() is null then null else (
    select json_build_object('id', p.id, 'name', p.name, 'role', p.role, 'wants_stop', p.wants_stop,
      'email', (select u.email from auth.users u where u.id = p.id), 'stop', public.my_stop())
    from public.profiles p where p.id = auth.uid()) end
$$;

create or replace function public.request_host(p_wants text) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_login();
  update public.profiles set role = 'anfitrion_pendiente', wants_stop = nullif(trim(p_wants), '')
   where id = auth.uid() and role = 'visitante';
  return public.my_profile();
end $$;

create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_login();
  delete from auth.users where id = auth.uid();
end $$;

-- ---------- Visitante ----------
create or replace function public.my_bookings() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(public.booking_json(b) order by b.created_at), '[]'::json)
  from public.bookings b where b.user_id = auth.uid()
$$;

create or replace function public.my_visits() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(stop_id), '[]'::json) from public.visits where user_id = auth.uid()
$$;

create or replace function public.mark_visit(p_stop text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_login();
  insert into public.visits (user_id, stop_id) values (auth.uid(), p_stop) on conflict do nothing;
end $$;

create or replace function public.create_booking(p_offer text, p_qty int, p_slot text, p_day date,
                                                 p_pay_mode text, p_method text) returns json
language plpgsql security definer set search_path = public as $$
declare
  o public.offers; s public.stops; b public.bookings;
  v_used int; v_total int; v_now int; v_code text; v_name text; v_day date;
begin
  perform public.require_login();
  select * into o from public.offers where id = p_offer for update;   -- bloquea la oferta: evita sobrecupo
  if not found or o.status <> 'aprobada' or not o.active then raise exception 'Esta oferta no está disponible.'; end if;
  select * into s from public.stops where id = o.stop_id;
  if not s.is_open then raise exception 'Esta parada está cerrada hoy.'; end if;
  if p_qty is null or p_qty < 1 or p_qty > 60 then raise exception 'La cantidad no es válida.'; end if;
  if p_method not in ('tarjeta','transferencia','efectivo') then raise exception 'El medio de pago no es válido.'; end if;

  if o.type = 'producto' then
    v_day := public.today_cl();
  else
    if p_method = 'efectivo' then raise exception 'Las reservas se pagan en la app.'; end if;
    if o.slots is null or p_slot is null or not (p_slot = any (o.slots)) then raise exception 'El horario no es válido.'; end if;
    if p_day is null or p_day < public.today_cl() or p_day > public.today_cl() + 90 then raise exception 'La fecha no es válida.'; end if;
    v_day := p_day;
    select coalesce(sum(qty), 0) into v_used from public.bookings
     where offer_id = o.id and day = v_day and slot = p_slot and status <> 'cancelada';
    if v_used + p_qty > o.cap then
      if o.cap - v_used <= 0 then raise exception 'Ya no quedan cupos en ese horario. Elige otro horario o fecha.'; end if;
      raise exception 'Solo quedan % cupos en ese horario.', o.cap - v_used;
    end if;
  end if;

  v_total := o.price * p_qty;
  v_now := case when o.type <> 'producto' and o.pay = 'abono' and p_pay_mode = 'abono'
                then (round(v_total * o.pct / 1000.0) * 10)::int else v_total end;

  loop
    v_code := 'RZ-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 4));
    exit when not exists (select 1 from public.bookings where code = v_code);
  end loop;

  select name into v_name from public.profiles where id = auth.uid();
  insert into public.bookings (code, user_id, who, offer_id, stop_id, qty, slot, day, total, paid, due, method, status)
  values (v_code, auth.uid(), coalesce(nullif(v_name, ''), 'Visitante'), o.id, o.stop_id, p_qty,
          case when o.type = 'producto' then null else p_slot end, v_day, v_total, v_now, v_total - v_now, p_method,
          case when o.type = 'producto' then 'entregado' else 'reservada' end)
  returning * into b;
  return public.booking_json(b);
end $$;

create or replace function public.cancel_booking(p_id uuid) returns json
language plpgsql security definer set search_path = public as $$
declare b public.bookings; o public.offers; v_refund int;
begin
  perform public.require_login();
  select * into b from public.bookings where id = p_id and user_id = auth.uid() for update;
  if not found then raise exception 'No encontramos esa reserva.'; end if;
  if b.status <> 'reservada' then raise exception 'Esa reserva ya no se puede cancelar.'; end if;
  select * into o from public.offers where id = b.offer_id;
  v_refund := case when o.cancel = 'moderada' then (round(b.paid * 0.05) * 10)::int else b.paid end;
  update public.bookings set status = 'cancelada', refund = v_refund where id = b.id returning * into b;
  return public.booking_json(b);
end $$;

-- ---------- Anfitrión ----------
create or replace function public.host_dashboard() returns json
language sql stable security definer set search_path = public as $$
  select case when public.my_stop() is null then null else json_build_object(
    'stop', public.my_stop(),
    'bookings', coalesce((select json_agg(public.booking_json(b) order by b.day, b.slot nulls last, b.created_at)
                           from public.bookings b
                          where b.stop_id = public.my_stop() and b.day >= public.today_cl() - 7), '[]'::json),
    'month', coalesce((select round(sum((b.paid - b.refund + case when b.status = 'atendida' then b.due else 0 end) * 0.92))::int
                         from public.bookings b
                        where b.stop_id = public.my_stop()
                          and date_trunc('month', b.created_at at time zone 'America/Santiago') = date_trunc('month', now() at time zone 'America/Santiago')), 0),
    'today', (select count(*) from public.bookings b where b.stop_id = public.my_stop() and b.day = public.today_cl() and b.status <> 'cancelada')
  ) end
$$;

create or replace function public.attend_booking(p_code text) returns json
language plpgsql security definer set search_path = public as $$
declare b public.bookings;
begin
  perform public.require_login();
  select * into b from public.bookings where code = upper(trim(p_code)) for update;
  if not found or b.stop_id is distinct from public.my_stop() then
    raise exception 'No encontramos ese código en tus reservas. Revisa las letras y números.';
  end if;
  if b.status = 'cancelada' then raise exception 'Esa reserva fue cancelada por el visitante.'; end if;
  if b.status <> 'reservada' then raise exception 'Ese código ya fue usado.'; end if;
  update public.bookings set status = 'atendida' where id = b.id returning * into b;
  return public.booking_json(b);
end $$;

create or replace function public.set_stop_open(p_open boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_login();
  if public.my_stop() is null then raise exception 'Tu cuenta no tiene una parada asignada.'; end if;
  update public.stops set is_open = p_open where id = public.my_stop();
end $$;

create or replace function public.set_offer_active(p_offer text, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_login();
  update public.offers set active = p_active
   where id = p_offer and (stop_id = public.my_stop() or public.is_admin());
  if not found then raise exception 'No puedes cambiar esa oferta.'; end if;
end $$;

-- Crear o editar una experiencia. Las nuevas quedan en revisión de la red; las aprobadas
-- se actualizan al tiro (la familia es dueña de su precio).
create or replace function public.save_offer(p jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare
  v_stop text := public.my_stop(); o public.offers; v_slots text[]; v_bad text;
  v_name text := trim(coalesce(p->>'name', '')); v_desc text := trim(coalesce(p->>'desc', ''));
  v_unit text := trim(coalesce(p->>'unit', '')); v_price int := (p->>'price')::int; v_cap int := (p->>'cap')::int;
  v_pay text := p->>'pay'; v_pct int := nullif(p->>'pct', '')::int; v_cancel text := p->>'cancel';
begin
  perform public.require_login();
  if v_stop is null and not public.is_admin() then raise exception 'Tu cuenta no tiene una parada asignada.'; end if;
  select array_agg(trim(x)) into v_slots from jsonb_array_elements_text(coalesce(p->'slots', '[]'::jsonb)) x where trim(x) <> '';
  if v_name = '' then raise exception 'Escribe el nombre de la experiencia.'; end if;
  if length(v_desc) < 20 then raise exception 'Cuenta en al menos una frase qué va a vivir el visitante.'; end if;
  if v_unit = '' then raise exception 'Indica cuánto dura.'; end if;
  if v_price is null or v_price < 1000 then raise exception 'El precio por persona debe ser de al menos $1.000.'; end if;
  if v_cap is null or v_cap < 1 or v_cap > 60 then raise exception 'Los cupos por horario deben estar entre 1 y 60.'; end if;
  if v_slots is null then raise exception 'Agrega al menos un horario.'; end if;
  select x into v_bad from unnest(v_slots) x where x !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' limit 1;
  if v_bad is not null then raise exception 'Revisa este horario: %. Usa el formato 10:30.', v_bad; end if;
  if v_pay not in ('total','abono') then raise exception 'Elige cómo se paga al reservar.'; end if;
  if v_pay = 'abono' and v_pct not in (30, 50) then raise exception 'El abono debe ser de 30%% o 50%%.'; end if;
  if v_cancel not in ('flexible','moderada') then raise exception 'Elige una política de cancelación.'; end if;

  if p->>'id' is not null and p->>'id' <> '' then
    select * into o from public.offers where id = p->>'id' for update;
    if not found or (o.stop_id is distinct from v_stop and not public.is_admin()) then raise exception 'No puedes editar esa experiencia.'; end if;
    update public.offers set name = v_name, descr = v_desc, unit = v_unit, incl = nullif(trim(coalesce(p->>'incl', '')), ''),
           price = v_price, cap = v_cap, slots = v_slots, pay = v_pay, pct = case when v_pay = 'abono' then v_pct end,
           cancel = v_cancel, status = case when status = 'rechazada' then 'pendiente' else status end
     where id = o.id returning * into o;
  else
    insert into public.offers (stop_id, type, name, descr, unit, incl, price, cap, slots, pay, pct, cancel, status, created_by)
    values (coalesce(v_stop, p->>'stop'), 'experiencia', v_name, v_desc, v_unit, nullif(trim(coalesce(p->>'incl', '')), ''),
            v_price, v_cap, v_slots, v_pay, case when v_pay = 'abono' then v_pct end, v_cancel,
            case when public.is_admin() then 'aprobada' else 'pendiente' end, auth.uid())
    returning * into o;
  end if;
  return public.offer_json(o);
end $$;

-- ---------- Panel de la red (administración) ----------
create or replace function public.admin_pending() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Solo la red puede ver esto.'; end if;
  return json_build_object(
    'offers', coalesce((select json_agg(json_build_object('offer', public.offer_json(o), 'stop', s.name, 'stopId', s.id, 'host', s.host_name) order by o.created_at)
                          from public.offers o join public.stops s on s.id = o.stop_id where o.status = 'pendiente'), '[]'::json),
    'hosts',  coalesce((select json_agg(json_build_object('id', p.id, 'name', p.name, 'wants', p.wants_stop,
                                         'email', (select u.email from auth.users u where u.id = p.id)) order by p.created_at)
                          from public.profiles p where p.role = 'anfitrion_pendiente'), '[]'::json),
    'freeStops', coalesce((select json_agg(json_build_object('id', s.id, 'n', s.n, 'name', s.name) order by s.n)
                          from public.stops s where s.host_id is null), '[]'::json)
  );
end $$;

create or replace function public.admin_review_offer(p_offer text, p_ok boolean, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Solo la red puede aprobar experiencias.'; end if;
  update public.offers set status = case when p_ok then 'aprobada' else 'rechazada' end,
         review_note = nullif(trim(coalesce(p_note, '')), '') where id = p_offer;
end $$;

create or replace function public.admin_assign_host(p_user uuid, p_stop text) returns void
language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  if not public.is_admin() then raise exception 'Solo la red puede asignar anfitriones.'; end if;
  select name into v_name from public.profiles where id = p_user;
  if not found then raise exception 'No encontramos esa cuenta.'; end if;
  update public.stops set host_id = p_user, host_name = coalesce(nullif(v_name, ''), host_name) where id = p_stop and host_id is null;
  if not found then raise exception 'Esa parada ya tiene anfitrión.'; end if;
  update public.profiles set role = 'anfitrion' where id = p_user and role <> 'admin';
end $$;

-- ---------- Permisos de ejecución ----------
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.booking_json(public.bookings) from public, anon, authenticated;
revoke all on function public.offer_json(public.offers) from public, anon, authenticated;

grant execute on function public.get_route(text), public.slot_usage(text, date), public.my_profile() to anon, authenticated;
grant execute on function
  public.request_host(text), public.delete_my_account(), public.my_bookings(), public.my_visits(), public.mark_visit(text),
  public.create_booking(text, int, text, date, text, text), public.cancel_booking(uuid),
  public.host_dashboard(), public.attend_booking(text), public.set_stop_open(boolean), public.set_offer_active(text, boolean),
  public.save_offer(jsonb), public.admin_pending(), public.admin_review_offer(text, boolean, text), public.admin_assign_host(uuid, text)
  to authenticated;
