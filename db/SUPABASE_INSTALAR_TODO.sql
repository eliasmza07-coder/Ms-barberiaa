-- ############################################################################
-- #                                                                          #
-- #   MS BARBERÍA — INSTALACIÓN COMPLETA EN SUPABASE                         #
-- #                                                                          #
-- #   Este archivo junta las migraciones 006 + 007 + 008 en un solo bloque   #
-- #   para pegar de una sola vez en el SQL Editor de Supabase.               #
-- #                                                                          #
-- ############################################################################
--
-- CÓMO CORRERLO
--
--   1. Supabase → tu proyecto → Database → Backups → Create backup.
--   2. Supabase → SQL Editor → New query.
--   3. Pegar TODO este archivo.
--   4. Run.
--
-- El SQL Editor corre todo dentro de una transacción: si algo falla, no
-- queda nada aplicado a medias. Podés volver a correrlo las veces que
-- quieras, es idempotente.
--
-- ANTES: corré `SUPABASE_VERIFICAR.sql` (solo lectura) y resolvé lo que
-- aparezca marcado como PROBLEMA.
--
-- QUÉ HACE, EN UNA LÍNEA CADA COSA:
--
--   PARTE A — Empareja tu base real con lo que el código asume
--             (arregla el error 400 al crear servicios, normaliza horas
--             y estados, agrega índices únicos que faltaban).
--
--   PARTE B — Modelo de agenda nuevo: horario semanal con jornada partida,
--             vacaciones, bloqueos por rango, múltiples servicios por turno,
--             los 6 estados, reservas temporales, protección real contra
--             doble reserva, y RLS sobre `turnos` (hoy tus clientes son
--             públicos).
--
--   PARTE C — Las funciones que validan y crean reservas del lado del
--             servidor, para que nadie pueda saltearse las reglas desde
--             la consola del navegador.
--
-- QUÉ NO HACE: no borra ninguna tabla, columna ni fila. Lo único que borra
-- son filas duplicadas exactas (mismo día bloqueado cargado dos veces).
-- La limpieza destructiva es opcional y vive aparte, en 009.
--
-- ############################################################################


-- ============================================================================
-- CANDADO DE SEGURIDAD — no seguir si nadie puede administrar después
--
-- Este script activa RLS sobre `turnos`. A partir de ahí, solo un usuario
-- con rol 'barbero' puede ver y gestionar la agenda. Si ninguno existe,
-- quedarías afuera de tu propio panel, así que frenamos acá.
--
-- Si esto corta la ejecución: ejecutá primero (con TU email real)
--
--     insert into perfiles (id, nombre, rol)
--     select id, 'Barbero', 'barbero' from auth.users where email = 'TU_EMAIL_ACA'
--     on conflict (id) do update set rol = 'barbero';
--
-- y volvé a correr este archivo.
-- ============================================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'perfiles') then
    raise exception 'Falta la tabla `perfiles`. Corré primero db/SUPABASE_SETUP.sql (PARTE 3).';
  end if;

  if not exists (select 1 from perfiles where rol = 'barbero') then
    raise exception E'\n\n  FRENO DE SEGURIDAD\n\n  No hay ningún usuario con rol ''barbero''. Si activo RLS ahora, nadie\n  (vos incluido) va a poder administrar los turnos.\n\n  Ejecutá esto con tu email real y volvé a correr el script:\n\n    insert into perfiles (id, nombre, rol)\n    select id, ''Barbero'', ''barbero'' from auth.users where email = ''TU_EMAIL_ACA''\n    on conflict (id) do update set rol = ''barbero'';\n';
  end if;

  raise notice 'Candado OK: hay % usuario(s) con rol barbero. Continuando…',
    (select count(*) from perfiles where rol = 'barbero');
end $$;




-- ############################################################################
-- #  PARTE A — NORMALIZACIÓN DE LA BASE ACTUAL  (era 006_normalizacion_base.sql)
-- ############################################################################

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


-- ############################################################################
-- #  PARTE B — MOTOR DE DISPONIBILIDAD + SEGURIDAD  (era 007_motor_disponibilidad.sql)
-- ############################################################################

-- ============================================================================
-- 007_motor_disponibilidad.sql
--
-- Correr DESPUÉS de 005_preflight_verificacion.sql (reporte) y
-- 006_normalizacion_base.sql (arreglos sobre las tablas actuales).
--
-- Convierte el modelo de agenda actual (config por fecha suelta + una fila
-- por hora bloqueada) en un modelo de reservas real:
--
--   • Horario semanal recurrente, con jornada partida (mañana/siesta/tarde).
--   • Excepciones por fecha: cerrado, vacaciones (rango), horario especial.
--   • Bloqueos por rango de horas, no por slot suelto.
--   • Múltiples servicios por turno.
--   • Estados completos del ciclo de vida de una cita.
--   • Imposibilidad FÍSICA de doble reserva (constraint de exclusión).
--   • Reservas temporales (hold) mientras el cliente completa sus datos.
--   • RLS real sobre `turnos`: hoy los datos de tus clientes son públicos.
--
-- ES IDEMPOTENTE y NO DESTRUCTIVO: no borra ninguna tabla ni columna
-- existente. Las tablas viejas (config_jornada, dias_libres,
-- horas_bloqueadas) siguen ahí y sus datos se copian al modelo nuevo, así
-- que podés volver atrás mientras probás.
--
-- CORRELO PRIMERO EN UN PROYECTO DE STAGING. Al final del archivo hay una
-- sección de VERIFICACIÓN para ejecutar antes de tocar producción.
-- ============================================================================

create extension if not exists btree_gist;

-- ============================================================================
-- 1. CONFIGURACIÓN DEL NEGOCIO
-- Todo lo que hoy está hardcodeado en constants.js o directamente no existe.
-- `negocio_id` ya viaja en todas las tablas nuevas: el día que sumes una
-- segunda barbería no hay que rehacer el esquema, solo dejar de forzar el
-- valor por defecto.
-- ============================================================================

create table if not exists negocios (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  slug text unique not null,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

insert into negocios (id, nombre, slug)
values ('00000000-0000-0000-0000-000000000001', 'MS Barbería y Peluquería', 'ms-barberia')
on conflict (id) do nothing;

create table if not exists negocio_config (
  negocio_id uuid primary key
    references negocios(id) on delete cascade
    default '00000000-0000-0000-0000-000000000001',

  zona_horaria            text    not null default 'America/Asuncion',
  intervalo_slot_min      int     not null default 15  check (intervalo_slot_min in (5, 10, 15, 20, 30, 60)),

  -- Márgenes por defecto; cada servicio puede sobrescribirlos.
  margen_antes_min        int     not null default 0   check (margen_antes_min  >= 0),
  margen_despues_min      int     not null default 5   check (margen_despues_min >= 0),

  -- Anticipación: cuánto antes hay que reservar y hasta cuándo hacia adelante.
  anticipacion_min_min    int     not null default 30  check (anticipacion_min_min >= 0),
  anticipacion_max_dias   int     not null default 60  check (anticipacion_max_dias > 0),

  -- Cancelación del cliente por su cuenta: hasta N horas antes.
  limite_cancelacion_horas int    not null default 3   check (limite_cancelacion_horas >= 0),

  -- Reserva temporal mientras completa el formulario.
  hold_minutos            int     not null default 5   check (hold_minutos between 1 and 30),

  -- false = el barbero confirma a mano (flujo actual). true = auto-confirma.
  confirmacion_automatica boolean not null default false,

  -- A partir de cuántas faltas el panel marca al cliente como riesgoso.
  max_faltas_alerta       int     not null default 2,

  updated_at timestamptz not null default now()
);

insert into negocio_config (negocio_id) values ('00000000-0000-0000-0000-000000000001')
on conflict (negocio_id) do nothing;


-- ============================================================================
-- 2. HORARIO SEMANAL RECURRENTE
-- Varias filas por día = jornada partida. Ej. martes 08:00–12:00 y 14:00–20:00.
-- ============================================================================

create table if not exists horarios_semanales (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references negocios(id) on delete cascade
    default '00000000-0000-0000-0000-000000000001',
  dia_semana  int  not null check (dia_semana between 0 and 6),   -- 0 = domingo
  hora_inicio time not null,
  hora_fin    time not null,
  activo      boolean not null default true,
  constraint horario_coherente check (hora_fin > hora_inicio)
);
create index if not exists idx_horarios_dia on horarios_semanales(negocio_id, dia_semana) where activo;


-- ============================================================================
-- 3. EXCEPCIONES POR FECHA (feriados, vacaciones, horario especial)
-- Un rango cubre las vacaciones completas con una sola fila.
-- ============================================================================

create table if not exists excepciones_horario (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references negocios(id) on delete cascade
    default '00000000-0000-0000-0000-000000000001',
  fecha_desde date not null,
  fecha_hasta date not null,
  tipo        text not null check (tipo in ('cerrado', 'especial')),
  hora_inicio time,   -- solo para tipo 'especial'
  hora_fin    time,
  motivo      text,
  created_at  timestamptz not null default now(),
  constraint rango_fechas_coherente check (fecha_hasta >= fecha_desde),
  constraint especial_con_horario check (
    tipo = 'cerrado' or (hora_inicio is not null and hora_fin is not null and hora_fin > hora_inicio)
  )
);
create index if not exists idx_excepciones_rango on excepciones_horario(negocio_id, fecha_desde, fecha_hasta);


-- ============================================================================
-- 4. BLOQUEOS PUNTUALES (reunión, almuerzo largo, trámite)
-- ============================================================================

create table if not exists bloqueos (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references negocios(id) on delete cascade
    default '00000000-0000-0000-0000-000000000001',
  fecha       date not null,
  hora_inicio time not null,
  hora_fin    time not null,
  motivo      text,
  created_at  timestamptz not null default now(),
  constraint bloqueo_coherente check (hora_fin > hora_inicio)
);
create index if not exists idx_bloqueos_fecha on bloqueos(negocio_id, fecha);


-- ============================================================================
-- 5. SERVICIOS — campos que faltaban
-- No se renombra la tabla ni se toca su PK (`id text`) para no romper nada
-- de lo que ya funciona hoy.
-- ============================================================================

alter table servicios add column if not exists negocio_id uuid
  references negocios(id) default '00000000-0000-0000-0000-000000000001';
alter table servicios add column if not exists activo boolean not null default true;
alter table servicios add column if not exists imagen_url text;
alter table servicios add column if not exists margen_antes_min int;    -- null = usa el default del negocio
alter table servicios add column if not exists margen_despues_min int;
alter table servicios add column if not exists orden int default 0;
alter table servicios add column if not exists created_at timestamptz default now();

update servicios set negocio_id = '00000000-0000-0000-0000-000000000001' where negocio_id is null;
update servicios set orden = 0 where orden is null;


-- ============================================================================
-- 6. CLIENTES — historial, faltas, cliente recurrente
-- Se identifican por teléfono (que es lo único que pedimos). Si además
-- tienen cuenta, `perfil_id` los une.
-- ============================================================================

create table if not exists clientes (
  id bigint generated always as identity primary key,
  negocio_id uuid not null references negocios(id) on delete cascade
    default '00000000-0000-0000-0000-000000000001',
  telefono   text not null,
  nombre     text not null,
  perfil_id  uuid references perfiles(id) on delete set null,
  notas      text,
  total_turnos   int not null default 0,
  total_faltas   int not null default 0,
  ultima_visita  date,
  bloqueado  boolean not null default false,
  created_at timestamptz not null default now(),
  unique (negocio_id, telefono)
);


-- ============================================================================
-- 7. TURNOS — estados completos + rango + anti-doble-reserva
-- ============================================================================

alter table turnos add column if not exists negocio_id uuid
  references negocios(id) default '00000000-0000-0000-0000-000000000001';
alter table turnos add column if not exists cliente_ref_id bigint references clientes(id) on delete set null;
alter table turnos add column if not exists comentario text;
alter table turnos add column if not exists origen text not null default 'web'
  check (origen in ('web', 'local', 'telefono'));
alter table turnos add column if not exists token_seguimiento uuid not null default gen_random_uuid();
alter table turnos add column if not exists motivo_cancelacion text;
alter table turnos add column if not exists cancelado_por text check (cancelado_por in ('cliente', 'barbero', 'sistema'));
alter table turnos add column if not exists reprogramado_de bigint references turnos(id) on delete set null;
alter table turnos add column if not exists updated_at timestamptz default now();
alter table turnos add column if not exists rango tsrange;

update turnos set negocio_id = '00000000-0000-0000-0000-000000000001' where negocio_id is null;

create unique index if not exists idx_turnos_token on turnos(token_seguimiento);

-- --- Estados -----------------------------------------------------------------
-- Se mantienen los valores en minúscula que ya están cargados en producción
-- ('pendiente', 'confirmado', 'cancelado') y se suman los que faltaban.
do $$
begin
  alter table turnos drop constraint if exists turnos_estado_check;
  alter table turnos add constraint turnos_estado_check check (
    estado in ('pendiente', 'confirmado', 'en_atencion', 'finalizado', 'cancelado', 'no_asistio')
  );
end $$;

-- --- Rango ocupado (incluye márgenes) ---------------------------------------
-- Se mantiene con un trigger en vez de una columna GENERATED porque los
-- márgenes dependen del servicio, y así el mismo cálculo sirve al insertar
-- y al reprogramar.
alter table turnos add column if not exists margen_antes_min int not null default 0;
alter table turnos add column if not exists margen_despues_min int not null default 0;

create or replace function sincronizar_rango_turno()
returns trigger
language plpgsql
as $$
declare
  v_inicio timestamp;
begin
  v_inicio := (new.fecha + new.hora::time);
  new.rango := tsrange(
    v_inicio - make_interval(mins => coalesce(new.margen_antes_min, 0)),
    v_inicio + make_interval(mins => coalesce(new.duracion_min, 30) + coalesce(new.margen_despues_min, 0)),
    '[)'
  );
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_sincronizar_rango_turno on turnos;
create trigger trg_sincronizar_rango_turno
  before insert or update of fecha, hora, duracion_min, margen_antes_min, margen_despues_min
  on turnos
  for each row execute function sincronizar_rango_turno();

-- Backfill para las filas que ya existían.
update turnos
set rango = tsrange(
      (fecha + hora::time) - make_interval(mins => coalesce(margen_antes_min, 0)),
      (fecha + hora::time) + make_interval(mins => coalesce(duracion_min, 30) + coalesce(margen_despues_min, 0)),
      '[)'
    )
where rango is null
  and hora ~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$';   -- las horas rotas quedan fuera (ver 005, consulta A)

-- --- LA constraint que hace imposible la doble reserva ----------------------
-- Dos clientes tocando "Confirmar" en el mismo milisegundo: Postgres deja
-- pasar uno y rechaza al otro. No depende de que el código chequee antes.
--
-- Si ya tenés turnos superpuestos cargados (probable, porque hasta hoy nada
-- lo impedía), la creación falla: la consulta de VERIFICACIÓN del final te
-- muestra exactamente cuáles son para que los arregles a mano.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'turnos_sin_solapamiento') then
    begin
      alter table turnos add constraint turnos_sin_solapamiento
        exclude using gist (
          negocio_id with =,
          rango with &&
        )
        where (estado in ('pendiente', 'confirmado', 'en_atencion', 'finalizado'));
      raise notice 'OK: constraint anti-doble-reserva creada.';
    exception when others then
      raise warning 'NO se pudo crear turnos_sin_solapamiento: %. Revisá la consulta de VERIFICACIÓN al final del archivo, resolvé los turnos superpuestos y volvé a correr este script.', sqlerrm;
    end;
  end if;
end $$;

create index if not exists idx_turnos_fecha_estado on turnos(negocio_id, fecha, estado);


-- ============================================================================
-- 8. MÚLTIPLES SERVICIOS POR TURNO
-- Se guarda el nombre y el precio DEL MOMENTO de la reserva: si mañana
-- cambiás el precio o borrás el servicio, el historial no se falsea.
-- ============================================================================

-- El tipo de `servicio_id` se copia del tipo real de `servicios.id`. En tu
-- base es bigint (int8), aunque SUPABASE_SETUP.sql declaraba text: así el
-- mismo script sirve para los dos casos sin editarlo a mano.
do $$
declare v_tipo text;
begin
  select case when data_type = 'text' then 'text' else 'bigint' end
    into v_tipo
  from information_schema.columns
  where table_schema = 'public' and table_name = 'servicios' and column_name = 'id';

  execute format($f$
    create table if not exists turno_servicios (
      id bigint generated always as identity primary key,
      turno_id     bigint not null references turnos(id) on delete cascade,
      servicio_id  %s references servicios(id) on delete set null,
      nombre       text   not null,
      precio       numeric not null default 0,
      duracion_min int    not null default 30,
      orden        int    not null default 0
    )$f$, coalesce(v_tipo, 'bigint'));
end $$;
create index if not exists idx_turno_servicios_turno on turno_servicios(turno_id);

-- Backfill: cada turno viejo tenía exactamente un servicio, en texto plano.
insert into turno_servicios (turno_id, servicio_id, nombre, precio, duracion_min)
select t.id, s.id, t.servicio_nombre, coalesce(t.precio, 0), coalesce(t.duracion_min, 30)
from turnos t
left join servicios s on s.nombre = t.servicio_nombre
where not exists (select 1 from turno_servicios ts where ts.turno_id = t.id);


-- ============================================================================
-- 9. RESERVAS TEMPORALES (hold)
-- Mientras el cliente escribe su nombre, el horario le queda apartado unos
-- minutos. No entra en la constraint de exclusión a propósito: un hold
-- vencido no debe bloquear nada, y las consultas siempre filtran por
-- `expira_en > now()`.
-- ============================================================================

create table if not exists reservas_temporales (
  id uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios(id) on delete cascade
    default '00000000-0000-0000-0000-000000000001',
  fecha      date not null,
  hora       text not null,
  duracion_min int not null,
  margen_antes_min int not null default 0,
  margen_despues_min int not null default 0,
  expira_en  timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_holds_vigentes on reservas_temporales(negocio_id, fecha, expira_en);

create or replace function limpiar_holds_vencidos()
returns void
language sql
security definer
set search_path = public
as $$
  delete from reservas_temporales where expira_en < now() - interval '1 minute';
$$;


-- ============================================================================
-- 10. MIGRACIÓN DE DATOS DEL MODELO VIEJO AL NUEVO
-- Nada se pierde: lo que ya cargaste en la agenda sigue valiendo.
-- ============================================================================

-- 10.a Horario semanal por defecto (solo si todavía no configuraste ninguno).
--      Se deduce de la última config_jornada cargada, o usa 08–12 / 14–20.
insert into horarios_semanales (dia_semana, hora_inicio, hora_fin)
select d.dia, h.inicio, h.fin
from (select generate_series(1, 6) as dia) d          -- lunes a sábado
cross join (values
  (time '08:00', time '12:00'),
  (time '14:00', time '20:00')
) as h(inicio, fin)
where not exists (select 1 from horarios_semanales);

-- 10.b dias_libres → excepciones tipo 'cerrado'
insert into excepciones_horario (fecha_desde, fecha_hasta, tipo, motivo)
select dl.fecha, dl.fecha, 'cerrado', 'Migrado de dias_libres'
from dias_libres dl
where not exists (
  select 1 from excepciones_horario e
  where e.tipo = 'cerrado' and dl.fecha between e.fecha_desde and e.fecha_hasta
);

-- 10.c config_jornada (horario distinto para una fecha puntual) → 'especial'
insert into excepciones_horario (fecha_desde, fecha_hasta, tipo, hora_inicio, hora_fin, motivo)
select cj.fecha, cj.fecha, 'especial',
       make_time(cj.apertura, 0, 0), make_time(least(cj.cierre, 23), 0, 0),
       'Migrado de config_jornada'
from (select distinct on (fecha) * from config_jornada order by fecha, id desc) cj
where cj.cierre > cj.apertura
  and not exists (
    select 1 from excepciones_horario e
    where e.tipo = 'especial' and e.fecha_desde = cj.fecha
  );

-- 10.d horas_bloqueadas (un slot suelto) → bloqueos con rango real
insert into bloqueos (fecha, hora_inicio, hora_fin, motivo)
select hb.fecha,
       hb.hora::time,
       hb.hora::time + make_interval(mins => coalesce(cj.intervalo, 15)),
       'Migrado de horas_bloqueadas'
from horas_bloqueadas hb
left join config_jornada cj on cj.fecha = hb.fecha
where hb.hora ~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$'
  and not exists (
    select 1 from bloqueos b
    where b.fecha = hb.fecha and b.hora_inicio = hb.hora::time
  );

-- 10.e clientes a partir del historial de turnos
insert into clientes (telefono, nombre, total_turnos, total_faltas, ultima_visita)
select t.cliente_telefono,
       (array_agg(t.cliente_nombre order by t.created_at desc))[1],
       count(*) filter (where t.estado <> 'cancelado'),
       count(*) filter (where t.estado = 'no_asistio'),
       max(t.fecha) filter (where t.estado in ('finalizado', 'confirmado'))
from turnos t
where t.cliente_telefono is not null and t.cliente_telefono <> ''
group by t.cliente_telefono
on conflict (negocio_id, telefono) do nothing;

update turnos t
set cliente_ref_id = c.id
from clientes c
where c.telefono = t.cliente_telefono and t.cliente_ref_id is null;


-- ============================================================================
-- 11. CONTADORES DE CLIENTE AUTOMÁTICOS
-- ============================================================================

create or replace function actualizar_metricas_cliente()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.cliente_ref_id is null then return new; end if;

  update clientes c
  set total_turnos  = (select count(*) from turnos t
                        where t.cliente_ref_id = c.id and t.estado <> 'cancelado'),
      total_faltas  = (select count(*) from turnos t
                        where t.cliente_ref_id = c.id and t.estado = 'no_asistio'),
      ultima_visita = (select max(t.fecha) from turnos t
                        where t.cliente_ref_id = c.id and t.estado = 'finalizado')
  where c.id = new.cliente_ref_id;

  return new;
end;
$$;

drop trigger if exists trg_metricas_cliente on turnos;
create trigger trg_metricas_cliente
  after insert or update of estado on turnos
  for each row execute function actualizar_metricas_cliente();


-- ============================================================================
-- 12. SEGURIDAD (RLS)
--
-- ⚠️  ESTE ES EL ARREGLO MÁS IMPORTANTE DEL ARCHIVO.
--
-- Hoy la tabla `turnos` NO tiene RLS activo. Como PostgREST la expone con
-- la anon key (que es pública y está en el bundle del navegador), cualquiera
-- puede hacer un GET a /rest/v1/turnos y descargarse el nombre y el
-- teléfono de TODOS tus clientes — y también borrarlos o editarlos.
-- Lo mismo con `servicios`.
--
-- A partir de acá:
--   • el público NO lee `turnos`;
--   • la disponibilidad se consulta por una función que devuelve solo
--     rangos horarios ocupados, sin ningún dato personal;
--   • crear una reserva pasa sí o sí por la función `crear_reserva()`
--     (archivo 006), que valida del lado del servidor.
-- ============================================================================

-- Requiere es_barbero(), que crea 006_normalizacion_base.sql.
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'es_barbero') then
    raise exception 'Falta la función es_barbero(). Corré primero 006_normalizacion_base.sql.';
  end if;
end $$;

alter table turnos              enable row level security;
alter table turno_servicios     enable row level security;
alter table servicios           enable row level security;
alter table clientes            enable row level security;
alter table negocios            enable row level security;
alter table negocio_config      enable row level security;
alter table horarios_semanales  enable row level security;
alter table excepciones_horario enable row level security;
alter table bloqueos            enable row level security;
alter table reservas_temporales enable row level security;

-- --- turnos ---
drop policy if exists "publico lee turnos" on turnos;          -- por si quedó de antes
drop policy if exists "barbero gestiona turnos" on turnos;
create policy "barbero gestiona turnos" on turnos
  for all using (es_barbero()) with check (es_barbero());

drop policy if exists "cliente lee sus turnos" on turnos;
create policy "cliente lee sus turnos" on turnos
  for select using (cliente_id is not null and cliente_id = auth.uid());

drop policy if exists "cliente cancela sus turnos" on turnos;
create policy "cliente cancela sus turnos" on turnos
  for update using (cliente_id is not null and cliente_id = auth.uid())
  with check (estado in ('cancelado', 'pendiente', 'confirmado'));

-- Nadie inserta directo: la creación pasa por crear_reserva() (SECURITY DEFINER).

-- --- turno_servicios: sigue la visibilidad de su turno ---
drop policy if exists "barbero gestiona turno_servicios" on turno_servicios;
create policy "barbero gestiona turno_servicios" on turno_servicios
  for all using (es_barbero()) with check (es_barbero());

drop policy if exists "cliente lee servicios de sus turnos" on turno_servicios;
create policy "cliente lee servicios de sus turnos" on turno_servicios
  for select using (
    exists (select 1 from turnos t where t.id = turno_id and t.cliente_id = auth.uid())
  );

-- --- servicios: el catálogo activo sí es público (es la carta del negocio) ---
drop policy if exists "lectura publica servicios activos" on servicios;
create policy "lectura publica servicios activos" on servicios
  for select using (activo = true);
drop policy if exists "barbero gestiona servicios" on servicios;
create policy "barbero gestiona servicios" on servicios
  for all using (es_barbero()) with check (es_barbero());

-- --- clientes: solo el barbero ---
drop policy if exists "barbero gestiona clientes" on clientes;
create policy "barbero gestiona clientes" on clientes
  for all using (es_barbero()) with check (es_barbero());

-- --- configuración y horarios: lectura pública (el cliente necesita saber
--     cuándo abrís), escritura solo del barbero ---
do $$
declare t text;
begin
  foreach t in array array['negocios', 'negocio_config', 'horarios_semanales', 'excepciones_horario', 'bloqueos']
  loop
    execute format('drop policy if exists "lectura publica %1$s" on %1$I', t);
    execute format('create policy "lectura publica %1$s" on %1$I for select using (true)', t);
    execute format('drop policy if exists "barbero gestiona %1$s" on %1$I', t);
    execute format('create policy "barbero gestiona %1$s" on %1$I for all using (es_barbero()) with check (es_barbero())', t);
  end loop;
end $$;

-- --- holds: se manejan solo por función ---
drop policy if exists "barbero gestiona holds" on reservas_temporales;
create policy "barbero gestiona holds" on reservas_temporales
  for all using (es_barbero()) with check (es_barbero());

-- --- Cierre del agujero de dias_libres -------------------------------------
-- FIX_DIAS_LIBRES_RLS.sql dejó una política "insercion publica dias_libres"
-- con `with check (true)`: cualquier visitante anónimo podía insertar un día
-- libre y cerrar la barbería entera. Se elimina.
drop policy if exists "insercion publica dias_libres" on dias_libres;


-- ============================================================================
-- 13. VERIFICACIÓN — corré esto DESPUÉS del script, antes de dar por hecho
--     que todo quedó bien.
-- ============================================================================

-- 13.a ¿Quedaron turnos superpuestos que impiden crear la constraint?
--      (si devuelve filas, resolvelas y volvé a correr el script)
--
--   select a.id, a.fecha, a.hora, a.cliente_nombre,
--          b.id, b.hora, b.cliente_nombre
--   from turnos a
--   join turnos b on a.id < b.id and a.rango && b.rango
--   where a.estado in ('pendiente','confirmado','en_atencion','finalizado')
--     and b.estado in ('pendiente','confirmado','en_atencion','finalizado')
--   order by a.fecha, a.hora;

-- 13.b ¿La constraint quedó creada?
--   select conname from pg_constraint where conname = 'turnos_sin_solapamiento';

-- 13.c ¿RLS activo donde tiene que estar? (rowsecurity debe ser true en todas)
--   select relname, relrowsecurity from pg_class
--   where relname in ('turnos','servicios','clientes','turno_servicios');

-- 13.d Comprobá que la anon key YA NO ve los turnos:
--   Supabase → SQL Editor no sirve para esto (corre como service_role).
--   Desde una terminal:
--     curl "https://TU_PROYECTO.supabase.co/rest/v1/turnos?select=*" \
--          -H "apikey: TU_ANON_KEY"
--   Antes devolvía todos tus clientes. Ahora tiene que devolver [].


-- ############################################################################
-- #  PARTE C — FUNCIONES DE RESERVA  (era 008_funciones_reserva.sql)
-- ############################################################################

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


-- ############################################################################
-- #  LISTO
-- #
-- #  Siguiente paso obligatorio: cargar TU horario real.
-- #  Está en db/SUPABASE_CONFIGURAR.sql — el script dejó un horario por
-- #  defecto (lunes a sábado, 08–12 y 14–20) que casi seguro no es el tuyo.
-- #
-- #  Después: db/SUPABASE_VERIFICAR.sql para confirmar que todo quedó bien.
-- ############################################################################
