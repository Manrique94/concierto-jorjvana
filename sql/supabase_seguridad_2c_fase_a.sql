-- ============================================================
-- SEGURIDAD 2C · FASE A
-- Nuevas funciones RPC (security definer) para compradores y
-- entradas. NO modifica policies de RLS (siguen using(true)).
-- Ejecuta TODO este script en: Supabase > SQL Editor > New Query > Run
-- Es seguro volver a ejecutarlo (create or replace).
-- ============================================================

-- ------------------------------------------------------------
-- 1) consultar_compra: lookup público por codigo_pago + dni
--    Reemplaza el select directo a "compradores" + "entradas"
--    en index.html (Mis entradas).
-- ------------------------------------------------------------
create or replace function public.consultar_compra(p_codigo_pago text, p_dni text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_comprador public.compradores%rowtype;
  v_entradas  jsonb := '[]'::jsonb;
begin
  select * into v_comprador
    from public.compradores
   where codigo_pago = upper(p_codigo_pago) and dni = p_dni;

  if not found then
    return null;
  end if;

  if v_comprador.estado = 'APROBADO' then
    select coalesce(jsonb_agg(to_jsonb(e) order by e.numero), '[]'::jsonb)
      into v_entradas
      from public.entradas e
     where e.comprador_id = v_comprador.id;
  end if;

  return jsonb_build_object(
    'id', v_comprador.id,
    'nombre', v_comprador.nombre,
    'dni', v_comprador.dni,
    'celular', v_comprador.celular,
    'correo', v_comprador.correo,
    'cantidad', v_comprador.cantidad,
    'total', v_comprador.total,
    'metodo_pago', v_comprador.metodo_pago,
    'estado', v_comprador.estado,
    'codigo_pago', v_comprador.codigo_pago,
    'expira_en', v_comprador.expira_en,
    'comprobante_url', v_comprador.comprobante_url,
    'fecha_pago', v_comprador.fecha_pago,
    'fecha_revision', v_comprador.fecha_revision,
    'entradas', v_entradas
  );
end;
$$;

-- ------------------------------------------------------------
-- 2) admin_listar_compradores: listado completo (panel admin)
-- ------------------------------------------------------------
create or replace function public.admin_listar_compradores(p_admin_key text)
returns setof public.compradores
language plpgsql
security definer
as $$
begin
  if not public.verificar_admin(p_admin_key) then
    raise exception 'Clave de administrador incorrecta.';
  end if;

  return query
    select * from public.compradores order by created_at desc;
end;
$$;

-- ------------------------------------------------------------
-- 3) admin_estadisticas: vendidas/utilizadas/anuladas/recaudacion/disponibles
--    Reemplaza el select('estado') de entradas en loadAdmin() y
--    el count usado en guardarAforo().
-- ------------------------------------------------------------
create or replace function public.admin_estadisticas(p_admin_key text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_vendidas integer;
  v_utilizadas integer;
  v_anuladas integer;
  v_recaudacion numeric;
begin
  if not public.verificar_admin(p_admin_key) then
    raise exception 'Clave de administrador incorrecta.';
  end if;

  select count(*),
         count(*) filter (where estado = 'UTILIZADA'),
         count(*) filter (where estado = 'ANULADA')
    into v_vendidas, v_utilizadas, v_anuladas
    from public.entradas;

  select coalesce(sum(total), 0) into v_recaudacion
    from public.compradores where estado = 'APROBADO';

  return jsonb_build_object(
    'vendidas', v_vendidas,
    'utilizadas', v_utilizadas,
    'anuladas', v_anuladas,
    'recaudacion', v_recaudacion,
    'disponibles', public.contar_disponibles()
  );
end;
$$;

-- ------------------------------------------------------------
-- 4) admin_rechazar_pago: reemplaza el update directo en rechazar()
-- ------------------------------------------------------------
create or replace function public.admin_rechazar_pago(p_admin_key text, p_comprador uuid)
returns void
language plpgsql
security definer
as $$
begin
  if not public.verificar_admin(p_admin_key) then
    raise exception 'Clave de administrador incorrecta.';
  end if;

  update public.compradores
     set estado = 'RECHAZADO', fecha_revision = now()
   where id = p_comprador;

  if not found then
    raise exception 'Compra no encontrada.';
  end if;
end;
$$;

-- ------------------------------------------------------------
-- 5) admin_listar_ventas: entradas + datos del comprador embebidos
--    Reemplaza el join sb.from('entradas').select('*, compradores(...)')
--    Devuelve filas (no jsonb envuelto) para no romper renderVentas().
-- ------------------------------------------------------------
create or replace function public.admin_listar_ventas(p_admin_key text)
returns table (
  id uuid,
  comprador_id uuid,
  codigo text,
  numero integer,
  estado text,
  nombre_asistente text,
  fecha_compra timestamptz,
  fecha_ingreso timestamptz,
  created_at timestamptz,
  compradores jsonb
)
language plpgsql
security definer
as $$
begin
  if not public.verificar_admin(p_admin_key) then
    raise exception 'Clave de administrador incorrecta.';
  end if;

  return query
    select e.id, e.comprador_id, e.codigo, e.numero, e.estado, e.nombre_asistente,
           e.fecha_compra, e.fecha_ingreso, e.created_at,
           jsonb_build_object(
             'nombre', c.nombre, 'dni', c.dni, 'correo', c.correo,
             'celular', c.celular, 'codigo_pago', c.codigo_pago
           ) as compradores
      from public.entradas e
      join public.compradores c on c.id = e.comprador_id
     order by e.numero desc;
end;
$$;

-- ------------------------------------------------------------
-- 6) admin_obtener_entradas: entradas de un comprador (Ver entradas)
-- ------------------------------------------------------------
create or replace function public.admin_obtener_entradas(p_admin_key text, p_comprador uuid)
returns setof public.entradas
language plpgsql
security definer
as $$
begin
  if not public.verificar_admin(p_admin_key) then
    raise exception 'Clave de administrador incorrecta.';
  end if;

  return query
    select * from public.entradas where comprador_id = p_comprador order by numero;
end;
$$;

-- ------------------------------------------------------------
-- 7) admin_anular_entrada: reemplaza el update directo en anularEntrada()
-- ------------------------------------------------------------
create or replace function public.admin_anular_entrada(p_admin_key text, p_entrada uuid)
returns void
language plpgsql
security definer
as $$
begin
  if not public.verificar_admin(p_admin_key) then
    raise exception 'Clave de administrador incorrecta.';
  end if;

  update public.entradas set estado = 'ANULADA' where id = p_entrada;

  if not found then
    raise exception 'Entrada no encontrada.';
  end if;
end;
$$;

-- ------------------------------------------------------------
-- 8) consultar_entrada: lookup público de una entrada por código
--    (solo lectura). Reemplaza el select directo en validador.html.
-- ------------------------------------------------------------
create or replace function public.consultar_entrada(p_codigo text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_entrada public.entradas%rowtype;
begin
  select * into v_entrada from public.entradas where codigo = p_codigo;
  if not found then
    return null;
  end if;
  return to_jsonb(v_entrada);
end;
$$;

-- ------------------------------------------------------------
-- GRANTS: igual que el resto de RPCs del proyecto
-- ------------------------------------------------------------
grant execute on function public.consultar_compra(text, text)        to anon, authenticated;
grant execute on function public.admin_listar_compradores(text)       to anon, authenticated;
grant execute on function public.admin_estadisticas(text)             to anon, authenticated;
grant execute on function public.admin_rechazar_pago(text, uuid)      to anon, authenticated;
grant execute on function public.admin_listar_ventas(text)            to anon, authenticated;
grant execute on function public.admin_obtener_entradas(text, uuid)   to anon, authenticated;
grant execute on function public.admin_anular_entrada(text, uuid)     to anon, authenticated;
grant execute on function public.consultar_entrada(text)              to anon, authenticated;

-- ============================================================
-- FIN FASE A
-- ============================================================
