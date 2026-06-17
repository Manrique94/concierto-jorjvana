-- ============================================================
-- SEGURIDAD 7 · BUCKET "comprobantes" (Storage)
-- ============================================================
-- Qué hace este script:
--   1) Quita el permiso público para LISTAR archivos del bucket
--      (nadie podía ver la lista completa de comprobantes antes
--      de este cambio sin que se note; ahora se bloquea).
--   2) Quita el permiso público para BORRAR cualquier archivo.
--      Antes, cualquier persona con la anon key podía borrar el
--      comprobante de cualquier compra, incluso una ya aprobada.
--   3) Limita qué se puede subir: solo imágenes (jpg/png/webp/heic)
--      y un máximo de 8 MB por archivo.
--   4) Mueve el borrado del archivo de Storage AL INTERIOR de la
--      función eliminar_compra() (que ya exige la clave de admin),
--      para que el botón "Eliminar" del panel admin siga
--      funcionando exactamente igual para quien lo usa, pero ya
--      no exista una puerta pública para borrar archivos.
--
-- Qué NO cambia:
--   - Subir el comprobante (INSERT) sigue abierto sin necesitar
--     clave, porque hoy el comprador no tiene cuenta ni sesión:
--     es el mismo mecanismo que ya existía. Cerrarlo del todo
--     requeriría rehacer el flujo de compra (subir el archivo
--     desde el servidor en vez del navegador), lo cual es un
--     cambio mayor, fuera del alcance de este script.
--   - La URL pública de un comprobante puntual sigue siendo
--     accesible si alguien ya conoce esa URL exacta (el bucket es
--     público a propósito, para que las imágenes se vean en
--     admin.html/index.html sin firmar URLs). Este script no
--     cambia eso, solo evita que se pueda LISTAR todo el bucket.
--
-- Ejecuta TODO este script en: Supabase > SQL Editor > New Query > Run
--
-- ROLLBACK: sql/supabase_seguridad_7_storage_comprobantes_rollback.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1) Bloquear el listado público de archivos.
-- ------------------------------------------------------------
drop policy if exists "leer comprobantes" on storage.objects;
create policy "bloquear listado comprobantes" on storage.objects
  for select using (false);

-- ------------------------------------------------------------
-- 2) Bloquear el borrado público de archivos.
-- ------------------------------------------------------------
drop policy if exists "eliminar comprobantes" on storage.objects;
create policy "bloquear borrado comprobantes" on storage.objects
  for delete using (false);

-- ------------------------------------------------------------
-- 3) Limitar tipo y tamaño de archivo permitido en el bucket.
-- ------------------------------------------------------------
update storage.buckets
   set allowed_mime_types = array['image/jpeg','image/png','image/webp','image/heic','image/heif'],
       file_size_limit = 8388608 -- 8 MB
 where id = 'comprobantes';

-- ------------------------------------------------------------
-- 4) eliminar_compra ahora también borra el archivo de Storage
--    correspondiente (si existe), usando el mismo privilegio
--    elevado que ya usa para borrar la fila de "compradores".
--    La firma de la función NO cambia (p_comprador, p_admin_key).
-- ------------------------------------------------------------
create or replace function public.eliminar_compra(p_comprador uuid, p_admin_key text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_comprador public.compradores%rowtype;
  v_path      text;
  v_marker    text := '/comprobantes/';
  v_idx       int;
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

  if v_comprador.comprobante_url is not null then
    v_idx := position(v_marker in v_comprador.comprobante_url);
    if v_idx > 0 then
      v_path := substring(v_comprador.comprobante_url from v_idx + length(v_marker));
      delete from storage.objects where bucket_id = 'comprobantes' and name = v_path;
    end if;
  end if;

  delete from public.compradores where id = p_comprador;

  return jsonb_build_object('id', v_comprador.id, 'comprobante_url', v_comprador.comprobante_url);
end;
$$;

grant execute on function public.eliminar_compra(uuid, text) to anon, authenticated;

-- ============================================================
-- FIN
-- ============================================================
