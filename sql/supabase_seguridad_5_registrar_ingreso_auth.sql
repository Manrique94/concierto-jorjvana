-- ============================================================
-- SEGURIDAD 5 · AUTORIZACIÓN REAL EN registrar_ingreso()
-- ============================================================
-- Qué hace este script:
--   Cambia la firma de registrar_ingreso de (p_codigo) a
--   (p_codigo, p_clave). Antes de tocar la entrada, valida que
--   p_clave corresponda a un validador activo o al admin. Si no
--   es válida, la función lanza una excepción y no marca nada.
--
-- Por qué es necesario:
--   Antes, cualquiera con la anon key (pública) podía marcar una
--   entrada como UTILIZADA llamando esta función directo, sin
--   pasar por el login de validador.html. La pantalla de login
--   no protegía nada del lado del servidor.
--
-- Requiere aplicar junto con el cambio en validador.html que
-- envía el código de acceso guardado en sessionStorage en cada
-- llamada a "Registrar ingreso".
--
-- Ejecuta TODO este script en: Supabase > SQL Editor > New Query > Run
--
-- ROLLBACK: sql/supabase_seguridad_5_registrar_ingreso_auth_rollback.sql
-- ============================================================

drop function if exists public.registrar_ingreso(text);

create or replace function public.registrar_ingreso(p_codigo text, p_clave text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_entrada public.entradas%rowtype;
  v_autorizado boolean;
begin
  v_autorizado := public.verificar_admin(p_clave)
               or coalesce((public.verificar_validador(p_clave)->>'valido')::boolean, false);

  if not v_autorizado then
    raise exception 'No autorizado. Vuelve a iniciar sesión como validador.';
  end if;

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

grant execute on function public.registrar_ingreso(text, text) to anon, authenticated;

-- ============================================================
-- FIN
-- ============================================================
