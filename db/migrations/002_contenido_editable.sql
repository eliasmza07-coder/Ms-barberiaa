-- ============================================================================
-- 002_contenido_editable.sql
--
-- Agrega las tablas necesarias para que el barbero administre TODO el sitio
-- desde el panel, sin depender del programador: datos del negocio, redes
-- sociales, tarjetas de "experiencia", galería y preguntas frecuentes.
--
-- Es 100% aditiva: no modifica ni borra ninguna tabla existente
-- (servicios, turnos, dias_libres, horas_bloqueadas, config_jornada).
-- Se puede ejecutar tal cual sobre la base actual en producción.
-- ============================================================================

-- Configuración general del sitio — fila única (id = 1).
-- Cubre todo lo que hoy está escrito fijo en el HTML: textos del hero,
-- del footer, datos de contacto, mapa, y la paleta de colores/logo.
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

-- Redes sociales (WhatsApp, Instagram, Facebook, TikTok, Google Maps...).
create table if not exists redes_sociales (
  id bigint generated always as identity primary key,
  plataforma text not null,       -- 'whatsapp' | 'instagram' | 'facebook' | 'tiktok' | 'maps'
  url text not null,
  activo boolean not null default true,
  orden int not null default 0
);

-- Tarjetas de la sección "Experiencia" (hoy son 3 fijas: Higiene, Sin Esperas, Técnica Clásica).
create table if not exists experiencia_items (
  id bigint generated always as identity primary key,
  icono text not null default 'shield-check',  -- nombre de ícono Lucide
  titulo text not null,
  descripcion text,
  orden int not null default 0,
  activo boolean not null default true
);

-- Galería de fotos del local/trabajos.
create table if not exists galeria (
  id bigint generated always as identity primary key,
  imagen_url text not null,
  descripcion text,
  orden int not null default 0,
  activo boolean not null default true,
  created_at timestamptz default now()
);

-- Preguntas frecuentes.
create table if not exists faq (
  id bigint generated always as identity primary key,
  pregunta text not null,
  respuesta text not null,
  orden int not null default 0,
  activo boolean not null default true
);

-- ============================================================================
-- Datos iniciales (seed) — para que el sitio no se quede vacío la primera vez
-- que se corre esta migración. Coinciden con lo que hoy está escrito fijo
-- en el HTML, así el resultado visual es idéntico apenas se aplica.
-- ============================================================================
insert into experiencia_items (icono, titulo, descripcion, orden) values
  ('shield-check', 'Higiene y Estándar', 'Instrumental esterilizado y productos de barbería premium para el cuidado óptimo de tu piel y cabello.', 1),
  ('clock', 'Sin Esperas', 'Nuestro motor de reserva inteligente calcula exactamente los tiempos para respetar tu agenda al minuto.', 2),
  ('award', 'Técnica Clásica', 'Dominio absoluto en tijera, degradados limpios y afeitado tradicional con toalla caliente.', 3)
on conflict do nothing;

-- Habilitar lectura pública (RLS) de todo lo que el sitio necesita mostrar
-- sin login, y escritura solo para usuarios autenticados (el barbero).
alter table sitio_config enable row level security;
alter table redes_sociales enable row level security;
alter table experiencia_items enable row level security;
alter table galeria enable row level security;
alter table faq enable row level security;

create policy "lectura publica sitio_config" on sitio_config for select using (true);
create policy "escritura autenticados sitio_config" on sitio_config for update using (auth.role() = 'authenticated');

create policy "lectura publica redes_sociales" on redes_sociales for select using (true);
create policy "escritura autenticados redes_sociales" on redes_sociales for all using (auth.role() = 'authenticated');

create policy "lectura publica experiencia_items" on experiencia_items for select using (true);
create policy "escritura autenticados experiencia_items" on experiencia_items for all using (auth.role() = 'authenticated');

create policy "lectura publica galeria" on galeria for select using (true);
create policy "escritura autenticados galeria" on galeria for all using (auth.role() = 'authenticated');

create policy "lectura publica faq" on faq for select using (true);
create policy "escritura autenticados faq" on faq for all using (auth.role() = 'authenticated');
