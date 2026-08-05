-- ============================================================================
-- 008_funciones_reserva.sql
--
-- La lógica que NO puede vivir en el navegador. Hoy toda la validación de
-- una reserva está en JavaScript: cualquiera con la consola abierta (o con
-- curl y la anon key, que es pública) puede saltearse el horario laboral,
-- reservar en un día cerrado o pisar un turno existente.
--
-- Estas funciones son SECURITY DEFINER: corren con permisos elevados y son
-- la ÚNICA puerta de entrada para crear o modificar un turno. El front-end
-- las llama con supabase.rpc(...). El motor de JS sigue existiendo, pero
-- pasa a ser lo que debe ser: una optimización de UX (no mostrar horarios
-- imposibles), no la barrera de seguridad.
--
-- Correr DESPUÉS de 007_motor_disponibilidad.sql.
-- ============================================================================

-- ============================================================================
-- 1. LECTURA PÚBLICA DE DISPONIBILIDAD (sin datos personales)
-- ============================================================================

/**
 * Jornadas laborales de cada día de un rango, ya resueltas:
 * horario semanal → pisado por excepciones ('cerrado' elimina el día,
 * 'especial' lo reemplaza). Devuelve una fila por tramo (jornada partida
 * = dos filas para el mismo día).
 */
create or replace function jornadas_rango(p_desde date, p_hasta date)
returns table (fecha date, hora_inicio time, hora_fin time)
language sql
stable
security definer
set search_path = public
as $$
  with dias as (
    select generate_series(p_desde, p_hasta, interval '1 day')::date as fecha
  ),
  cerrados as (
    select d.fecha
    from dias d
    join excepciones_horario e
      on e.tipo = 'cerrado' and d.fecha between e.fecha_desde and e.fecha_hasta
  ),
  especiales as (
    select d.fecha, e.hora_inicio, e.hora_fin
    from dias d
    join excepciones_horario e
      on e.tipo = 'especial' and d.fecha between e.fecha_desde and e.fecha_hasta
  )
  select d.fecha, esp.hora_inicio, esp.hora_fin
  from dias d
  join especiales esp on esp.fecha = d.fecha
  where d.fecha not in (select fecha from cerrados)

  union all

  select d.fecha, hs.hora_inicio, hs.hora_fin
  from dias d
  join horarios_semanales hs
    on hs.activo and hs.dia_semana = extract(dow from d.fecha)::int
  where d.fecha not in (select fecha from cerrados)
    and d.fecha not in (select fecha from especiales)

  order by 1, 2;
$$;

/**
 * Franjas ocupadas de un rango: turnos activos + bloqueos manuales + holds
 * vigentes. Devuelve SOLO horarios, nunca nombres ni teléfonos — por eso
 * puede ser pública sin exponer a tus clientes.
 */
create or replace function ocupacion_rango(p_desde date, p_hasta date)
returns table (fecha date, hora_inicio time, hora_fin time, tipo text)
language sql
stable
security definer
set search_path = public
as $$
  select t.fecha,
         (lower(t.rango))::time,
         (upper(t.rango))::time,
         'turno'::text
  from turnos t
  where t.fecha between p_desde and p_hasta
    and t.estado in ('pendiente', 'confirmado', 'en_atencion', 'finalizado')

  union all

  select b.fecha, b.hora_inicio, b.hora_fin, 'bloqueo'
  from bloqueos b
  where b.fecha between p_desde and p_hasta

  union all

  select h.fecha,
         (h.hora::time - make_interval(mins => h.margen_antes_min)),
         (h.hora::time + make_interval(mins => h.duracion_min + h.margen_despues_min)),
         'hold'
  from reservas_temporales h
  where h.fecha between p_desde and p_hasta
    and h.expira_en > now();
$$;

grant execute on function jornadas_rango(date, date) to anon, authenticated;
grant execute on function ocupacion_rango(date, date) to anon, authenticated;


-- ============================================================================
-- 2. VALIDACIÓN CENTRAL DE UN HORARIO
-- Devuelve NULL si el slot es válido, o un código de error legible.
-- La usan crear_reserva() y reprogramar_turno(): una sola definición de
-- "horario válido" para todo el sistema.
-- ============================================================================

create or replace function validar_slot(
  p_fecha date,
  p_hora time,
  p_duracion int,
  p_margen_antes int default 0,
  p_margen_despues int default 0,
  p_ignorar_anticipacion boolean default false,
  p_excluir_turno bigint default null
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  cfg          negocio_config%rowtype;
  v_ahora      timestamp;
  v_inicio     timestamp;
  v_fin        timestamp;
  v_rango      tsrange;
  v_cabe       boolean;
begin
  select * into cfg from negocio_config limit 1;

  v_ahora  := now() at time zone cfg.zona_horaria;
  v_inicio := p_fecha + p_hora;
  v_fin    := v_inicio + make_interval(mins => p_duracion);
  v_rango  := tsrange(
                v_inicio - make_interval(mins => p_margen_antes),
                v_fin    + make_interval(mins => p_margen_despues),
                '[)');

  if p_duracion is null or p_duracion <= 0 then
    return 'DURACION_INVALIDA';
  end if;

  -- Anticipación mínima y máxima
  if not p_ignorar_anticipacion then
    if v_inicio < v_ahora + make_interval(mins => cfg.anticipacion_min_min) then
      return 'ANTICIPACION_MINIMA';
    end if;
    if p_fecha > (v_ahora::date + cfg.anticipacion_max_dias) then
      return 'FUERA_DE_RANGO';
    end if;
  elsif v_inicio < v_ahora - interval '1 day' then
    return 'FECHA_PASADA';
  end if;

  -- ¿El bloque completo entra dentro de alguna jornada laboral del día?
  select exists (
    select 1
    from jornadas_rango(p_fecha, p_fecha) j
    where (v_inicio - make_interval(mins => p_margen_antes))::time >= j.hora_inicio
      and (v_fin    + make_interval(mins => p_margen_despues))::time <= j.hora_fin
      and (v_fin + make_interval(mins => p_margen_despues))::date = p_fecha  -- no cruza medianoche
  ) into v_cabe;

  if not v_cabe then
    return 'FUERA_DE_JORNADA';
  end if;

  -- Bloqueos manuales
  if exists (
    select 1 from bloqueos b
    where b.fecha = p_fecha
      and tsrange(p_fecha + b.hora_inicio, p_fecha + b.hora_fin, '[)') && v_rango
  ) then
    return 'HORARIO_BLOQUEADO';
  end if;

  -- Turnos existentes
  if exists (
    select 1 from turnos t
    where t.estado in ('pendiente', 'confirmado', 'en_atencion', 'finalizado')
      and t.rango && v_rango
      and (p_excluir_turno is null or t.id <> p_excluir_turno)
  ) then
    return 'HORARIO_OCUPADO';
  end if;

  -- Reservas temporales de otro cliente
  if exists (
    select 1 from reservas_temporales h
    where h.fecha = p_fecha
      and h.expira_en > now()
      and tsrange(
            p_fecha + h.hora::time - make_interval(mins => h.margen_antes_min),
            p_fecha + h.hora::time + make_interval(mins => h.duracion_min + h.margen_despues_min),
            '[)') && v_rango
  ) then
    return 'HORARIO_RESERVADO_TEMPORALMENTE';
  end if;

  return null;
end;
$$;


-- ============================================================================
-- 3. RESERVA TEMPORAL (hold)
-- El cliente elige un horario → se le aparta N minutos mientras completa
-- sus datos. Si abandona, expira solo.
-- ============================================================================

-- Nota: `p_servicios` viaja como text[] y se compara con `s.id::text`.
-- En tu base `servicios.id` es bigint; en el SUPABASE_SETUP.sql original era
-- text. El cast hace que estas funciones sirvan en los dos casos sin cambios.
create or replace function crear_hold(
  p_fecha date,
  p_hora time,
  p_servicios text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg negocio_config%rowtype;
  v_duracion int;
  v_m_antes int;
  v_m_despues int;
  v_error text;
  v_id uuid;
  v_expira timestamptz;
begin
  perform limpiar_holds_vencidos();
  select * into cfg from negocio_config limit 1;

  select coalesce(sum(s.duracion), 0),
         coalesce(max(coalesce(s.margen_antes_min,  cfg.margen_antes_min)),  cfg.margen_antes_min),
         coalesce(max(coalesce(s.margen_despues_min, cfg.margen_despues_min)), cfg.margen_despues_min)
    into v_duracion, v_m_antes, v_m_despues
  from servicios s
  where s.id::text = any(p_servicios) and s.activo;

  if v_duracion <= 0 then
    return jsonb_build_object('ok', false, 'error', 'SERVICIO_INVALIDO');
  end if;

  v_error := validar_slot(p_fecha, p_hora, v_duracion, v_m_antes, v_m_despues);
  if v_error is not null then
    return jsonb_build_object('ok', false, 'error', v_error);
  end if;

  v_expira := now() + make_interval(mins => cfg.hold_minutos);

  insert into reservas_temporales (fecha, hora, duracion_min, margen_antes_min, margen_despues_min, expira_en)
  values (p_fecha, to_char(p_hora, 'HH24:MI'), v_duracion, v_m_antes, v_m_despues, v_expira)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'hold_id', v_id, 'expira_en', v_expira, 'duracion_min', v_duracion);
end;
$$;

create or replace function liberar_hold(p_hold_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from reservas_temporales where id = p_hold_id;
$$;

grant execute on function crear_hold(date, time, text[]) to anon, authenticated;
grant execute on function liberar_hold(uuid) to anon, authenticated;


-- ============================================================================
-- 4. CREAR RESERVA — atómica, validada en servidor, multi-servicio
-- ============================================================================

create or replace function crear_reserva(
  p_fecha date,
  p_hora time,
  p_nombre text,
  p_telefono text,
  p_servicios text[],
  p_comentario text default null,
  p_hold_id uuid default null,
  p_origen text default 'web'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg          negocio_config%rowtype;
  v_duracion   int;
  v_precio     numeric;
  v_m_antes    int;
  v_m_despues  int;
  v_nombres    text;
  v_error      text;
  v_cliente_id bigint;
  v_turno_id   bigint;
  v_token      uuid;
  v_estado     text;
  v_es_barbero boolean := es_barbero();
  v_ignorar    boolean;
begin
  select * into cfg from negocio_config limit 1;
  perform limpiar_holds_vencidos();

  -- Solo el barbero puede crear una cita "desde el local" salteando la
  -- anticipación mínima; un cliente web nunca puede pedir ese privilegio.
  v_ignorar := v_es_barbero and p_origen in ('local', 'telefono');

  if coalesce(trim(p_nombre), '') = '' or coalesce(trim(p_telefono), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'DATOS_INCOMPLETOS',
      'mensaje', 'Necesitamos tu nombre y tu número de WhatsApp.');
  end if;

  if p_servicios is null or array_length(p_servicios, 1) is null then
    return jsonb_build_object('ok', false, 'error', 'SERVICIO_INVALIDO',
      'mensaje', 'Elegí al menos un servicio.');
  end if;

  -- Suma de duraciones y precios; los márgenes son el máximo entre los
  -- servicios elegidos (no se acumulan: la limpieza se hace una sola vez).
  select coalesce(sum(s.duracion), 0),
         coalesce(sum(s.precio), 0),
         coalesce(max(coalesce(s.margen_antes_min,   cfg.margen_antes_min)),   cfg.margen_antes_min),
         coalesce(max(coalesce(s.margen_despues_min, cfg.margen_despues_min)), cfg.margen_despues_min),
         string_agg(s.nombre, ' + ' order by s.orden, s.nombre)
    into v_duracion, v_precio, v_m_antes, v_m_despues, v_nombres
  from servicios s
  where s.id::text = any(p_servicios) and s.activo;

  if v_duracion <= 0 then
    return jsonb_build_object('ok', false, 'error', 'SERVICIO_INVALIDO',
      'mensaje', 'Alguno de los servicios elegidos ya no está disponible.');
  end if;

  -- Si el cliente tenía el horario apartado, su propio hold no debe
  -- bloquearlo a él mismo.
  if p_hold_id is not null then
    delete from reservas_temporales where id = p_hold_id;
  end if;

  -- Serializa las reservas del mismo día: dos pestañas o dos celulares
  -- entran de a uno. La constraint de exclusión es la garantía final.
  perform pg_advisory_xact_lock(hashtext(p_fecha::text));

  v_error := validar_slot(p_fecha, p_hora, v_duracion, v_m_antes, v_m_despues, v_ignorar);
  if v_error is not null then
    return jsonb_build_object('ok', false, 'error', v_error, 'mensaje', mensaje_error_reserva(v_error));
  end if;

  -- Cliente (alta o actualización del nombre)
  insert into clientes (telefono, nombre)
  values (trim(p_telefono), trim(p_nombre))
  on conflict (negocio_id, telefono) do update set nombre = excluded.nombre
  returning id into v_cliente_id;

  if exists (select 1 from clientes where id = v_cliente_id and bloqueado) then
    return jsonb_build_object('ok', false, 'error', 'CLIENTE_BLOQUEADO',
      'mensaje', 'No podemos tomar la reserva online. Escribinos por WhatsApp.');
  end if;

  v_estado := case when cfg.confirmacion_automatica then 'confirmado' else 'pendiente' end;

  begin
    insert into turnos (
      fecha, hora, cliente_nombre, cliente_telefono, servicio_nombre,
      precio, duracion_min, estado, comentario, origen,
      margen_antes_min, margen_despues_min, cliente_ref_id, cliente_id
    ) values (
      p_fecha, to_char(p_hora, 'HH24:MI'), trim(p_nombre), trim(p_telefono), v_nombres,
      v_precio, v_duracion, v_estado, nullif(trim(coalesce(p_comentario, '')), ''), p_origen,
      v_m_antes, v_m_despues, v_cliente_id, auth.uid()
    )
    returning id, token_seguimiento into v_turno_id, v_token;
  exception
    when exclusion_violation then
      -- Dos personas reservaron el mismo horario en el mismo instante.
      -- Postgres dejó pasar a una sola. Esta es la otra.
      return jsonb_build_object('ok', false, 'error', 'HORARIO_OCUPADO',
        'mensaje', 'Ese horario acaba de ser tomado por otra persona. Elegí otro, por favor.');
  end;

  insert into turno_servicios (turno_id, servicio_id, nombre, precio, duracion_min, orden)
  select v_turno_id, s.id, s.nombre, s.precio, s.duracion, s.orden
  from servicios s
  where s.id::text = any(p_servicios);

  return jsonb_build_object(
    'ok', true,
    'turno_id', v_turno_id,
    'token', v_token,
    'estado', v_estado,
    'fecha', p_fecha,
    'hora', to_char(p_hora, 'HH24:MI'),
    'duracion_min', v_duracion,
    'precio_total', v_precio,
    'servicios', v_nombres
  );
end;
$$;

/** Traduce los códigos de error a algo que el cliente pueda entender. */
create or replace function mensaje_error_reserva(p_codigo text)
returns text
language sql
immutable
as $$
  select case p_codigo
    when 'ANTICIPACION_MINIMA'   then 'Ese horario está demasiado cerca. Elegí uno un poco más tarde.'
    when 'FUERA_DE_RANGO'        then 'Todavía no abrimos la agenda para esa fecha.'
    when 'FECHA_PASADA'          then 'Ese horario ya pasó.'
    when 'FUERA_DE_JORNADA'      then 'No trabajamos en ese horario.'
    when 'HORARIO_BLOQUEADO'     then 'Ese horario no está disponible.'
    when 'HORARIO_OCUPADO'       then 'El horario ya no está disponible.'
    when 'HORARIO_RESERVADO_TEMPORALMENTE' then 'Alguien está reservando ese horario en este momento. Probá con otro.'
    when 'SERVICIO_INVALIDO'     then 'El servicio elegido ya no está disponible.'
    when 'DURACION_INVALIDA'     then 'No pudimos calcular la duración del servicio.'
    else 'No pudimos tomar la reserva. Intentá de nuevo.'
  end;
$$;

grant execute on function crear_reserva(date, time, text, text, text[], text, uuid, text) to anon, authenticated;
grant execute on function mensaje_error_reserva(text) to anon, authenticated;


-- ============================================================================
-- 5. MÁQUINA DE ESTADOS
-- Cada estado sabe a cuáles puede pasar. Se acabó el "cancelar = borrar la
-- fila" (que hoy destruye el historial y hace imposible medir ausencias).
-- ============================================================================

create or replace function transicion_valida(p_desde text, p_hasta text)
returns boolean
language sql
immutable
as $$
  select case p_desde
    when 'pendiente'   then p_hasta in ('confirmado', 'cancelado', 'no_asistio')
    when 'confirmado'  then p_hasta in ('en_atencion', 'finalizado', 'cancelado', 'no_asistio')
    when 'en_atencion' then p_hasta in ('finalizado', 'cancelado')
    when 'finalizado'  then false
    when 'cancelado'   then false
    when 'no_asistio'  then p_hasta in ('finalizado')   -- por si el barbero se equivocó
    else false
  end;
$$;

create or replace function cambiar_estado_turno(
  p_turno_id bigint,
  p_nuevo_estado text,
  p_motivo text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actual text;
begin
  if not es_barbero() then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select estado into v_actual from turnos where id = p_turno_id;
  if v_actual is null then
    return jsonb_build_object('ok', false, 'error', 'TURNO_INEXISTENTE');
  end if;

  if not transicion_valida(v_actual, p_nuevo_estado) then
    return jsonb_build_object('ok', false, 'error', 'TRANSICION_INVALIDA',
      'mensaje', format('No se puede pasar de %s a %s.', v_actual, p_nuevo_estado));
  end if;

  update turnos
  set estado = p_nuevo_estado,
      motivo_cancelacion = case when p_nuevo_estado = 'cancelado' then p_motivo else motivo_cancelacion end,
      cancelado_por = case when p_nuevo_estado = 'cancelado' then 'barbero' else cancelado_por end
  where id = p_turno_id;

  return jsonb_build_object('ok', true, 'estado', p_nuevo_estado);
end;
$$;

grant execute on function cambiar_estado_turno(bigint, text, text) to authenticated;


-- ============================================================================
-- 6. REPROGRAMACIÓN
-- Valida el horario nuevo con las mismas reglas, deja rastro del turno
-- anterior y libera el horario viejo en la misma transacción.
-- ============================================================================

create or replace function reprogramar_turno(
  p_turno_id bigint,
  p_fecha date,
  p_hora time
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  t turnos%rowtype;
  v_error text;
begin
  select * into t from turnos where id = p_turno_id;
  if t.id is null then
    return jsonb_build_object('ok', false, 'error', 'TURNO_INEXISTENTE');
  end if;

  if not (es_barbero() or (t.cliente_id is not null and t.cliente_id = auth.uid())) then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  if t.estado not in ('pendiente', 'confirmado') then
    return jsonb_build_object('ok', false, 'error', 'ESTADO_NO_REPROGRAMABLE');
  end if;

  perform pg_advisory_xact_lock(hashtext(p_fecha::text));

  v_error := validar_slot(p_fecha, p_hora, t.duracion_min, t.margen_antes_min, t.margen_despues_min,
                          es_barbero(), p_turno_id);
  if v_error is not null then
    return jsonb_build_object('ok', false, 'error', v_error, 'mensaje', mensaje_error_reserva(v_error));
  end if;

  update turnos
  set fecha = p_fecha,
      hora = to_char(p_hora, 'HH24:MI'),
      estado = case when es_barbero() then estado else 'pendiente' end
  where id = p_turno_id;

  return jsonb_build_object('ok', true, 'fecha', p_fecha, 'hora', to_char(p_hora, 'HH24:MI'));
end;
$$;

grant execute on function reprogramar_turno(bigint, date, time) to anon, authenticated;


-- ============================================================================
-- 7. SEGUIMIENTO Y CANCELACIÓN DEL CLIENTE INVITADO (sin cuenta)
-- El token va en el link/localStorage. Reemplaza al truco actual de buscar
-- el turno por fecha+hora+teléfono (que, además, hoy funciona para
-- cualquiera que adivine un teléfono).
-- ============================================================================

create or replace function turno_por_token(p_token uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'turno_id', t.id,
    'fecha', t.fecha,
    'hora', t.hora,
    'estado', t.estado,
    'servicios', t.servicio_nombre,
    'duracion_min', t.duracion_min,
    'precio', t.precio,
    'puede_cancelar', (
      t.estado in ('pendiente', 'confirmado')
      and (t.fecha + t.hora::time) - make_interval(hours => c.limite_cancelacion_horas)
          > (now() at time zone c.zona_horaria)
    )
  )
  from turnos t cross join negocio_config c
  where t.token_seguimiento = p_token;
$$;

create or replace function cancelar_turno_cliente(p_token uuid, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  t turnos%rowtype;
  cfg negocio_config%rowtype;
begin
  select * into cfg from negocio_config limit 1;
  select * into t from turnos where token_seguimiento = p_token;

  if t.id is null then
    return jsonb_build_object('ok', false, 'error', 'TURNO_INEXISTENTE');
  end if;
  if t.estado not in ('pendiente', 'confirmado') then
    return jsonb_build_object('ok', false, 'error', 'ESTADO_NO_CANCELABLE');
  end if;
  if (t.fecha + t.hora::time) - make_interval(hours => cfg.limite_cancelacion_horas)
     <= (now() at time zone cfg.zona_horaria) then
    return jsonb_build_object('ok', false, 'error', 'FUERA_DE_PLAZO',
      'mensaje', format('Las cancelaciones online se aceptan hasta %s horas antes. Escribinos por WhatsApp.',
                        cfg.limite_cancelacion_horas));
  end if;

  update turnos
  set estado = 'cancelado', cancelado_por = 'cliente', motivo_cancelacion = p_motivo
  where id = t.id;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function turno_por_token(uuid) to anon, authenticated;
grant execute on function cancelar_turno_cliente(uuid, text) to anon, authenticated;


-- ============================================================================
-- 8. VISTAS DE APOYO PARA EL PANEL
-- ============================================================================

create or replace view v_agenda_dia as
select t.id, t.fecha, t.hora, t.estado, t.duracion_min, t.precio,
       t.cliente_nombre, t.cliente_telefono, t.servicio_nombre, t.comentario, t.origen,
       t.token_seguimiento,
       lower(t.rango)::time as bloque_inicio,
       upper(t.rango)::time as bloque_fin,
       c.total_faltas, c.total_turnos, c.bloqueado as cliente_bloqueado
from turnos t
left join clientes c on c.id = t.cliente_ref_id;

-- La vista hereda el RLS de `turnos`: el público sigue sin poder leerla.
alter view v_agenda_dia set (security_invoker = on);


-- ============================================================================
-- 9. PRUEBA RÁPIDA (correr en el SQL Editor después de instalar)
-- ============================================================================
--   select * from jornadas_rango(current_date, current_date + 7);
--   select * from ocupacion_rango(current_date, current_date + 7);
--   select validar_slot(current_date + 1, time '09:00', 30);   -- null = válido
--   select crear_reserva(current_date + 1, time '09:00', 'Prueba', '0981000000',
--                        array['corte']);
--   -- repetir la MISMA llamada: la segunda debe devolver HORARIO_OCUPADO
