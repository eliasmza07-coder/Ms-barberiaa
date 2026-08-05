-- ============================================================================
-- 009_limpieza_opcional.sql
--
-- ⚠️  ESTE SCRIPT SÍ BORRA COSAS. Es el único de la entrega que lo hace.
--
-- No es necesario para que nada funcione: es higiene. Corrélo solo cuando
-- 007 y 008 lleven varias semanas andando bien en producción y ya no
-- pienses volver atrás.
--
-- Saca de encima los restos de intentos anteriores que hoy conviven en tu
-- base y confunden a cualquiera que la abra: tablas duplicadas, columnas
-- que el código nunca lee, y el modelo viejo de agenda que quedó
-- reemplazado por horarios_semanales / excepciones_horario / bloqueos.
--
-- ANTES DE CORRERLO: Database → Backups → Create backup.
-- ============================================================================

-- ============================================================================
-- 1. Tabla `experiencia` duplicada
-- El código lee `experiencia_items`. `experiencia` es de un esquema
-- anterior. Primero se rescata cualquier dato que solo esté ahí.
-- ============================================================================

do $$
begin
  if exists (select 1 from information_schema.tables
             where table_schema='public' and table_name='experiencia') then

    insert into experiencia_items (icono, titulo, descripcion, orden, activo)
    select 'shield-check', e.titulo, e.descripcion, coalesce(e.orden, 0), true
    from experiencia e
    where not exists (select 1 from experiencia_items ei where ei.titulo = e.titulo);

    drop table experiencia;
    raise notice 'Tabla `experiencia` eliminada; sus items se movieron a experiencia_items.';
  end if;
end $$;


-- ============================================================================
-- 2. Columnas duplicadas de sitio_config
-- 006_normalizacion_base.sql ya copió los datos a los nombres oficiales.
-- Verificá que la página se vea bien antes de correr esto.
-- ============================================================================

alter table sitio_config drop column if exists titulo_hero1;
alter table sitio_config drop column if exists titulo_hero_1;
alter table sitio_config drop column if exists hero_titulo_1;
alter table sitio_config drop column if exists hero_titulo_2;
alter table sitio_config drop column if exists titulo_hero_2;
alter table sitio_config drop column if exists subtitulo_hero;
alter table sitio_config drop column if exists direccion_completa;
alter table sitio_config drop column if exists mapa_url;
alter table sitio_config drop column if exists texto_footer;


-- ============================================================================
-- 3. Modelo viejo de agenda
-- config_jornada, dias_libres y horas_bloqueadas quedaron reemplazados.
-- Sus datos se copiaron en 007 (sección 10).
--
-- ⚠️  DEJADO COMENTADO A PROPÓSITO. Descomentá recién cuando estés seguro
--     de que no queda código llamando a schedule.repository.js.
-- ============================================================================

-- Antes de borrar, comprobá que la migración de datos quedó completa:
--
--   select
--     (select count(*) from dias_libres)        as dias_libres_viejos,
--     (select count(*) from excepciones_horario where tipo='cerrado')  as excepciones_cerrado,
--     (select count(*) from horas_bloqueadas)   as horas_viejas,
--     (select count(*) from bloqueos)           as bloqueos_nuevos,
--     (select count(*) from config_jornada)     as configs_viejas,
--     (select count(*) from excepciones_horario where tipo='especial') as excepciones_especial;
--
-- Si los números cierran:
--
--   drop table if exists horas_bloqueadas;
--   drop table if exists dias_libres;
--   drop table if exists config_jornada;
--
-- Y borrá también estos archivos del proyecto:
--   src/modules/schedule/schedule.repository.js
--   src/modules/schedule/schedule.service.js
--   db/FIX_DIAS_LIBRES_RLS.sql
--   db/FIX_SERVICIOS_400.sql
--   db/migrations/001_future_schema_multi_tenant.sql   (quedó obsoleto:
--       ese multi-tenant "a futuro" ya está implementado con negocio_id
--       en las tablas nuevas, sin renombrar todo a inglés)


-- ============================================================================
-- 4. Columna redundante en turnos
-- `servicio_nombre` quedó como resumen legible ("Corte + Barba"); el detalle
-- real vive en turno_servicios. Se mantiene a propósito: es lo que hace que
-- el historial no se falsee si mañana borrás un servicio. NO la borres.
-- ============================================================================
