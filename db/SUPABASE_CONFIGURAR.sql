-- ############################################################################
-- #                                                                          #
-- #   MS BARBERÍA — CONFIGURACIÓN DEL NEGOCIO                                #
-- #                                                                          #
-- #   Correr DESPUÉS de SUPABASE_INSTALAR_TODO.sql                           #
-- #                                                                          #
-- #   Este archivo SÍ hay que editarlo antes de correrlo: son TUS horarios   #
-- #   y TUS reglas. Lo que viene cargado son valores de ejemplo.             #
-- #                                                                          #
-- ############################################################################


-- ============================================================================
-- 1. TU HORARIO SEMANAL
--
-- Una fila = un tramo de trabajo. Dos filas para el mismo día = jornada
-- partida (mañana y tarde, con la pausa del mediodía en el medio).
--
-- dia_semana:  0=domingo  1=lunes  2=martes  3=miércoles
--              4=jueves   5=viernes  6=sábado
--
-- Los días que no aparecen acá quedan cerrados automáticamente.
-- Las horas van en formato 24h y admiten minutos ('08:30' es válido).
-- ============================================================================

-- ⚠️  Esto borra el horario por defecto que dejó la instalación.
--     No toca ningún turno ya reservado.
delete from horarios_semanales;

insert into horarios_semanales (dia_semana, hora_inicio, hora_fin) values
  -- Lunes
  (1, '08:00', '12:00'),
  (1, '14:00', '20:00'),
  -- Martes
  (2, '08:00', '12:00'),
  (2, '14:00', '20:00'),
  -- Miércoles
  (3, '08:00', '12:00'),
  (3, '14:00', '20:00'),
  -- Jueves
  (4, '08:00', '12:00'),
  (4, '14:00', '20:00'),
  -- Viernes (ejemplo: hasta más tarde)
  (5, '08:00', '12:00'),
  (5, '14:00', '21:00'),
  -- Sábado (ejemplo: corrido, sin pausa)
  (6, '08:00', '16:00');
  -- Domingo: no se carga → cerrado.

-- Comprobá cómo quedó:
--   select dia_semana, hora_inicio, hora_fin from horarios_semanales order by 1, 2;


-- ============================================================================
-- 2. REGLAS DEL NEGOCIO
--
-- Cambiá los valores y corré el UPDATE. Cada uno explicado:
-- ============================================================================

update negocio_config set

  -- Zona horaria. No la toques salvo que el negocio no esté en Paraguay.
  zona_horaria = 'America/Asuncion',

  -- Cada cuántos minutos aparece un horario en la grilla.
  -- 15 es el recomendado. Con 30 se ve más limpio pero se pierden huecos;
  -- con 5 hay más opciones pero la grilla marea.
  intervalo_slot_min = 15,

  -- Minutos de preparación ANTES de cada turno (normalmente 0).
  margen_antes_min = 0,

  -- Minutos de limpieza DESPUÉS de cada turno. Se bloquean solos: si el
  -- corte es de 30 y esto es 5, el próximo turno no puede empezar antes
  -- de que pasen 35.
  margen_despues_min = 5,

  -- Cuánto antes hay que reservar. Con 30, a las 14:20 el primer horario
  -- ofrecido es 15:00. Evita que aparezca alguien "para ya".
  anticipacion_min_min = 30,

  -- Cuántos días hacia adelante se puede reservar. Con 60, nadie te
  -- agenda para dentro de un año.
  anticipacion_max_dias = 60,

  -- Hasta cuántas horas antes el cliente puede cancelar solo. Pasado ese
  -- plazo, el sistema le dice que te escriba por WhatsApp.
  limite_cancelacion_horas = 3,

  -- Cuántos minutos se le aparta el horario mientras completa sus datos.
  hold_minutos = 5,

  -- false = vos confirmás cada turno a mano (flujo actual).
  -- true  = se confirman solos al reservar.
  confirmacion_automatica = false,

  -- A partir de cuántas ausencias el panel marca al cliente en rojo.
  max_faltas_alerta = 2,

  updated_at = now();


-- ============================================================================
-- 3. NOMBRE DEL NEGOCIO
-- ============================================================================

update negocios
set nombre = 'MS Barbería y Peluquería',
    slug   = 'ms-barberia'
where id = '00000000-0000-0000-0000-000000000001';


-- ============================================================================
-- 4. TUS SERVICIOS
--
-- Si ya los tenés cargados, esto solo les completa los campos nuevos.
-- Revisá que las duraciones sean las REALES: de acá sale todo el cálculo
-- de disponibilidad. Un corte que dura 40 minutos pero está cargado como
-- 30 te va a superponer turnos todos los días.
-- ============================================================================

-- Ver cómo están hoy:
--   select id, nombre, precio, duracion, activo, orden from servicios order by orden, nombre;

-- Todos los existentes quedan activos y visibles:
update servicios set activo = true where activo is null;

-- Ejemplo de ajuste de duración (poné el id real que veas arriba):
--   update servicios set duracion = 40 where id = 1;

-- Ejemplo de servicio con más limpieza que el resto (ej. coloración):
--   update servicios set margen_despues_min = 15 where id = 3;

-- Ejemplo de orden en que se muestran en la carta:
--   update servicios set orden = 1 where nombre = 'Corte Masculino';
--   update servicios set orden = 2 where nombre = 'Perfilado de Barba';

-- Servicio nuevo (NO se manda id: lo genera la base):
--   insert into servicios (nombre, precio, duracion, "desc", activo, orden)
--   values ('Lavado', 15000, 10, 'Lavado con masaje capilar.', true, 5);


-- ============================================================================
-- 5. VACACIONES Y FERIADOS
--
-- Un rango completo con una sola fila.
-- ============================================================================

-- Vacaciones (ejemplo — cambiá las fechas):
--   insert into excepciones_horario (fecha_desde, fecha_hasta, tipo, motivo)
--   values ('2026-01-05', '2026-01-19', 'cerrado', 'Vacaciones');

-- Feriado suelto:
--   insert into excepciones_horario (fecha_desde, fecha_hasta, tipo, motivo)
--   values ('2026-05-01', '2026-05-01', 'cerrado', 'Día del Trabajador');

-- Día con horario especial (ej. 24 de diciembre, medio día):
--   insert into excepciones_horario (fecha_desde, fecha_hasta, tipo, hora_inicio, hora_fin, motivo)
--   values ('2026-12-24', '2026-12-24', 'especial', '08:00', '13:00', 'Nochebuena');

-- Ver lo cargado:
--   select fecha_desde, fecha_hasta, tipo, hora_inicio, hora_fin, motivo
--   from excepciones_horario order by fecha_desde;


-- ============================================================================
-- 6. BLOQUEOS PUNTUALES
--
-- Para cosas de un día específico (reunión, trámite, turno médico).
-- Esto también lo vas a poder hacer desde el panel más adelante.
-- ============================================================================

--   insert into bloqueos (fecha, hora_inicio, hora_fin, motivo)
--   values ('2026-08-12', '14:00', '16:00', 'Reunión');


-- ============================================================================
-- 7. PROBAR QUE TODO QUEDÓ BIEN
-- ============================================================================

-- 7.a ¿Qué jornadas resuelve el sistema para los próximos 7 días?
--     (los días cerrados no aparecen)
select fecha, hora_inicio, hora_fin
from jornadas_rango(current_date, current_date + 7)
order by fecha, hora_inicio;

-- 7.b ¿Qué está ocupado en esos días? (solo horarios, sin datos personales)
--   select * from ocupacion_rango(current_date, current_date + 7) order by fecha, hora_inicio;

-- 7.c ¿Es válido este horario? (null = sí, cualquier texto = el motivo del no)
--   select validar_slot(current_date + 1, time '09:00', 30);

-- 7.d Reserva de prueba. Cambiá el id del servicio por uno real.
--   select crear_reserva(current_date + 1, time '09:00', 'Prueba', '0981000000', array['1']);
--
--   Corré la MISMA línea dos veces: la segunda tiene que devolver
--   HORARIO_OCUPADO. Si devuelve ok=true las dos veces, la protección
--   anti-doble-reserva NO se creó — revisá SUPABASE_VERIFICAR.sql.
--
--   Para borrar la prueba después:
--     delete from turnos where cliente_telefono = '0981000000';
