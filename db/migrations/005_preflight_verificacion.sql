-- ============================================================================
-- 005_preflight_verificacion.sql
--
-- SOLO LECTURA. No modifica absolutamente nada. Corré esto PRIMERO en el
-- SQL Editor y guardá el resultado: es la foto del estado real de tu base
-- antes de tocarla, y te dice si alguna de las migraciones que siguen va a
-- tener problemas.
--
-- Cada fila es un chequeo. Mirá la columna `estado`:
--   OK       → todo bien, seguí.
--   ATENCION → no frena nada, pero hay que saberlo.
--   PROBLEMA → resolvelo antes de correr 006/007/008.
-- ============================================================================

with
-- ---------- Tipos de las columnas clave ----------
tipos as (
  select table_name, column_name, data_type,
         (column_default is not null or is_identity = 'YES') as tiene_default
  from information_schema.columns
  where table_schema = 'public'
    and (table_name, column_name) in (
      ('servicios','id'), ('servicios','duracion'), ('servicios','precio'),
      ('turnos','id'), ('turnos','hora'), ('turnos','precio'), ('turnos','duracion_min'),
      ('config_jornada','id'), ('config_jornada','fecha'),
      ('horas_bloqueadas','hora')
    )
),
chk_servicios_id as (
  select 'tipo de servicios.id' as chequeo,
         case when data_type in ('bigint','integer') and not tiene_default then 'PROBLEMA'
              when data_type in ('bigint','integer') then 'ATENCION'
              else 'OK' end as estado,
         format('es %s%s. El código JS genera ids tipo ''serv_1712...'' (texto): con un id numérico, crear un servicio nuevo desde el panel falla con error 400.',
                data_type, case when tiene_default then ' con default' else ' SIN default (tampoco se puede insertar sin id)' end) as detalle
  from tipos where table_name='servicios' and column_name='id'
),
-- ---------- ¿Existe es_barbero()? ----------
chk_es_barbero as (
  select 'función es_barbero()',
         case when exists (select 1 from pg_proc where proname = 'es_barbero') then 'OK' else 'PROBLEMA' end,
         'Todas las políticas RLS nuevas dependen de esta función. Si falta, la crea 006_normalizacion_base.sql.'
),
chk_perfiles as (
  select 'tabla perfiles',
         case when exists (select 1 from information_schema.tables where table_schema='public' and table_name='perfiles') then 'OK' else 'PROBLEMA' end,
         'Necesaria para roles (barbero/cliente).'
),
chk_barbero_cargado as (
  select 'hay al menos un usuario con rol barbero',
         case when exists (select 1 from perfiles where rol = 'barbero') then 'OK' else 'PROBLEMA' end,
         'Sin esto, después de activar RLS NADIE puede administrar los turnos. Ver PASO MANUAL al final de SUPABASE_SETUP.sql.'
),
-- ---------- Estado actual de RLS ----------
chk_rls as (
  select 'RLS en ' || c.relname,
         case when c.relrowsecurity then 'OK' else 'PROBLEMA' end,
         case when c.relrowsecurity then 'activo'
              else 'DESACTIVADO: esta tabla es legible (y editable) por cualquiera con la anon key.' end
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname in ('turnos','servicios','perfiles','resenas')
),
-- ---------- Datos que pueden romper las migraciones ----------
chk_hora_invalida as (
  select 'formato de turnos.hora',
         case when count(*) = 0 then 'OK' else 'PROBLEMA' end,
         format('%s turno(s) con hora que no se puede convertir a hora real. Se listan abajo.', count(*))
  from turnos
  where hora is null or hora !~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$'
),
chk_estados as (
  select 'valores de turnos.estado',
         case when count(*) = 0 then 'OK' else 'ATENCION' end,
         coalesce('valores fuera del set esperado: ' || string_agg(distinct estado, ', '), 'todos válidos')
  from turnos
  where estado not in ('pendiente','confirmado','en_atencion','finalizado','cancelado','no_asistio')
),
chk_solapados as (
  select 'turnos superpuestos ya cargados',
         case when count(*) = 0 then 'OK' else 'PROBLEMA' end,
         format('%s par(es) de turnos que se pisan. Impiden crear la protección anti-doble-reserva; la consulta de abajo los lista.', count(*))
  from turnos a
  join turnos b
    on a.id < b.id
   and a.fecha = b.fecha
   and a.estado <> 'cancelado' and b.estado <> 'cancelado'
   and a.hora ~ '^[0-9]{1,2}:[0-9]{2}' and b.hora ~ '^[0-9]{1,2}:[0-9]{2}'
   and tsrange(a.fecha + a.hora::time, a.fecha + a.hora::time + make_interval(mins => coalesce(a.duracion_min,30)), '[)')
    && tsrange(b.fecha + b.hora::time, b.fecha + b.hora::time + make_interval(mins => coalesce(b.duracion_min,30)), '[)')
),
chk_dup_config as (
  select 'fechas duplicadas en config_jornada',
         case when count(*) = 0 then 'OK' else 'ATENCION' end,
         format('%s fecha(s) repetidas; 006 se queda con la más reciente.', count(*))
  from (select fecha from config_jornada group by fecha having count(*) > 1) x
),
chk_dup_horas as (
  select 'bloqueos duplicados en horas_bloqueadas',
         case when count(*) = 0 then 'OK' else 'ATENCION' end,
         format('%s combinación(es) fecha+hora repetidas.', count(*))
  from (select fecha, hora from horas_bloqueadas group by fecha, hora having count(*) > 1) x
),
chk_servicios_huerfanos as (
  select 'turnos que apuntan a un servicio inexistente',
         'ATENCION',
         format('%s turno(s) cuyo servicio_nombre ya no existe en el catálogo. No rompe nada (el nombre queda congelado en el turno), pero no se podrán vincular al catálogo.', count(*))
  from turnos t
  where not exists (select 1 from servicios s where s.nombre = t.servicio_nombre)
),
-- ---------- Restos de esquemas anteriores ----------
chk_tabla_experiencia as (
  select 'tabla duplicada `experiencia`',
         case when exists (select 1 from information_schema.tables where table_schema='public' and table_name='experiencia')
              then 'ATENCION' else 'OK' end,
         'Convive con `experiencia_items`, que es la que usa el código. La limpieza opcional está en 009.'
),
chk_columnas_viejas as (
  select 'columnas duplicadas en sitio_config',
         case when count(*) = 0 then 'OK' else 'ATENCION' end,
         coalesce('sobran: ' || string_agg(column_name, ', '), 'ninguna')
  from information_schema.columns
  where table_schema='public' and table_name='sitio_config'
    and column_name in ('titulo_hero1','titulo_hero_1','hero_titulo_1','hero_titulo_2','titulo_hero_2',
                        'subtitulo_hero','direccion_completa','mapa_url','texto_footer')
),
chk_politica_peligrosa as (
  select 'política pública de inserción en dias_libres',
         case when exists (
           select 1 from pg_policies
           where tablename = 'dias_libres' and cmd = 'INSERT' and coalesce(with_check,'') like '%true%'
         ) then 'PROBLEMA' else 'OK' end,
         'Si existe, cualquier visitante anónimo puede insertar días libres y cerrar la barbería. La elimina 007.'
),
-- ---------- Volumen ----------
chk_volumen as (
  select 'volumen de datos',
         'OK',
         format('%s turnos, %s servicios, %s días libres, %s horas bloqueadas, %s configs de jornada.',
                (select count(*) from turnos), (select count(*) from servicios),
                (select count(*) from dias_libres), (select count(*) from horas_bloqueadas),
                (select count(*) from config_jornada))
)
select * from chk_servicios_id
union all select * from chk_es_barbero
union all select * from chk_perfiles
union all select * from chk_barbero_cargado
union all select * from chk_rls
union all select * from chk_hora_invalida
union all select * from chk_estados
union all select * from chk_solapados
union all select * from chk_dup_config
union all select * from chk_dup_horas
union all select * from chk_servicios_huerfanos
union all select * from chk_tabla_experiencia
union all select * from chk_columnas_viejas
union all select * from chk_politica_peligrosa
union all select * from chk_volumen
order by case estado when 'PROBLEMA' then 1 when 'ATENCION' then 2 else 3 end, chequeo;


-- ============================================================================
-- CONSULTAS DE DETALLE — corré la que corresponda si el reporte marcó
-- PROBLEMA en ese punto.
-- ============================================================================

-- A) Turnos con hora en formato inválido (hay que corregirlos a mano):
--
--   select id, fecha, hora, cliente_nombre, estado from turnos
--   where hora is null or hora !~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$';

-- B) Turnos superpuestos (decidí cuál queda y cancelá el otro):
--
--   select a.id as id_a, a.hora as hora_a, a.duracion_min as dur_a, a.cliente_nombre as cliente_a,
--          b.id as id_b, b.hora as hora_b, b.duracion_min as dur_b, b.cliente_nombre as cliente_b,
--          a.fecha
--   from turnos a
--   join turnos b on a.id < b.id and a.fecha = b.fecha
--    and a.estado <> 'cancelado' and b.estado <> 'cancelado'
--    and tsrange(a.fecha + a.hora::time, a.fecha + a.hora::time + make_interval(mins => coalesce(a.duracion_min,30)), '[)')
--     && tsrange(b.fecha + b.hora::time, b.fecha + b.hora::time + make_interval(mins => coalesce(b.duracion_min,30)), '[)')
--   order by a.fecha, a.hora;

-- C) Marcar tu usuario como barbero (reemplazá el email):
--
--   insert into perfiles (id, nombre, rol)
--   select id, 'Barbero', 'barbero' from auth.users where email = 'TU_EMAIL_ACA'
--   on conflict (id) do update set rol = 'barbero';
