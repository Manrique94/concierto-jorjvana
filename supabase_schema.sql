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
  clave      text not null unique,
  activo     boolean not null default true,
  created_at timestamptz not null default now()
);

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
-- STORAGE: bucket público para comprobantes de pago
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('comprobantes', 'comprobantes', true)
on conflict (id) do nothing;

create policy "subir comprobantes" on storage.objects
  for insert with check (bucket_id = 'comprobantes');
create policy "leer comprobantes" on storage.objects
  for select using (bucket_id = 'comprobantes');

-- ------------------------------------------------------------
-- VISTA: estadísticas rápidas
-- ------------------------------------------------------------
create or replace view public.v_estadisticas as
select
  (select count(*) from public.entradas)                                as vendidas,
  (select count(*) from public.entradas where estado='UTILIZADA')       as utilizadas,
  (select coalesce(sum(total),0) from public.compradores where estado='APROBADO') as recaudacion,
  ((select aforo from public.configuracion where id=1) - (select count(*) from public.entradas)) as disponibles;

-- ============================================================
-- FIN DEL ESQUEMA
-- ============================================================
