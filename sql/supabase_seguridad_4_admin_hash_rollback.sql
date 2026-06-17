-- ============================================================
-- ROLLBACK · SEGURIDAD 4 (clave de admin con hash)
-- ============================================================
-- Úsalo solo si necesitas revertir de emergencia (ej. el panel
-- admin queda inaccesible la noche del evento).
--
-- Igual que en el script original, NO escribas tu clave real
-- aquí ni la subas a git: reemplaza 'CAMBIA_ESTA_CLAVE_AQUI'
-- justo antes de ejecutar, solo en el SQL Editor de Supabase.
-- ============================================================

create or replace function public.verificar_admin(p_admin_key text)
returns boolean
language plpgsql
security definer
as $$
begin
  return p_admin_key = 'CAMBIA_ESTA_CLAVE_AQUI';
end;
$$;

grant execute on function public.verificar_admin(text) to anon, authenticated;

-- Nota: la columna admin_pass_hash en "configuracion" puede
-- quedarse sin uso, no es necesario borrarla para que este
-- rollback funcione.

-- ============================================================
-- FIN
-- ============================================================
