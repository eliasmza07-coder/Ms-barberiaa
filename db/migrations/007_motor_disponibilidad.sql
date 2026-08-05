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
