-- ============================================================
-- SEGURIDAD 6 · CIERRE DE RLS (compradores, entradas)
-- ============================================================
-- Qué hace este script:
--   Cierra el acceso directo vía REST (/rest/v1/<tabla>) a las
--   tablas "compradores" y "entradas". A partir de este script,
--   SOLO las funciones RPC (todas SECURITY DEFINER, ya
--   existentes: crear_reserva, registrar_comprobante,
--   consultar_compra, aprobar_pago, eliminar_compra,
--   registrar_ingreso, consultar_entrada, admin_*, etc.) pueden
--   leer o escribir estas tablas.
--
-- Qué NO cambia:
--   - Ninguna firma de función cambia.
--   - Ningún archivo del frontend necesita cambios: index.html,
--     admin.html y validador.html nunca leen ni escriben estas
--     tablas directo (sb.from(...)), siempre usan sb.rpc(...).
--   - El flujo de compra, aprobación y validación QR sigue igual.
--
-- Ejecuta TODO este script en: Supabase > SQL Editor > New Query > Run
--
-- ROLLBACK: sql/supabase_seguridad_6_cierre_rls_compradores_entradas_rollback.sql
-- ============================================================

drop policy if exists "ver compradores"        on public.compradores;
drop policy if exists "crear compra propia"    on public.compradores;
drop policy if exists "crear compra"           on public.compradores;
drop policy if exists "actualizar compradores" on public.compradores;
create policy "bloquear compradores" on public.compradores
  for all using (false) with check (false);

drop policy if exists "anon entradas" on public.entradas;
create policy "bloquear entradas" on public.entradas
  for all using (false) with check (false);

-- ============================================================
-- FIN
-- ============================================================
