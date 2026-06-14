-- ============================================================
-- SISTEMA DE ENTRADAS - CONCIERTO ACÚSTICO JORJVANA
-- Esquema de base de datos para Supabase (PostgreSQL)
-- ============================================================
-- Ejecuta TODO este script en: Supabase > SQL Editor > New Query > Run
-- ============================================================

-- Extensión para generar UUID / aleatorios
create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- TABLA: compradores
-- ------------------------------------------------------------
create table if not exists public.compradores (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null,
  dni             text not null,
  celular         text not null,
  correo          text,
  cantidad        integer not null check (cantidad >= 1),
  total           numeric(10,2) not null,
  comprobante_url text,                       -- URL de la captura del pago (Storage)
  metodo_pago     text,                        -- 'Yape' | 'Plin'
  estado          text not null default 'PENDIENTE', -- PENDIENTE | APROBADO | RECHAZADO
  fecha_pago      timestamptz not null default now(),
  fecha_revision  timestamptz,
  created_at      timestamptz not null default now()
);

-- Migración: elimina rastros de la versión anterior con Supabase Auth
drop index if exists idx_compradores_user;
alter table public.compradores drop column if exists user_id;

-- Migración: reservas temporales de pago por Yape (30 minutos)
alter table public.compradores add column if not exists codigo_pago text;
alter table public.compradores add column if not exists expira_en timestamptz;
alter table public.compradores add column if not exists comprobante_hash text;

-- código de pago único (ej. JORJ-12345)
create unique index if not exists idx_compradores_codigo_pago
  on public.compradores(codigo_pago) where codigo_pago is not null;

-- un mismo comprobante no puede usarse en más de una compra
create unique index if not exists idx_compradores_comprobante_hash
  on public.compradores(comprobante_hash) where comprobante_hash is not null;

-- ------------------------------------------------------------
-- TABLA: entradas
-- ------------------------------------------------------------
create table if not exists public.entradas (
  id            uuid primary key default gen_random_uuid(),
  comprador_id  uuid not null references public.compradores(id) on delete cascade,
  codigo        text not null unique,          -- p.ej. JORJ-2026-A8F7K2
  numero        integer not null,              -- numeración automática 1..500
  estado        text not null default 'VALIDA',-- VALIDA | UTILIZADA | ANULADA
  nombre_asistente text not null,
  fecha_compra  timestamptz not null default now(),
  fecha_ingreso timestamptz,
  created_at    timestamptz not null default now()
);

create index if not exists idx_entradas_codigo on public.entradas(codigo);
create index if not exists idx_entradas_comprador on public.entradas(comprador_id);

-- ------------------------------------------------------------
-- TABLA: validaciones (historial de escaneos / ingresos)
-- ------------------------------------------------------------
create table if not exists public.validaciones (
  id          uuid primary key default gen_random_uuid(),
  entrada_id  uuid references public.entradas(id) on delete set null,
  codigo      text not null,
  resultado   text not null,                   -- VALIDA | UTILIZADA | ANULADA | NO_EXISTE
  accion      text,                            -- 'CONSULTA' | 'INGRESO'
  fecha       timestamptz not null default now()
);

-- ------------------------------------------------------------
-- TABLA: validadores (personas autorizadas por el admin para
-- validar/registrar el ingreso de entradas en la puerta)
-- ------------------------------------------------------------
create table if not exists public.validadores (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null,
  codigo     text not null,             -- código de acceso, ej. VAL-58321
  clave      text not null unique,
  estado     text not null default 'ACTIVO',
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);

-- Migración: tablas creadas con el esquema anterior (created_at,
-- sin "codigo" ni "estado") se actualizan al esquema actual.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='validadores' and column_name='created_at'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='validadores' and column_name='creado_en'
  ) then
    alter table public.validadores rename column created_at to creado_en;
  end if;
end $$;

alter table public.validadores add column if not exists codigo text;
update public.validadores set codigo = clave where codigo is null;
alter table public.validadores alter column codigo set not null;

alter table public.validadores add column if not exists estado text not null default 'ACTIVO';

-- ------------------------------------------------------------
-- TABLA: configuracion (aforo editable desde el panel admin)
-- ------------------------------------------------------------
create table if not exists public.configuracion (
  id    integer primary key default 1,
  aforo integer not null default 500,
  constraint configuracion_single_row check (id = 1)
);
insert into public.configuracion (id, aforo) values (1, 500)
  on conflict (id) do nothing;

-- ------------------------------------------------------------
-- SECUENCIA para numeración global de entradas (1..500...)
-- ------------------------------------------------------------
create sequence if not exists public.entrada_numero_seq start 1;

-- ------------------------------------------------------------
-- FUNCIÓN: aprobar pago y generar entradas con código único
-- ------------------------------------------------------------
create or replace function public.aprobar_pago(p_comprador uuid)
returns setof public.entradas
language plpgsql
security definer
as $$
declare
  v_comprador public.compradores%rowtype;
  v_i integer;
  v_codigo text;
  v_numero integer;
  v_existe integer;
begin
  select * into v_comprador from public.compradores where id = p_comprador for update;
  if not found then
    raise exception 'Comprador no existe';
  end if;
  if v_comprador.estado = 'APROBADO' then
    -- ya fue aprobado: devolver sus entradas existentes
    return query select * from public.entradas where comprador_id = p_comprador order by numero;
    return;
  end if;
  if v_comprador.estado not in ('PENDIENTE','PENDIENTE_APROBACION') then
    raise exception 'Esta compra no está pendiente de aprobación (estado: %).', v_comprador.estado;
  end if;

  for v_i in 1..v_comprador.cantidad loop
    -- generar código único no predecible
    loop
      v_codigo := 'JORJ-2026-' || upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 6));
      select count(*) into v_existe from public.entradas where codigo = v_codigo;
      exit when v_existe = 0;
    end loop;

    v_numero := nextval('public.entrada_numero_seq');

    insert into public.entradas (comprador_id, codigo, numero, estado, nombre_asistente)
    values (p_comprador, v_codigo, v_numero, 'VALIDA', v_comprador.nombre);
  end loop;

  update public.compradores
     set estado = 'APROBADO', fecha_revision = now()
   where id = p_comprador;

  return query select * from public.entradas where comprador_id = p_comprador order by numero;
end;
$$;

-- ------------------------------------------------------------
-- FUNCIÓN: entradas disponibles = aforo - vendidas - reservas activas
-- (RESERVADO no vencido o PENDIENTE/PENDIENTE_APROBACION cuentan
-- como "tomadas")
-- ------------------------------------------------------------
create or replace function public.contar_disponibles()
returns integer
language sql
stable
as $$
  select greatest(0,
    (select aforo from public.configuracion where id = 1)
    - (select count(*) from public.entradas)
    - (select coalesce(sum(cantidad), 0) from public.compradores
         where estado in ('PENDIENTE','PENDIENTE_APROBACION')
            or (estado = 'RESERVADO' and expira_en > now()))
  )::integer;
$$;

-- ------------------------------------------------------------
-- FUNCIÓN: limpiar reservas vencidas
-- (RESERVADO/PENDIENTE_PAGO con expira_en pasado -> EXPIRADO)
-- ------------------------------------------------------------
create or replace function public.limpiar_reservas_expiradas()
returns integer
language plpgsql
security definer
as $$
declare
  v_count integer;
begin
  update public.compradores
     set estado = 'EXPIRADO', fecha_revision = now()
   where estado in ('RESERVADO','PENDIENTE_PAGO')
     and expira_en is not null
     and expira_en < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ------------------------------------------------------------
-- FUNCIÓN: crear reserva temporal de pago por Yape (30 minutos)
-- Devuelve un objeto JSON con id, codigo_pago, expira_en, total,
-- cantidad y estado (no solo el uuid).
-- ------------------------------------------------------------
drop function if exists public.crear_reserva(text, text, text, text, integer, numeric, text);

create or replace function public.crear_reserva(
  p_nombre text, p_dni text, p_celular text, p_correo text,
  p_cantidad integer, p_total numeric, p_metodo text default 'Yape'
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_codigo text;
  v_existe integer;
  v_comprador public.compradores%rowtype;
begin
  perform public.limpiar_reservas_expiradas();

  if p_cantidad > public.contar_disponibles() then
    raise exception 'No hay suficientes entradas disponibles. Quedan % entrada(s).', public.contar_disponibles();
  end if;

  -- generar código de pago único, ej. JORJ-12345
  loop
    v_codigo := 'JORJ-' || lpad((floor(random()*100000))::int::text, 5, '0');
    select count(*) into v_existe from public.compradores where codigo_pago = v_codigo;
    exit when v_existe = 0;
  end loop;

  insert into public.compradores
    (nombre, dni, celular, correo, cantidad, total, metodo_pago, estado, codigo_pago, expira_en)
  values
    (p_nombre, p_dni, p_celular, p_correo, p_cantidad, p_total, p_metodo, 'RESERVADO', v_codigo, now() + interval '30 minutes')
  returning * into v_comprador;

  return jsonb_build_object(
    'id', v_comprador.id,
    'codigo_pago', v_comprador.codigo_pago,
    'expira_en', v_comprador.expira_en,
    'total', v_comprador.total,
    'cantidad', v_comprador.cantidad,
    'estado', v_comprador.estado
  );
end;
$$;

-- ------------------------------------------------------------
-- FUNCIÓN: registrar comprobante de pago (RESERVADO -> PENDIENTE_APROBACION)
-- Verifica que el comprobante no haya sido usado por otra compra.
-- Devuelve un objeto JSON con id, codigo_pago, expira_en, total,
-- cantidad, estado y comprobante_url.
-- ------------------------------------------------------------
drop function if exists public.registrar_comprobante(uuid, text, text);

create or replace function public.registrar_comprobante(
  p_comprador uuid, p_url text, p_hash text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_comprador public.compradores%rowtype;
  v_dup integer;
begin
  select * into v_comprador from public.compradores where id = p_comprador for update;
  if not found then
    raise exception 'Reserva no encontrada.';
  end if;

  if v_comprador.estado <> 'RESERVADO' then
    raise exception 'Esta reserva ya no está activa (estado: %).', v_comprador.estado;
  end if;

  if v_comprador.expira_en is not null and v_comprador.expira_en < now() then
    update public.compradores set estado = 'EXPIRADO', fecha_revision = now() where id = p_comprador;
    raise exception 'El tiempo de la reserva expiró. Genera un nuevo código de pago.';
  end if;

  select count(*) into v_dup from public.compradores
   where comprobante_hash = p_hash and id <> p_comprador;
  if v_dup > 0 then
    raise exception 'Este comprobante ya fue registrado en otra compra.';
  end if;

  update public.compradores
     set comprobante_url = p_url,
         comprobante_hash = p_hash,
         estado = 'PENDIENTE_APROBACION'
   where id = p_comprador
  returning * into v_comprador;

  return jsonb_build_object(
    'id', v_comprador.id,
    'codigo_pago', v_comprador.codigo_pago,
    'expira_en', v_comprador.expira_en,
    'total', v_comprador.total,
    'cantidad', v_comprador.cantidad,
    'estado', v_comprador.estado,
    'comprobante_url', v_comprador.comprobante_url
  );
end;
$$;

-- ------------------------------------------------------------
-- FUNCIÓN: eliminar una compra no aprobada (panel admin)
-- Solo permite borrar compras en estado RESERVADO, PENDIENTE,
-- PENDIENTE_APROBACION, RECHAZADO, EXPIRADO o CANCELADO.
-- Las compras APROBADO (y sus entradas) nunca se tocan.
-- Devuelve el comprobante_url para que el frontend borre el
-- archivo del bucket "comprobantes" si existe.
-- ------------------------------------------------------------
create or replace function public.eliminar_compra(p_comprador uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_comprador public.compradores%rowtype;
begin
  select * into v_comprador from public.compradores where id = p_comprador for update;
  if not found then
    raise exception 'Compra no encontrada.';
  end if;

  if v_comprador.estado not in ('RESERVADO','PENDIENTE','PENDIENTE_APROBACION','RECHAZADO','EXPIRADO','CANCELADO') then
    raise exception 'No se puede eliminar una compra con estado %.', v_comprador.estado;
  end if;

  delete from public.compradores where id = p_comprador;

  return jsonb_build_object('id', v_comprador.id, 'comprobante_url', v_comprador.comprobante_url);
end;
$$;

-- ------------------------------------------------------------
-- FUNCIÓN: registrar ingreso (marca UTILIZADA solo una vez)
-- ------------------------------------------------------------
create or replace function public.registrar_ingreso(p_codigo text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_entrada public.entradas%rowtype;
begin
  select * into v_entrada from public.entradas where codigo = p_codigo for update;

  if not found then
    insert into public.validaciones(codigo, resultado, accion) values (p_codigo, 'NO_EXISTE', 'INGRESO');
    return jsonb_build_object('resultado','NO_EXISTE');
  end if;

  if v_entrada.estado = 'ANULADA' then
    insert into public.validaciones(entrada_id, codigo, resultado, accion) values (v_entrada.id, p_codigo, 'ANULADA', 'INGRESO');
    return jsonb_build_object('resultado','ANULADA','nombre',v_entrada.nombre_asistente,'codigo',v_entrada.codigo);
  end if;

  if v_entrada.estado = 'UTILIZADA' then
    insert into public.validaciones(entrada_id, codigo, resultado, accion) values (v_entrada.id, p_codigo, 'UTILIZADA', 'INGRESO');
    return jsonb_build_object('resultado','UTILIZADA','nombre',v_entrada.nombre_asistente,'codigo',v_entrada.codigo,'fecha_ingreso',v_entrada.fecha_ingreso);
  end if;

  -- estado VALIDA -> marcar UTILIZADA
  update public.entradas set estado='UTILIZADA', fecha_ingreso=now() where id = v_entrada.id;
  insert into public.validaciones(entrada_id, codigo, resultado, accion) values (v_entrada.id, p_codigo, 'VALIDA', 'INGRESO');
  return jsonb_build_object('resultado','INGRESO_OK','nombre',v_entrada.nombre_asistente,'codigo',v_entrada.codigo,'fecha_ingreso',now());
end;
$$;

-- ------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ------------------------------------------------------------
alter table public.compradores enable row level security;
alter table public.entradas    enable row level security;
alter table public.validaciones enable row level security;
alter table public.configuracion enable row level security;
alter table public.validadores enable row level security;

-- Política permisiva (clave anónima). La compra no requiere cuenta ni
-- inicio de sesión: cualquiera puede registrar su compra directamente.
-- Para producción se recomienda restringir el panel admin con autenticación.
drop policy if exists "ver compradores"        on public.compradores;
drop policy if exists "crear compra propia"    on public.compradores;
drop policy if exists "crear compra"           on public.compradores;
drop policy if exists "actualizar compradores" on public.compradores;
create policy "ver compradores"        on public.compradores for select using (true);
create policy "crear compra"           on public.compradores for insert with check (true);
create policy "actualizar compradores" on public.compradores for update using (true) with check (true);
create policy "anon entradas"     on public.entradas     for all using (true) with check (true);
create policy "anon validaciones" on public.validaciones for all using (true) with check (true);
create policy "ver configuracion"        on public.configuracion for select using (true);
create policy "actualizar configuracion" on public.configuracion for update using (true) with check (true);
drop policy if exists "anon validadores" on public.validadores;
create policy "anon validadores" on public.validadores for all using (true) with check (true);

-- ------------------------------------------------------------
-- PERMISOS: las funciones deben ser ejecutables por anon/authenticated
-- para que PostgREST las expongo en /rest/v1/rpc/... (si no, devuelve
-- "Could not find the function ... in the schema cache").
-- ------------------------------------------------------------
grant execute on function public.aprobar_pago(uuid) to anon, authenticated;
grant execute on function public.contar_disponibles() to anon, authenticated;
grant execute on function public.limpiar_reservas_expiradas() to anon, authenticated;
grant execute on function public.crear_reserva(text, text, text, text, integer, numeric, text) to anon, authenticated;
grant execute on function public.registrar_comprobante(uuid, text, text) to anon, authenticated;
grant execute on function public.eliminar_compra(uuid) to anon, authenticated;
grant execute on function public.registrar_ingreso(text) to anon, authenticated;

-- ------------------------------------------------------------
-- STORAGE: bucket público para comprobantes de pago
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('comprobantes', 'comprobantes', true)
on conflict (id) do nothing;

drop policy if exists "subir comprobantes" on storage.objects;
drop policy if exists "leer comprobantes" on storage.objects;
drop policy if exists "eliminar comprobantes" on storage.objects;
create policy "subir comprobantes" on storage.objects
  for insert with check (bucket_id = 'comprobantes');
create policy "leer comprobantes" on storage.objects
  for select using (bucket_id = 'comprobantes');
create policy "eliminar comprobantes" on storage.objects
  for delete using (bucket_id = 'comprobantes');

-- ------------------------------------------------------------
-- VISTA: estadísticas rápidas
-- ------------------------------------------------------------
create or replace view public.v_estadisticas as
select
  (select count(*) from public.entradas)                                as vendidas,
  (select count(*) from public.entradas where estado='UTILIZADA')       as utilizadas,
  (select coalesce(sum(total),0) from public.compradores where estado='APROBADO') as recaudacion,
  public.contar_disponibles() as disponibles;

-- ============================================================
-- FIN DEL ESQUEMA
-- ============================================================
