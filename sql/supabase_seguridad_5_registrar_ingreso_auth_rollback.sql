-- ============================================================
-- ROLLBACK · SEGURIDAD 5 (autorización en registrar_ingreso)
-- ============================================================
-- Restaura la versión anterior de registrar_ingreso (sin
-- parámetro de clave). Si usas esto, recuerda que validador.html
-- también debe revertirse (deja de enviar p_clave), o las
-- llamadas fallarán por número de argumentos.
-- ============================================================

drop function if exists public.registrar_ingreso(text, text);

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

  update public.entradas set estado='UTILIZADA', fecha_ingreso=now() where id = v_entrada.id;
  insert into public.validaciones(entrada_id, codigo, resultado, accion) values (v_entrada.id, p_codigo, 'VALIDA', 'INGRESO');
  return jsonb_build_object('resultado','INGRESO_OK','nombre',v_entrada.nombre_asistente,'codigo',v_entrada.codigo,'fecha_ingreso',now());
end;
$$;

grant execute on function public.registrar_ingreso(text) to anon, authenticated;

-- ============================================================
-- FIN
-- ============================================================
