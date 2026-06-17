-- ============================================================
-- SEGURIDAD 3 · CIERRE DE RLS (validadores, validaciones, configuracion)
-- ============================================================
-- Qué hace este script:
--   Cierra el acceso directo vía REST (/rest/v1/<tabla>) a las
--   tablas "validadores", "validaciones" y "configuracion".
--   A partir de este script, SOLO las funciones RPC (todas
--   SECURITY DEFINER, ya existentes) pueden leer o escribir
--   estas tablas. El acceso anon/authenticated vía REST directo
--   queda bloqueado por completo.
--
-- Qué NO cambia:
--   - Ninguna firma de función RPC cambia.
--   - Ningún archivo del frontend necesita cambios.
--   - El flujo de compra, aprobación y validación QR sigue igual.
--
-- Excepción técnica necesaria:
--   "contar_disponibles()" y "obtener_aforo()" se llaman
--   directamente desde el navegador (RPC) y no eran SECURITY
--   DEFINER, así que sin este ajuste perderían acceso de lectura
--   a "configuracion" en cuanto se cierre su RLS. Se les agrega
--   SECURITY DEFINER (su lógica y su firma no cambian en nada).
--
-- Ejecuta TODO este script en: Supabase > SQL Editor > New Query > Run
-- Es seguro volver a ejecutarlo.
--
-- ROLLBACK: para revertir, vuelve a ejecutar las políticas
-- originales (using(true)) que están documentadas en
-- sql/supabase_schema.sql líneas 405-417, y quita "security
-- definer" de contar_disponibles()/obtener_aforo() volviendo a
-- su versión en sql/supabase_schema.sql y sql/supabase_fix_rpc.sql.
-- ============================================================

-- ------------------------------------------------------------
-- 1) validadores: cierre total.
--    Acceso solo vía: verificar_validador, admin_listar_validadores,
--    admin_crear_validador, admin_set_validador_activo,
--    admin_eliminar_validador (todas SECURITY DEFINER).
-- ------------------------------------------------------------
drop policy if exists "anon validadores" on public.validadores;
create policy "bloquear validadores" on public.validadores
  for all using (false) with check (false);

-- ------------------------------------------------------------
-- 2) validaciones: cierre total.
--    Acceso solo vía: registrar_ingreso, registrar_consulta_no_existe
--    (ambas SECURITY DEFINER).
-- ------------------------------------------------------------
drop policy if exists "anon validaciones" on public.validaciones;
create policy "bloquear validaciones" on public.validaciones
  for all using (false) with check (false);

-- ------------------------------------------------------------
-- 3) configuracion: cierre total (select + update).
-- ------------------------------------------------------------
drop policy if exists "ver configuracion" on public.configuracion;
drop policy if exists "actualizar configuracion" on public.configuracion;
create policy "bloquear configuracion select" on public.configuracion
  for select using (false);
create policy "bloquear configuracion update" on public.configuracion
  for update using (false) with check (false);

-- Las dos únicas funciones que leen "aforo" directamente desde el
-- cliente pasan a SECURITY DEFINER para conservar su comportamiento
-- actual sin depender de RLS abierta. Lógica y firma sin cambios.
create or replace function public.contar_disponibles()
returns integer
language sql
stable
security definer
as $$
  select greatest(0,
    (select aforo from public.configuracion where id = 1)
    - (select count(*) from public.entradas)
    - (select coalesce(sum(cantidad), 0) from public.compradores
         where estado in ('PENDIENTE','PENDIENTE_APROBACION')
            or (estado = 'RESERVADO' and expira_en > now()))
  )::integer;
$$;

create or replace function public.obtener_aforo()
returns integer
language sql
stable
security definer
as $$
  select aforo from public.configuracion where id = 1;
$$;

grant execute on function public.contar_disponibles() to anon, authenticated;
grant execute on function public.obtener_aforo() to anon, authenticated;

-- ============================================================
-- FIN
-- ============================================================
