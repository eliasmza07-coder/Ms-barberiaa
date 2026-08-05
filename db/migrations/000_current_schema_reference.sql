-- ============================================================================
-- 000_current_schema_reference.sql
--
-- Esto NO es una migración a ejecutar: es la referencia documentada del
-- esquema que la base de datos YA TIENE en producción hoy, tal como lo usa
-- el código migrado en src/modules/*. Sirve para levantar un entorno de
-- desarrollo/staging idéntico al actual sin tener que inspeccionar el
-- dashboard de Supabase.
--
-- El proyecto (src/) sigue apuntando a estas mismas tablas, con estos
-- mismos nombres de columna. Si en el futuro se decide adoptar el esquema
-- ampliado de 001_future_schema_multi_tenant.sql, hacerlo siguiendo el plan
-- de migración de docs/ARCHITECTURE.md (sección 12) — no reemplazar esto
-- de un día para el otro.
-- ============================================================================

create table if not exists servicios (
  id text primary key,
  nombre text not null,
  precio numeric not null,
  duracion integer not null default 30,
  "desc" text
);

create table if not exists config_jornada (
  fecha date primary key,
  apertura integer not null,
  cierre integer not null,
  intervalo integer not null
);

create table if not exists dias_libres (
  fecha date primary key
);

create table if not exists horas_bloqueadas (
  id bigint generated always as identity primary key,
  fecha date not null,
  hora text not null,
  unique (fecha, hora)
);

create table if not exists turnos (
  id bigint generated always as identity primary key,
  fecha date not null,
  hora text not null,
  cliente_nombre text not null,
  cliente_telefono text not null,
  servicio_nombre text not null,
  precio numeric,
  duracion_min integer not null default 30,
  estado text not null default 'pendiente' -- pendiente | confirmado | cancelado
);

-- Nota: la creación de un turno NO se hace con un insert directo desde el
-- cliente — pasa por la Edge Function `gestionar-reserva`, que es la que
-- valida y escribe en `turnos`. Ver src/modules/reservations/reservations.service.js.
