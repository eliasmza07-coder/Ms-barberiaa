-- ############################################################################
-- #   MS BARBERÍA — VERIFICACIÓN POSTERIOR  (correr DESPUÉS de instalar)     #
-- ############################################################################
--
-- Solo lectura. Confirma que la instalación quedó completa y, sobre todo,
-- que el agujero de seguridad se cerró.
--
-- Mirá la columna `estado`: todo tiene que decir OK.
-- ############################################################################

with
-- ---------- ¿Están todas las piezas? ----------
chk_tablas as (
  select 'tablas nuevas creadas' as chequeo,
         case when count(*) = 9 then 'OK' else 'PROBLEMA' end as estado,
         format('%s de 9 (%s)', count(*), string_agg(table_name, ', ' order by table_name)) as detalle
  from information_schema.tables
  where table_schema = 'public'
    and table_name in ('negocios','negocio_config','horarios_semanales','excepciones_horario',
                       'bloqueos','clientes','turno_servicios','reservas_temporales','turnos')
),
chk_funciones as (
  select 'funciones de reserva creadas',
         case when count(*) >= 10 then 'OK' else 'PROBLEMA' end,
         format('%s encontradas: %s', count(*), string_agg(proname, ', ' order by proname))
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and proname in ('es_barbero','jornadas_rango','ocupacion_rango','validar_slot','crear_hold',
                    'liberar_hold','crear_reserva','cambiar_estado_turno','reprogramar_turno',
                    'turno_por_token','cancelar_turno_cliente','transicion_valida',
                    'mensaje_error_reserva','limpiar_holds_vencidos')
),

-- ---------- LO MÁS IMPORTANTE: la doble reserva ----------
chk_constraint as (
  select 'protección anti-doble-reserva',
         case when exists (select 1 from pg_constraint where conname = 'turnos_sin_solapamiento')
              then 'OK' else 'PROBLEMA' end,
         case when exists (select 1 from pg_constraint where conname = 'turnos_sin_solapamiento')
              then 'constraint `turnos_sin_solapamiento` activa: dos personas no pueden tomar el mismo horario ni reservando en el mismo milisegundo'
              else 'NO se creó. Casi seguro hay turnos superpuestos ya cargados: mirá la consulta B de abajo, resolvelos y volvé a correr el instalador' end
),

-- ---------- LO SEGUNDO MÁS IMPORTANTE: la privacidad ----------
chk_rls as (
  select 'RLS en ' || c.relname,
         case when c.relrowsecurity then 'OK' else 'PROBLEMA' end,
         case when c.relrowsecurity then 'activo'
              else 'DESACTIVADO: esta tabla sigue siendo legible por cualquiera con la anon key' end
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('turnos','turno_servicios','clientes','servicios')
),
chk_politicas_turnos as (
  select 'políticas de acceso a turnos',
         case when count(*) filter (where cmd = 'INSERT') = 0 and count(*) >= 2 then 'OK'
              when count(*) filter (where cmd = 'INSERT') > 0 then 'PROBLEMA'
              else 'PROBLEMA' end,
         format('%s política(s): %s. Nadie debe poder INSERT directo (la creación pasa por crear_reserva()).',
                count(*), coalesce(string_agg(policyname, ' | '), 'ninguna'))
  from pg_policies where schemaname = 'public' and tablename = 'turnos'
),
chk_dias_libres as (
  select 'política pública peligrosa en dias_libres',
         case when exists (
           select 1 from pg_policies
           where tablename = 'dias_libres' and cmd = 'INSERT' and coalesce(with_check,'') like '%true%'
         ) then 'PROBLEMA' else 'OK' end,
         'Si sigue existiendo, un visitante anónimo puede cerrar la barbería insertando días libres'
),
chk_barbero as (
  select 'usuarios con rol barbero',
         case when count(*) > 0 then 'OK' else 'PROBLEMA' end,
         format('%s. Sin al menos uno, nadie puede administrar la agenda.', count(*))
  from perfiles where rol = 'barbero'
),

-- ---------- ¿Se migraron los datos viejos? ----------
chk_migracion as (
  select 'migración de datos del modelo viejo',
         case when (select count(*) from dias_libres) <=
                   (select count(*) from excepciones_horario where tipo = 'cerrado')
          and  (select count(*) from horas_bloqueadas) <= (select count(*) from bloqueos)
              then 'OK' else 'ATENCION' end,
         format('días libres %s → excepciones cerrado %s | horas bloqueadas %s → bloqueos %s | config_jornada %s → excepciones especial %s',
                (select count(*) from dias_libres),
                (select count(*) from excepciones_horario where tipo = 'cerrado'),
                (select count(*) from horas_bloqueadas),
                (select count(*) from bloqueos),
                (select count(*) from config_jornada),
                (select count(*) from excepciones_horario where tipo = 'especial'))
),
chk_turno_servicios as (
  select 'turnos con su detalle de servicios',
         case when (select count(*) from turnos) = 0
                or (select count(*) from turnos t where not exists
                     (select 1 from turno_servicios ts where ts.turno_id = t.id)) = 0
              then 'OK' else 'ATENCION' end,
         format('%s de %s turnos tienen detalle cargado',
                (select count(distinct turno_id) from turno_servicios),
                (select count(*) from turnos))
),
chk_clientes as (
  select 'ficha de clientes generada',
         'OK',
         format('%s cliente(s) a partir del historial de turnos', (select count(*) from clientes))
),
chk_rango as (
  select 'turnos con rango horario calculado',
         case when count(*) = 0 then 'OK' else 'ATENCION' end,
         format('%s turno(s) sin rango (hora en formato inválido; ver consulta A)', count(*))
  from turnos where rango is null
),

-- ---------- ¿El horario está cargado? ----------
chk_horario as (
  select 'horario semanal cargado',
         case when count(*) > 0 then 'OK' else 'PROBLEMA' end,
         format('%s tramo(s) en %s día(s) de la semana. Si son los de ejemplo, editá SUPABASE_CONFIGURAR.sql.',
                count(*), count(distinct dia_semana))
  from horarios_semanales where activo
),
chk_config as (
  select 'configuración del negocio',
         case when count(*) = 1 then 'OK' else 'PROBLEMA' end,
         (select format('zona %s | intervalo %s min | limpieza %s min | anticipación %s min / %s días | cancela hasta %s h antes',
                 zona_horaria, intervalo_slot_min, margen_despues_min,
                 anticipacion_min_min, anticipacion_max_dias, limite_cancelacion_horas)
          from negocio_config limit 1)
  from negocio_config
),
chk_jornadas as (
  select 'el motor resuelve jornadas para los próximos 7 días',
         case when count(*) > 0 then 'OK' else 'PROBLEMA' end,
         format('%s tramo(s) disponibles entre hoy y dentro de 7 días', count(*))
  from jornadas_rango(current_date, current_date + 7)
)
select * from chk_tablas
union all select * from chk_funciones
union all select * from chk_constraint
union all select * from chk_rls
union all select * from chk_politicas_turnos
union all select * from chk_dias_libres
union all select * from chk_barbero
union all select * from chk_migracion
union all select * from chk_turno_servicios
union all select * from chk_clientes
union all select * from chk_rango
union all select * from chk_horario
union all select * from chk_config
union all select * from chk_jornadas
order by case estado when 'PROBLEMA' then 1 when 'ATENCION' then 2 else 3 end, chequeo;


-- ############################################################################
-- #  LA PRUEBA QUE NO SE PUEDE HACER DESDE ACÁ
-- #
-- #  El SQL Editor de Supabase corre como `service_role`, que se saltea RLS
-- #  por diseño. Así que desde acá SIEMPRE vas a ver los turnos, tenga o no
-- #  tenga RLS. Para comprobar de verdad que tus clientes ya no son
-- #  públicos, hacelo desde afuera, con la anon key:
-- #
-- #    curl "https://TU_PROYECTO.supabase.co/rest/v1/turnos?select=*" \
-- #         -H "apikey: TU_ANON_KEY"
-- #
-- #  ANTES de instalar: devuelve todos tus clientes con nombre y teléfono.
-- #  DESPUÉS:           tiene que devolver []
-- #
-- #  (La anon key está en Supabase → Settings → API → Project API keys →
-- #   anon public, y también en tu archivo .env)
-- ############################################################################


-- ============================================================================
-- CONSULTAS DE DETALLE
-- ============================================================================

-- A) Turnos con hora en formato inválido (corregir a mano):
--   select id, fecha, hora, cliente_nombre, estado from turnos where rango is null;

-- B) Turnos superpuestos que impiden crear la protección:
--   select a.id as id_a, a.hora as hora_a, a.cliente_nombre as cliente_a,
--          b.id as id_b, b.hora as hora_b, b.cliente_nombre as cliente_b, a.fecha
--   from turnos a join turnos b
--     on a.id < b.id and a.rango && b.rango
--    and a.estado in ('pendiente','confirmado','en_atencion','finalizado')
--    and b.estado in ('pendiente','confirmado','en_atencion','finalizado')
--   order by a.fecha, a.hora;
--
--   Resolvelos (cancelá uno de cada par) y volvé a correr el instalador:
--     update turnos set estado = 'cancelado', cancelado_por = 'barbero',
--            motivo_cancelacion = 'Turno duplicado' where id = EL_ID_QUE_SOBRA;

-- C) Ver la agenda de hoy como la ve el panel:
--   select hora, estado, cliente_nombre, servicio_nombre, duracion_min
--   from v_agenda_dia where fecha = current_date order by hora;

-- D) Clientes con más ausencias:
--   select nombre, telefono, total_turnos, total_faltas, ultima_visita
--   from clientes where total_faltas > 0 order by total_faltas desc;
