-- ============================================================
-- FUNCIONES RPC FALTANTES · CONCIERTO JORJVANA
-- ============================================================
-- Ejecuta TODO este script en: Supabase > SQL Editor > New Query > Run
-- Es seguro volver a ejecutarlo (DROP + CREATE en cada función).
-- ============================================================

-- DROP previo de todas las funciones (resuelve conflictos de return type)
drop function if exists public.verificar_admin(text);
drop function if exists public.verificar_validador(text);
drop function if exists public.admin_listar_validadores(text);
drop function if exists public.admin_crear_validador(text,text,text);
drop function if exists public.admin_set_validador_activo(text,uuid,boolean);
drop function if exists public.admin_eliminar_validador(text,uuid);
drop function if exists public.obtener_aforo();
drop function if exists public.admin_actualizar_aforo(text,integer);
drop function if exists public.registrar_consulta_no_existe(text);
drop function if exists public.aprobar_pago(uuid);
drop function if exists public.aprobar_pago(uuid,text);
drop function if exists public.eliminar_compra(uuid);
drop function if exists public.eliminar_compra(uuid,text);

-- ============================================================
-- 1) verificar_admin
--    Valida la clave del administrador. Devuelve true/false.
--    ⚠️ TEMPORAL: la contraseña está hardcodeada para pruebas.
--    Antes de producción, moverla a una tabla de configuración
--    con hash bcrypt o usar Supabase Auth.
-- ============================================================
create or replace function public.verificar_admin(p_admin_key text)
returns boolean
language plpgsql
security definer
as $$
begin
  return p_admin_key = 'jorjvana2026';
end;
$$;

-- ============================================================
-- 2) verificar_validador
--    Verifica que el código de acceso pertenezca a un
--    validador activo. Devuelve {valido, nombre}.
-- ============================================================
create or replace function public.verificar_validador(p_clave text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_val public.validadores%rowtype;
begin
  select * into v_val
    from public.validadores
   where clave = p_clave and activo = true;

  if not found then
    return jsonb_build_object('valido', false, 'nombre', '');
  end if;

  return jsonb_build_object('valido', true, 'nombre', v_val.nombre);
end;
$$;

-- ============================================================
-- 3) admin_listar_validadores
--    Lista todos los validadores registrados.
-- ============================================================
create or replace function public.admin_listar_validadores(p_admin_key text)
returns setof public.validadores
language plpgsql
security definer
as $$
begin
  if not public.verificar_admin(p_admin_key) then
    raise exception 'Clave de administrador incorrecta.';
  end if;

  return query
    select * from public.validadores order by creado_en desc;
end;
$$;

-- ============================================================
-- 4) admin_crear_validador
--    Crea un nuevo validador con nombre y clave de acceso.
-- ============================================================
create or replace function public.admin_crear_validador(
  p_admin_key text,
  p_nombre    text,
  p_clave     text
)
returns void
language plpgsql
security definer
as $$
begin
  if not public.verificar_admin(p_admin_key) then
    raise exception 'Clave de administrador incorrecta.';
  end if;

  if exists (select 1 from public.validadores where clave = p_clave) then
    raise exception 'Ya existe un validador con ese código de acceso.';
  end if;

  insert into public.validadores (nombre, codigo, clave, activo)
  values (p_nombre, p_clave, p_clave, true);
end;
$$;

-- ============================================================
-- 5) admin_set_validador_activo
--    Activa o desactiva un validador.
-- ============================================================
create or replace function public.admin_set_validador_activo(
  p_admin_key text,
  p_id        uuid,
  p_activo    boolean
)
returns void
language plpgsql
security definer
as $$
begin
  if not public.verificar_admin(p_admin_key) then
    raise exception 'Clave de administrador incorrecta.';
  end if;

  update public.validadores
     set activo = p_activo,
         estado = case when p_activo then 'ACTIVO' else 'INACTIVO' end
   where id = p_id;

  if not found then
    raise exception 'Validador no encontrado.';
  end if;
end;
$$;

-- ============================================================
-- 6) admin_eliminar_validador
--    Elimina permanentemente un validador.
-- ============================================================
create or replace function public.admin_eliminar_validador(
  p_admin_key text,
  p_id        uuid
)
returns void
language plpgsql
security definer
as $$
begin
  if not public.verificar_admin(p_admin_key) then
    raise exception 'Clave de administrador incorrecta.';
  end if;

  delete from public.validadores where id = p_id;

  if not found then
    raise exception 'Validador no encontrado.';
  end if;
end;
$$;

-- ============================================================
-- 7) obtener_aforo
--    Devuelve el aforo configurado (no requiere autenticación,
--    se llama en el init() del panel antes del login).
-- ============================================================
create or replace function public.obtener_aforo()
returns integer
language sql
stable
as $$
  select aforo from public.configuracion where id = 1;
$$;

-- ============================================================
-- 8) admin_actualizar_aforo
--    Actualiza el aforo total del evento.
-- ============================================================
create or replace function public.admin_actualizar_aforo(
  p_admin_key text,
  p_aforo     integer
)
returns void
language plpgsql
security definer
as $$
begin
  if not public.verificar_admin(p_admin_key) then
    raise exception 'Clave de administrador incorrecta.';
  end if;

  if p_aforo < 1 then
    raise exception 'El aforo debe ser mayor a 0.';
  end if;

  update public.configuracion set aforo = p_aforo where id = 1;
end;
$$;

-- ============================================================
-- 9) registrar_consulta_no_existe
--    Inserta en validaciones cuando se escanea un código
--    que no existe en la base de datos (auditoría).
-- ============================================================
create or replace function public.registrar_consulta_no_existe(p_codigo text)
returns void
language plpgsql
security definer
as $$
begin
  insert into public.validaciones (codigo, resultado, accion)
  values (p_codigo, 'NO_EXISTE', 'CONSULTA');
end;
$$;

-- ============================================================
-- 10) aprobar_pago (FIRMA ACTUALIZADA: agrega p_admin_key)
--     DROP necesario porque PostgreSQL no permite cambiar la
--     firma de una función con CREATE OR REPLACE.
--     admin.html ya envía p_admin_key — ahora el SQL coincide.
-- ============================================================
drop function if exists public.aprobar_pago(uuid);

create function public.aprobar_pago(p_comprador uuid, p_admin_key text)
returns setof public.entradas
language plpgsql
security definer
as $$
declare
  v_comprador public.compradores%rowtype;
  v_i         integer;
  v_codigo    text;
  v_numero    integer;
  v_existe    integer;
begin
  if not public.verificar_admin(p_admin_key) then
    raise exception 'Clave de administrador incorrecta.';
  end if;

  select * into v_comprador from public.compradores where id = p_comprador for update;
  if not found then
    raise exception 'Comprador no existe';
  end if;

  if v_comprador.estado = 'APROBADO' then
    return query select * from public.entradas where comprador_id = p_comprador order by numero;
    return;
  end if;

  if v_comprador.estado not in ('PENDIENTE','PENDIENTE_APROBACION') then
    raise exception 'Esta compra no está pendiente de aprobación (estado: %).', v_comprador.estado;
  end if;

  for v_i in 1..v_comprador.cantidad loop
    loop
      v_codigo := 'JORJ-2026-' || upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 6));
      select count(*) into v_existe from public.entradas where codigo = v_codigo;
      exit when v_existe = 0;
    end loop;

    v_numero := nextval('public.entrada_numero_seq');

    insert into public.entradas (comprador_id, codigo, numero, estado, nombre_asistente)
    values (p_comprador, v_codigo, v_numero, 'VALIDA', v_comprador.nombre);
  end loop;

  update public.compradores
     set estado = 'APROBADO', fecha_revision = now()
   where id = p_comprador;

  return query select * from public.entradas where comprador_id = p_comprador order by numero;
end;
$$;

-- ============================================================
-- 11) eliminar_compra (FIRMA ACTUALIZADA: agrega p_admin_key)
--     admin.html ya envía p_admin_key — ahora el SQL coincide.
-- ============================================================
drop function if exists public.eliminar_compra(uuid);

create function public.eliminar_compra(p_comprador uuid, p_admin_key text)
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

-- ============================================================
-- GRANTS: todas las funciones deben ser ejecutables por anon
-- ============================================================
grant execute on function public.verificar_admin(text)                           to anon, authenticated;
grant execute on function public.verificar_validador(text)                       to anon, authenticated;
grant execute on function public.admin_listar_validadores(text)                  to anon, authenticated;
grant execute on function public.admin_crear_validador(text, text, text)         to anon, authenticated;
grant execute on function public.admin_set_validador_activo(text, uuid, boolean) to anon, authenticated;
grant execute on function public.admin_eliminar_validador(text, uuid)            to anon, authenticated;
grant execute on function public.obtener_aforo()                                 to anon, authenticated;
grant execute on function public.admin_actualizar_aforo(text, integer)           to anon, authenticated;
grant execute on function public.registrar_consulta_no_existe(text)              to anon, authenticated;
grant execute on function public.aprobar_pago(uuid, text)                        to anon, authenticated;
grant execute on function public.eliminar_compra(uuid, text)                     to anon, authenticated;

-- ============================================================
-- FIN
-- ============================================================
