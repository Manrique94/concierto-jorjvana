-- ============================================================
-- SEGURIDAD 4 · CLAVE DE ADMIN CON HASH (pgcrypto)
-- ============================================================
-- Este archivo NO contiene ninguna clave real. El marcador
-- 'CAMBIA_ESTA_CLAVE_AQUI' debe reemplazarse por tu clave nueva
-- SOLO en el momento de pegar el script en el SQL Editor de
-- Supabase. No guardes esa clave en ningún archivo del proyecto
-- ni la subas a git.
--
-- Ejecuta los 3 pasos EN ORDEN, cada uno por separado, en:
-- Supabase > SQL Editor > New Query > Run
--
-- ROLLBACK: sql/supabase_seguridad_4_admin_hash_rollback.sql
-- ============================================================

-- ------------------------------------------------------------
-- PASO 1: agregar la columna donde se guarda el HASH (no la
-- clave en texto) de la contraseña de administrador.
-- ------------------------------------------------------------
alter table public.configuracion add column if not exists admin_pass_hash text;

-- ------------------------------------------------------------
-- PASO 2: definir la clave nueva.
-- ⚠️ Reemplaza 'CAMBIA_ESTA_CLAVE_AQUI' por tu clave real antes
-- de ejecutar esta instrucción. No dejes el marcador puesto, y
-- no guardes la versión con la clave real en ningún archivo.
-- ------------------------------------------------------------
update public.configuracion
   set admin_pass_hash = crypt('CAMBIA_ESTA_CLAVE_AQUI', gen_salt('bf'))
 where id = 1;

-- ------------------------------------------------------------
-- PASO 3: reemplazar verificar_admin() para que compare contra
-- el hash guardado en lugar de un texto literal en el código.
-- La firma (p_admin_key text -> boolean) no cambia, así que
-- ningún otro archivo (admin.html, validador.html,
-- api/enviar-entradas.js) necesita modificarse.
-- ------------------------------------------------------------
create or replace function public.verificar_admin(p_admin_key text)
returns boolean
language plpgsql
security definer
as $$
declare
  v_hash text;
begin
  if p_admin_key is null or length(p_admin_key) = 0 then
    return false;
  end if;

  select admin_pass_hash into v_hash from public.configuracion where id = 1;

  if v_hash is null then
    return false;
  end if;

  return v_hash = crypt(p_admin_key, v_hash);
end;
$$;

grant execute on function public.verificar_admin(text) to anon, authenticated;

-- ============================================================
-- FIN
-- ============================================================
