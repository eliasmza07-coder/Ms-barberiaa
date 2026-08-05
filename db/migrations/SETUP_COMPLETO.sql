-- ============================================================================
-- SETUP_COMPLETO.sql
--
-- Todo lo necesario en Supabase para el proyecto MS Barbería, en un solo
-- script: contenido editable (CMS), reseñas, el fix de días bloqueados
-- duplicados, y cuentas de cliente opcionales.
--
-- SEGURO DE CORRER MÁS DE UNA VEZ: todo está escrito para no fallar si ya
-- ejecutaste antes 002/003/004 por separado, o si corrés esto dos veces
-- por error. No modifica ni borra ninguna tabla existente (servicios,
-- turnos, dias_libres, horas_bloqueadas, config_jornada) — solo agrega.
--
-- Cómo correrlo: Supabase → tu proyecto → SQL Editor → pegar todo → Run.
-- ============================================================================


-- ============================================================================
-- PARTE 1 — CONTENIDO EDITABLE DEL SITIO (para que administres todo desde
-- el panel: textos, redes, experiencia, galería, FAQ)
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
  color_fondo text default '#0B0B0C',
  color_superficie text default '#18160F',
  color_texto text default '#F3EEE1',
  color_acento text default '#FFFFFF',
  modo_mantenimiento boolean not null default false,
  updated_at timestamptz default now(),
  constraint solo_una_fila check (id = 1)
);
insert into sitio_config (id) values (1) on conflict (id) do nothing;

create table if not exists redes_sociales (
  id bigint generated always as identity primary key,
  plataforma text not null,
  url text not null,
  activo boolean not null default true,
  orden int not null default 0
);

create table if not exists experiencia_items (
  id bigint generated always as identity primary key,
  icono text not null default 'shield-check',
  titulo text not null,
  descripcion text,
  orden int not null default 0,
  activo boolean not null default true
);
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

create table if not exists faq (
  id bigint generated always as identity primary key,
  pregunta text not null,
  respuesta text not null,
  orden int not null default 0,
  activo boolean not null default true
);

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
-- PARTE 2 — RESEÑAS DE CLIENTES + FIX DE DÍAS BLOQUEADOS DUPLICADOS
-- ============================================================================

-- Limpia duplicados si en algún momento se bloqueó/desbloqueó un día
-- varias veces (bug ya corregido en el código, esto limpia datos viejos).
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

alter table turnos add column if not exists cliente_id uuid references perfiles(id);
create index if not exists idx_turnos_cliente on turnos(cliente_id);

alter table perfiles enable row level security;

drop policy if exists "cada uno lee su propio perfil" on perfiles;
create policy "cada uno lee su propio perfil" on perfiles for select using (auth.uid() = id);

drop policy if exists "cada uno edita su propio perfil" on perfiles;
create policy "cada uno edita su propio perfil" on perfiles for update using (auth.uid() = id);

drop policy if exists "el barbero lee todos los perfiles" on perfiles;
create policy "el barbero lee todos los perfiles" on perfiles for select using (
  exists (select 1 from perfiles p where p.id = auth.uid() and p.rol = 'barbero')
);


-- ============================================================================
-- PASO MANUAL — hacé esto UNA SOLA VEZ, después de correr todo lo de arriba:
--
-- Tu cuenta de barbero (la que ya usás para entrar al panel admin) se creó
-- antes de que existiera la tabla `perfiles`, así que el trigger de arriba
-- no la alcanzó. Reemplazá el email de abajo por el tuyo y ejecutá:
--
--   insert into perfiles (id, nombre, rol)
--   select id, 'Barbero', 'barbero' from auth.users where email = 'TU_EMAIL_DE_ADMIN_ACA'
--   on conflict (id) do update set rol = 'barbero';
--
-- Sin este paso, tu propia cuenta de admin quedaría tratada como cliente
-- y no podrías entrar al panel.
-- ============================================================================
