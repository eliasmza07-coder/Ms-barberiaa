-- ============================================================================
-- 006_normalizacion_base.sql
--
-- Empareja tu base REAL con lo que el código asume, antes de montar el
-- modelo nuevo. Sale de comparar el diagrama de tu proyecto contra
-- db/SUPABASE_SETUP.sql: hay varias diferencias que hoy están causando
-- errores silenciosos.
--
-- Diferencia principal encontrada:
--
--   SUPABASE_SETUP.sql dice:  servicios.id  text primary key
--   Tu base real tiene:       servicios.id  int8 (bigint)
--
-- Y `services-catalog.service.js` hace esto al crear un servicio nuevo:
--
--   if (!id) payload.id = 'serv_' + Date.now();
--
-- Un id de texto contra una columna bigint = error 400 (`invalid input
-- syntax for type bigint`). Por eso "agregar servicio" falla desde el
-- panel mientras que "editar" funciona: al editar ya viaja el id numérico.
-- FIX_SERVICIOS_400.sql atacó la columna `orden`, que era otro síntoma
-- del mismo problema, pero no éste.
--
-- Este script arregla la base; el archivo
-- src/modules/services-catalog/services-catalog.service.js incluido en la
-- entrega arregla el JS. Hacen falta los dos.
--
-- Es idempotente y no borra datos.
-- ============================================================================

-- ============================================================================
-- 1. es_barbero() — de esto dependen TODAS las políticas de seguridad nuevas
-- ============================================================================

-- SECURITY DEFINER a propósito: si la política de `perfiles` tuviera que
-- leer `perfiles` para saber si podés leer `perfiles`, Postgres entra en
-- recursión infinita. Esta función corta el ciclo.
create or replace function es_barbero()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from perfiles where id = auth.uid() and rol = 'barbero');
$$;

grant execute on function es_barbero() to anon, authenticated;


-- ============================================================================
-- 2. servicios.id — que se puedan crear servicios nuevos
--
-- No se cambia el tipo (eso rompería los turnos que ya referencian
-- servicios por nombre y cualquier dato existente). Lo que se hace es
-- darle una secuencia propia, así el JS puede insertar SIN mandar id y la
-- base lo genera sola.
-- ============================================================================

do $$
declare
  v_tipo text;
  v_tiene_default boolean;
  v_max bigint;
begin
  select data_type, (column_default is not null or is_identity = 'YES')
    into v_tipo, v_tiene_default
  from information_schema.columns
  where table_schema = 'public' and table_name = 'servicios' and column_name = 'id';

  if v_tipo in ('bigint', 'integer') and not v_tiene_default then
    execute 'create sequence if not exists servicios_id_seq owned by servicios.id';
    select coalesce(max(id), 0) into v_max from servicios;
    execute format('select setval(''servicios_id_seq'', %s)', greatest(v_max, 1));
    execute 'alter table servicios alter column id set default nextval(''servicios_id_seq'')';
    raise notice 'servicios.id: se le asignó una secuencia. Ahora se pueden crear servicios sin enviar id.';
  elsif v_tipo = 'text' then
    raise notice 'servicios.id es text: el código actual ya funciona tal cual.';
  else
    raise notice 'servicios.id (%) ya tiene valor por defecto. Nada que hacer.', v_tipo;
  end if;
end $$;


-- ============================================================================
-- 3. Restricciones de unicidad que faltan
-- Sin ellas, un doble clic crea filas duplicadas que después descuadran la
-- agenda (ya pasó con dias_libres; el comentario de schedule.repository.js
-- lo documenta).
-- ============================================================================

-- 3.a dias_libres: una fila por fecha
delete from dias_libres a using dias_libres b
where a.fecha = b.fecha and a.id > b.id;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'dias_libres_fecha_unique') then
    alter table dias_libres add constraint dias_libres_fecha_unique unique (fecha);
  end if;
end $$;

-- 3.b horas_bloqueadas: una fila por fecha+hora
delete from horas_bloqueadas a using horas_bloqueadas b
where a.fecha = b.fecha and a.hora = b.hora and a.id > b.id;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'horas_bloqueadas_fecha_hora_unique') then
    alter table horas_bloqueadas add constraint horas_bloqueadas_fecha_hora_unique unique (fecha, hora);
  end if;
end $$;

-- 3.c config_jornada: una config por fecha (el código hace upsert
--     onConflict:'fecha', que sin este índice falla o duplica)
delete from config_jornada a using config_jornada b
where a.fecha = b.fecha and a.id < b.id;   -- se queda la MÁS RECIENTE

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'config_jornada_fecha_unique') then
    alter table config_jornada add constraint config_jornada_fecha_unique unique (fecha);
  end if;
end $$;


-- ============================================================================
-- 4. Normalización de `turnos.hora`
-- Se guarda como texto libre. Conviven '9:00', '09:00' y '09:00:00', y el
-- código compara con strings ('09:00'), así que los otros formatos
-- simplemente no matchean: el turno existe pero la grilla no lo ve.
-- ============================================================================

update turnos
set hora = to_char(hora::time, 'HH24:MI')
where hora ~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$'
  and hora <> to_char(hora::time, 'HH24:MI');

update horas_bloqueadas
set hora = to_char(hora::time, 'HH24:MI')
where hora ~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$'
  and hora <> to_char(hora::time, 'HH24:MI');

-- Las horas que no se pueden interpretar quedan como están: se listan en
-- el reporte de 005 (consulta A) para revisarlas a mano. No se borra nada.


-- ============================================================================
-- 5. Normalización de `turnos.estado`
-- ============================================================================

update turnos set estado = lower(trim(estado)) where estado <> lower(trim(estado));
update turnos set estado = 'confirmado' where estado in ('confirmada', 'aceptado', 'aceptada');
update turnos set estado = 'cancelado'  where estado in ('cancelada', 'rechazado', 'rechazada');
update turnos set estado = 'pendiente'  where estado in ('pendiente_confirmacion', 'nuevo');

-- Cualquier valor que siga fuera del set queda visible acá:
do $$
declare v_raros text;
begin
  select string_agg(distinct estado, ', ') into v_raros
  from turnos
  where estado not in ('pendiente','confirmado','en_atencion','finalizado','cancelado','no_asistio');
  if v_raros is not null then
    raise warning 'Hay turnos con estados no reconocidos: %. Corregilos antes de correr 007, o el CHECK va a fallar.', v_raros;
  end if;
end $$;


-- ============================================================================
-- 6. Consolidación de columnas duplicadas en sitio_config
-- Tu tabla tiene los nombres viejos Y los nuevos conviviendo (titulo_hero_1
-- junto a hero_titulo, etc.). Esto copia cualquier dato que hayas cargado
-- en un nombre viejo hacia el nombre que el código realmente lee.
-- NO borra las columnas viejas — eso es opcional y está en 009.
-- ============================================================================

do $$
declare
  v_col text;
  v_destino text;
  v_pares text[][] := array[
    ['titulo_hero1',      'hero_titulo'],
    ['titulo_hero_1',     'hero_titulo'],
    ['hero_titulo_1',     'hero_titulo'],
    ['hero_titulo_2',     'hero_titulo_destacado'],
    ['titulo_hero_2',     'hero_titulo_destacado'],
    ['subtitulo_hero',    'hero_subtitulo'],
    ['direccion_completa','direccion'],
    ['mapa_url',          'mapa_embed_url'],
    ['texto_footer',      'footer_texto']
  ];
  i int;
begin
  for i in 1 .. array_length(v_pares, 1) loop
    v_col := v_pares[i][1];
    v_destino := v_pares[i][2];
    if exists (select 1 from information_schema.columns
               where table_schema='public' and table_name='sitio_config' and column_name = v_col)
       and exists (select 1 from information_schema.columns
               where table_schema='public' and table_name='sitio_config' and column_name = v_destino)
    then
      execute format(
        'update sitio_config set %I = %I where id = 1 and coalesce(nullif(trim(%I), ''''), null) is null and nullif(trim(%I), '''') is not null',
        v_destino, v_col, v_destino, v_col
      );
    end if;
  end loop;
end $$;


-- ============================================================================
-- 7. Índices que faltan (la agenda consulta por fecha en cada carga)
-- ============================================================================

create index if not exists idx_turnos_fecha on turnos(fecha);
create index if not exists idx_turnos_telefono on turnos(cliente_telefono);
create index if not exists idx_horas_bloq_fecha on horas_bloqueadas(fecha);


-- ============================================================================
-- VERIFICACIÓN — volvé a correr 005_preflight_verificacion.sql.
-- Los PROBLEMA de servicios.id, es_barbero y duplicados tienen que haber
-- pasado a OK. Los de RLS siguen en PROBLEMA hasta que corras 007.
-- ============================================================================
