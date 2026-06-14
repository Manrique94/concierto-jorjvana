-- ============================================================
-- FIX: funciones RPC faltantes en la base de datos real
-- contar_disponibles() y limpiar_reservas_expiradas()
-- ============================================================
-- Ejecuta este script en: Supabase > SQL Editor > New Query > Run
-- Es seguro volver a ejecutarlo (usa IF NOT EXISTS / OR REPLACE).
-- ============================================================

-- Dependencia: tabla de configuración (aforo editable desde el panel admin)
create table if not exists public.configuracion (
  id    integer primary key default 1,
  aforo integer not null default 500,
  constraint configuracion_single_row check (id = 1)
);
insert into public.configuracion (id, aforo) values (1, 500)
  on conflict (id) do nothing;

alter table public.configuracion enable row level security;
drop policy if exists "ver configuracion" on public.configuracion;
drop policy if exists "actualizar configuracion" on public.configuracion;
create policy "ver configuracion"        on public.configuracion for select using (true);
create policy "actualizar configuracion" on public.configuracion for update using (true) with check (true);

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

-- Las funciones deben ser ejecutables por anon/authenticated para que
-- PostgREST las expongo en /rest/v1/rpc/... (si no, devuelve
-- "Could not find the function ... in the schema cache").
grant execute on function public.contar_disponibles() to anon, authenticated;
grant execute on function public.limpiar_reservas_expiradas() to anon, authenticated;

-- ============================================================
-- FIN
-- ============================================================
