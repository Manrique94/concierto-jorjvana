-- ============================================================
-- ROLLBACK · SEGURIDAD 6 (RLS de compradores y entradas)
-- ============================================================
-- Úsalo solo si necesitas revertir de emergencia. Esto vuelve a
-- dejar las dos tablas exactamente como estaban antes del
-- script supabase_seguridad_6_cierre_rls_compradores_entradas.sql
-- (políticas abiertas, using(true)).
--
-- Recuerda: volver a este estado vuelve a permitir que cualquier
-- persona con la anon key lea/escriba estas tablas directo.
-- ============================================================

drop policy if exists "bloquear compradores" on public.compradores;
create policy "ver compradores"        on public.compradores for select using (true);
create policy "crear compra"           on public.compradores for insert with check (true);
create policy "actualizar compradores" on public.compradores for update using (true) with check (true);

drop policy if exists "bloquear entradas" on public.entradas;
create policy "anon entradas" on public.entradas for all using (true) with check (true);

-- ============================================================
-- FIN
-- ============================================================
