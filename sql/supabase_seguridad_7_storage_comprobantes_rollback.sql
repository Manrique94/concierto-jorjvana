-- ============================================================
-- ROLLBACK · SEGURIDAD 7 (bucket comprobantes)
-- ============================================================
-- Úsalo solo si necesitas revertir de emergencia. Vuelve a dejar
-- el bucket "comprobantes" y la función eliminar_compra() como
-- estaban antes del script supabase_seguridad_7_storage_comprobantes.sql.
--
-- Si revierte esto, recuerda que admin.html ya no vuelve a borrar
-- el archivo de Storage por su cuenta desde el navegador (ese
-- código fue quitado). Tendrías que restaurar también esa parte
-- de admin.html con git si quieres el comportamiento 100%
-- idéntico al de antes de la Seguridad 7.
-- ============================================================

drop policy if exists "bloquear listado comprobantes" on storage.objects;
create policy "leer comprobantes" on storage.objects
  for select using (bucket_id = 'comprobantes');

drop policy if exists "bloquear borrado comprobantes" on storage.objects;
create policy "eliminar comprobantes" on storage.objects
  for delete using (bucket_id = 'comprobantes');

update storage.buckets
   set allowed_mime_types = null,
       file_size_limit = null
 where id = 'comprobantes';

create or replace function public.eliminar_compra(p_comprador uuid, p_admin_key text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_comprador public.compradores%rowtype;
begin
  if not public.verificar_admin(p_admin_key) then
    raise exception 'Clave de administrador incorrecta.';
  end if;

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

grant execute on function public.eliminar_compra(uuid, text) to anon, authenticated;

-- ============================================================
-- FIN
-- ============================================================
