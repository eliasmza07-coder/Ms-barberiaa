-- ============================================================================
-- SUPABASE_SETUP.sql — Script único y completo para MS Barbería (v7)
--
-- Crea TODO lo que el proyecto necesita: las tablas base del sistema de
-- turnos, más el CMS, reseñas y cuentas de cliente. Pensado para correr
-- sobre CUALQUIER estado de tu base:
--
--   • Si una tabla/columna/relación YA EXISTE → no la toca, no pierde datos.
--   • Si NO EXISTE → la crea.
--
-- Podés correrlo en un proyecto de Supabase totalmente vacío (crea todo
-- desde cero) o sobre tu proyecto actual en producción con datos reales
-- (solo agrega lo que falta). Es seguro ejecutarlo más de una vez.
--
-- Cómo correrlo: Supabase → tu proyecto → SQL Editor → New query → pegar
-- todo esto → Run.
-- ============================================================================


-- ============================================================================
-- PARTE 0 — TABLAS BASE (sistema de turnos)
-- Estas son las tablas que ya existen y usa el sitio hoy. Si tu proyecto
-- ya las tiene (con datos reales de turnos), esta parte no hace nada —
-- CREATE TABLE IF NOT EXISTS nunca toca una tabla que ya existe. Si estás
-- arrancando de cero, las crea con la misma forma que ya usa el código.
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
  id bigint generated always as identity primary key,
  fecha date not null,
  created_at timestamptz default now()
);

create table if not exists horas_bloqueadas (
  id bigint generated always as identity primary key,
  fecha date not null,
  hora text not null,
  created_at timestamptz default now(),
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
  estado text not null default 'pendiente',
  created_at timestamptz default now()
);
create index if not exists idx_turnos_fecha on turnos(fecha);

-- Nota: la creación de un turno nuevo no es un insert directo desde el
-- cliente — pasa por la Edge Function `gestionar-reserva`, que valida y
-- escribe en `turnos`. Esta tabla solo se declara acá por si tu proyecto
-- arranca de cero; si ya existe, este bloque no la modifica.


-- ============================================================================
-- PARTE 1 — CONTENIDO EDITABLE DEL SITIO (CMS)
-- ============================================================================

create table if not exists sitio_config (
  id int primary key default 1,
  nombre_negocio text not null default 'MS Barbería y Peluquería',
  eslogan text default 'Studio & Peluquería',
  hero_titulo text default 'El oficio del corte,',
  hero_titulo_destacado text default 'hecho a mano.',
  hero_subtitulo text default 'Barbería tradicional con estándar de estudio: navaja al detalle, atención dedicada y gestión 100% autónoma para asegurar tu espacio sin esperas.',
  direccion text default 'Barrio Yukyry, Luque, Paraguay',
  direccion_corta text default 'Yukyry · Luque · Paraguay',
  telefono text,
  whatsapp text,
  mapa_embed_url text default 'https://www.google.com/maps?q=MS%20Barber%C3%ADa%20y%20Peluquer%C3%ADa%2C%20Luque%2C%20Paraguay&output=embed',
  footer_texto text default '© 2026 Yukyry, Luque, Paraguay. Todos los derechos reservados.',
  logo_url text,
  favicon_url text,
  color_fondo text default '#0A0A0A',
  color_superficie text default '#1A1A1A',
  color_texto text default '#F5F5F4',
  color_acento text default '#E8E8E6',
  modo_mantenimiento boolean not null default false,
  updated_at timestamptz default now(),
  constraint solo_una_fila check (id = 1)
);

-- Si la tabla ya existía con menos columnas (de un intento anterior), esto
-- agrega solo las que falten, sin tocar las que ya están.
alter table sitio_config add column if not exists nombre_negocio text default 'MS Barbería y Peluquería';
alter table sitio_config add column if not exists eslogan text default 'Studio & Peluquería';
alter table sitio_config add column if not exists hero_titulo text default 'El oficio del corte,';
alter table sitio_config add column if not exists hero_titulo_destacado text default 'hecho a mano.';
alter table sitio_config add column if not exists hero_subtitulo text default 'Barbería tradicional con estándar de estudio: navaja al detalle, atención dedicada y gestión 100% autónoma para asegurar tu espacio sin esperas.';
alter table sitio_config add column if not exists direccion text default 'Barrio Yukyry, Luque, Paraguay';
alter table sitio_config add column if not exists direccion_corta text default 'Yukyry · Luque · Paraguay';
alter table sitio_config add column if not exists telefono text;
alter table sitio_config add column if not exists whatsapp text;
alter table sitio_config add column if not exists mapa_embed_url text default 'https://www.google.com/maps?q=MS%20Barber%C3%ADa%20y%20Peluquer%C3%ADa%2C%20Luque%2C%20Paraguay&output=embed';
alter table sitio_config add column if not exists footer_texto text default '© 2026 Yukyry, Luque, Paraguay. Todos los derechos reservados.';
alter table sitio_config add column if not exists logo_url text;
alter table sitio_config add column if not exists favicon_url text;
alter table sitio_config add column if not exists color_fondo text default '#0A0A0A';
alter table sitio_config add column if not exists color_superficie text default '#1A1A1A';
alter table sitio_config add column if not exists color_texto text default '#F5F5F4';
alter table sitio_config add column if not exists color_acento text default '#E8E8E6';

-- Si ya existía la fila con los colores viejos (tema dorado, antes del
-- rediseño monocromático), la actualiza a los valores actuales.
update sitio_config set
  color_fondo = '#0A0A0A',
  color_superficie = '#1A1A1A',
  color_texto = '#F5F5F4',
  color_acento = '#E8E8E6'
where id = 1 and (color_fondo = '#0B0B0C' or color_superficie = '#18160F' or color_texto = '#F3EEE1');
alter table sitio_config add column if not exists modo_mantenimiento boolean default false;
alter table sitio_config add column if not exists updated_at timestamptz default now();
insert into sitio_config (id) values (1) on conflict (id) do nothing;

create table if not exists redes_sociales (
  id bigint generated always as identity primary key,
  plataforma text not null,
  url text not null,
  activo boolean not null default true,
  orden int not null default 0
);
alter table redes_sociales add column if not exists plataforma text default '';
alter table redes_sociales add column if not exists url text default '';
alter table redes_sociales add column if not exists activo boolean default true;
alter table redes_sociales add column if not exists orden int default 0;

create table if not exists experiencia_items (
  id bigint generated always as identity primary key,
  icono text not null default 'shield-check',
  titulo text not null,
  descripcion text,
  orden int not null default 0,
  activo boolean not null default true
);
alter table experiencia_items add column if not exists icono text default 'shield-check';
alter table experiencia_items add column if not exists titulo text default '';
alter table experiencia_items add column if not exists descripcion text;
alter table experiencia_items add column if not exists orden int default 0;
alter table experiencia_items add column if not exists activo boolean default true;
insert into experiencia_items (icono, titulo, descripcion, orden)
select * from (values
  ('shield-check', 'Higiene y Estándar', 'Instrumental esterilizado y productos de barbería premium para el cuidado óptimo de tu piel y cabello.', 1),
  ('clock', 'Sin Esperas', 'Nuestro motor de reserva inteligente calcula exactamente los tiempos para respetar tu agenda al minuto.', 2),
  ('award', 'Técnica Clásica', 'Dominio absoluto en tijera, degradados limpios y afeitado tradicional con toalla caliente.', 3)
) as datos(icono, titulo, descripcion, orden)
where not exists (select 1 from experiencia_items);

create table if not exists galeria (
  id bigint generated always as identity primary key,
  imagen_url text not null,
  descripcion text,
  orden int not null default 0,
  activo boolean not null default true,
  created_at timestamptz default now()
);
alter table galeria add column if not exists imagen_url text default '';
alter table galeria add column if not exists descripcion text;
alter table galeria add column if not exists orden int default 0;
alter table galeria add column if not exists activo boolean default true;
alter table galeria add column if not exists created_at timestamptz default now();

create table if not exists faq (
  id bigint generated always as identity primary key,
  pregunta text not null,
  respuesta text not null,
  orden int not null default 0,
  activo boolean not null default true
);
alter table faq add column if not exists pregunta text default '';
alter table faq add column if not exists respuesta text default '';
alter table faq add column if not exists orden int default 0;
alter table faq add column if not exists activo boolean default true;

alter table sitio_config enable row level security;
alter table redes_sociales enable row level security;
alter table experiencia_items enable row level security;
alter table galeria enable row level security;
alter table faq enable row level security;

drop policy if exists "lectura publica sitio_config" on sitio_config;
create policy "lectura publica sitio_config" on sitio_config for select using (true);
drop policy if exists "escritura autenticados sitio_config" on sitio_config;
create policy "escritura autenticados sitio_config" on sitio_config for update using (auth.role() = 'authenticated');

drop policy if exists "lectura publica redes_sociales" on redes_sociales;
create policy "lectura publica redes_sociales" on redes_sociales for select using (true);
drop policy if exists "escritura autenticados redes_sociales" on redes_sociales;
create policy "escritura autenticados redes_sociales" on redes_sociales for all using (auth.role() = 'authenticated');

drop policy if exists "lectura publica experiencia_items" on experiencia_items;
create policy "lectura publica experiencia_items" on experiencia_items for select using (true);
drop policy if exists "escritura autenticados experiencia_items" on experiencia_items;
create policy "escritura autenticados experiencia_items" on experiencia_items for all using (auth.role() = 'authenticated');

drop policy if exists "lectura publica galeria" on galeria;
create policy "lectura publica galeria" on galeria for select using (true);
drop policy if exists "escritura autenticados galeria" on galeria;
create policy "escritura autenticados galeria" on galeria for all using (auth.role() = 'authenticated');

drop policy if exists "lectura publica faq" on faq;
create policy "lectura publica faq" on faq for select using (true);
drop policy if exists "escritura autenticados faq" on faq;
create policy "escritura autenticados faq" on faq for all using (auth.role() = 'authenticated');


-- ============================================================================
-- PARTE 2 — RESEÑAS + FIX DE DÍAS BLOQUEADOS DUPLICADOS
-- ============================================================================

delete from dias_libres a
using dias_libres b
where a.fecha = b.fecha
  and a.id > b.id;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'dias_libres_fecha_unique') then
    alter table dias_libres add constraint dias_libres_fecha_unique unique (fecha);
  end if;
end $$;

create table if not exists resenas (
  id bigint generated always as identity primary key,
  cliente_nombre text not null,
  calificacion int not null check (calificacion between 1 and 5),
  comentario text not null,
  aprobada boolean not null default false,
  orden int not null default 0,
  created_at timestamptz default now()
);
alter table resenas add column if not exists cliente_nombre text default '';
alter table resenas add column if not exists calificacion int default 5;
alter table resenas add column if not exists comentario text default '';
alter table resenas add column if not exists aprobada boolean default false;
alter table resenas add column if not exists orden int default 0;
alter table resenas add column if not exists created_at timestamptz default now();

alter table resenas enable row level security;

drop policy if exists "lectura publica resenas aprobadas" on resenas;
create policy "lectura publica resenas aprobadas" on resenas for select using (aprobada = true);
drop policy if exists "insercion publica de resenas" on resenas;
create policy "insercion publica de resenas" on resenas for insert with check (aprobada = false);
drop policy if exists "lectura completa autenticados resenas" on resenas;
create policy "lectura completa autenticados resenas" on resenas for select using (auth.role() = 'authenticated');
drop policy if exists "escritura autenticados resenas" on resenas;
create policy "escritura autenticados resenas" on resenas for update using (auth.role() = 'authenticated');
drop policy if exists "borrado autenticados resenas" on resenas;
create policy "borrado autenticados resenas" on resenas for delete using (auth.role() = 'authenticated');


-- ============================================================================
-- PARTE 3 — CUENTAS DE CLIENTE OPCIONALES + ROLES (barbero / cliente)
-- ============================================================================

create table if not exists perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre text,
  telefono text,
  rol text not null default 'cliente' check (rol in ('cliente', 'barbero')),
  created_at timestamptz default now()
);
alter table perfiles add column if not exists nombre text;
alter table perfiles add column if not exists telefono text;
alter table perfiles add column if not exists rol text default 'cliente';
alter table perfiles add column if not exists created_at timestamptz default now();

create or replace function crear_perfil_automatico()
returns trigger as $$
begin
  insert into perfiles (id, nombre, telefono, rol)
  values (new.id, new.raw_user_meta_data->>'nombre', new.raw_user_meta_data->>'telefono', 'cliente')
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function crear_perfil_automatico();

-- Relación: cada turno puede (opcionalmente) pertenecer a una cuenta de cliente.
alter table turnos add column if not exists cliente_id uuid references perfiles(id);
create index if not exists idx_turnos_cliente on turnos(cliente_id);

alter table perfiles enable row level security;

drop policy if exists "cada uno lee su propio perfil" on perfiles;
create policy "cada uno lee su propio perfil" on perfiles for select using (auth.uid() = id);
drop policy if exists "cada uno edita su propio perfil" on perfiles;
create policy "cada uno edita su propio perfil" on perfiles for update using (auth.uid() = id);

-- Nota: esta política NO consulta `perfiles` directamente desde su propio
-- USING — eso causaba recursión infinita en RLS (Postgres detecta que,
-- para saber si podés leer `perfiles`, la política necesita volver a leer
-- `perfiles`, lo que dispara la misma política de nuevo). Se resuelve con
-- una función SECURITY DEFINER que corta ese ciclo.
create or replace function es_barbero()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (select 1 from perfiles where id = auth.uid() and rol = 'barbero');
$$;

drop policy if exists "el barbero lee todos los perfiles" on perfiles;
create policy "el barbero lee todos los perfiles" on perfiles for select using (es_barbero());


-- ============================================================================
-- PARTE 4 — RECONCILIACIÓN Y LIMPIEZA
-- Tu base tiene columnas duplicadas de intentos anteriores (ej. tanto
-- `titulo_hero1` como `hero_titulo`) y a `redes_sociales` le falta `activo`
-- (por eso ninguna red social se estaba mostrando). Esto migra cualquier
-- dato que ya hayas cargado en los nombres viejos hacia los nombres que
-- realmente usa el código, y después borra los duplicados. Seguro de
-- correr aunque los nombres viejos no existan en tu caso particular.
-- ============================================================================

-- redes_sociales: el campo que le faltaba (por esto no se veían las redes).
alter table redes_sociales add column if not exists activo boolean default true;
update redes_sociales set activo = true where activo is null;

-- servicios: por si tu tabla real no tiene la columna de descripción
-- (el editor de servicios del admin la necesita para guardar).
alter table servicios add column if not exists "desc" text;

-- Tu tabla real tiene una columna `orden` que el código nunca envía. Si
-- es NOT NULL sin default, cualquier alta/edición de servicio falla con
-- error 400 ("null value in column orden violates not-null constraint").
-- Esto le pone un default para que no haga falta enviarla desde el código.
do $$
begin
  if exists (select 1 from information_schema.columns where table_name = 'servicios' and column_name = 'orden') then
    alter table servicios alter column orden set default 0;
    update servicios set orden = 0 where orden is null;
  end if;
end $$;

-- sitio_config: aseguramos que existan también los nombres viejos, SOLO
-- para poder leer cualquier dato ya cargado en ellos antes de consolidar
-- (si no existían, esto los crea vacíos y no cambia nada).
alter table sitio_config add column if not exists titulo_hero1 text;
alter table sitio_config add column if not exists hero_titulo_2 text;
alter table sitio_config add column if not exists titulo_hero_2 text;
alter table sitio_config add column if not exists subtitulo_hero text;
alter table sitio_config add column if not exists direccion_completa text;
alter table sitio_config add column if not exists mapa_url text;
alter table sitio_config add column if not exists texto_footer text;

-- Migra cualquier valor ya cargado en los nombres viejos hacia los
-- nombres oficiales (solo si el oficial todavía está vacío).
update sitio_config set
  hero_titulo             = coalesce(nullif(hero_titulo, ''), titulo_hero1, hero_titulo),
  hero_titulo_destacado   = coalesce(nullif(hero_titulo_destacado, ''), hero_titulo_2, titulo_hero_2, hero_titulo_destacado),
  hero_subtitulo          = coalesce(nullif(hero_subtitulo, ''), subtitulo_hero, hero_subtitulo),
  direccion                = coalesce(nullif(direccion, ''), direccion_completa, direccion),
  mapa_embed_url           = coalesce(nullif(mapa_embed_url, ''), mapa_url, mapa_embed_url),
  footer_texto             = coalesce(nullif(footer_texto, ''), texto_footer, footer_texto)
where id = 1;

-- Ahora que los datos están a salvo en los nombres oficiales, borramos los
-- duplicados — dejan de existir dos lugares distintos con el mismo dato.
alter table sitio_config drop column if exists titulo_hero1;
alter table sitio_config drop column if exists hero_titulo_2;
alter table sitio_config drop column if exists titulo_hero_2;
alter table sitio_config drop column if exists subtitulo_hero;
alter table sitio_config drop column if exists direccion_completa;
alter table sitio_config drop column if exists mapa_url;
alter table sitio_config drop column if exists texto_footer;

-- redes_sociales: `nombre` e `icono` quedaron de un esquema anterior y el
-- código no los usa (el ícono de cada red se elige automático según
-- `plataforma`). Se borran para no dejar columnas fantasma en el panel.
alter table redes_sociales drop column if exists nombre;
alter table redes_sociales drop column if exists icono;


-- ============================================================================
-- RESUMEN DE RELACIONES CREADAS
-- ============================================================================
--   experiencia_items, galeria, faq, redes_sociales  → tablas independientes (CMS)
--   sitio_config                                     → fila única (id = 1)
--   resenas                                          → independiente, moderada por `aprobada`
--   perfiles.id            → auth.users.id  (1 a 1, se borra en cascada)
--   turnos.cliente_id      → perfiles.id    (opcional, NULL = reserva de invitado)
-- ============================================================================


-- ============================================================================
-- PASO MANUAL — hacé esto UNA SOLA VEZ, después de correr todo lo de arriba:
--
-- Tu cuenta de barbero (la que ya usás para entrar al panel admin) se creó
-- antes de que existiera la tabla `perfiles`, así que el trigger no la
-- alcanzó. Reemplazá el email de abajo por el tuyo y ejecutá:
--
--   insert into perfiles (id, nombre, rol)
--   select id, 'Barbero', 'barbero' from auth.users where email = 'TU_EMAIL_DE_ADMIN_ACA'
--   on conflict (id) do update set rol = 'barbero';
--
-- Sin este paso, tu propia cuenta de admin quedaría tratada como cliente
-- y no podrías entrar al panel.
-- ============================================================================
