-- ============================================================================
-- 001_future_schema_multi_tenant.sql
--
-- Esquema PROPUESTO a futuro (ver docs/ARCHITECTURE.md, secciones 7 y 12).
-- NO ejecutar directamente sobre la base productiva actual: el código de
-- src/ hoy sigue trabajando contra el esquema documentado en
-- 000_current_schema_reference.sql. Este archivo es el punto de partida
-- para cuando se decida encarar la Fase 1 del plan de migración (crear
-- este esquema en un proyecto Supabase de staging, migrar los datos, y
-- recién después re-apuntar el código).
-- ============================================================================

-- ============ NEGOCIO / CONFIGURACIÓN ============

create table businesses (               -- preparado para multi-tenant a futuro; hoy una sola fila
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);

create table app_settings (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  key text not null,                    -- 'theme' | 'seo' | 'social' | 'business' | 'maintenance'
  value jsonb not null default '{}',
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  updated_by uuid references auth.users(id),
  unique (business_id, key)
);

create table appearance (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  colors jsonb not null default '{}',   -- { ink, gold, bone, ... }
  fonts jsonb not null default '{}',    -- { display, body, mono }
  updated_at timestamptz default now(),
  updated_by uuid references auth.users(id)
);

create table landing_sections (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  key text not null,                    -- 'hero' | 'experiencia' | 'ubicacion' | 'footer'
  content jsonb not null default '{}',
  sort_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  updated_by uuid references auth.users(id),
  unique (business_id, key)
);

-- ============ CATÁLOGO ============

create table categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  name text not null,
  sort_order int default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);

create table services (                 -- reemplaza a "servicios"
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  category_id uuid references categories(id),
  name text not null,
  description text,
  price numeric(12,0) not null,         -- Gs sin decimales
  duration_minutes int not null default 30,
  is_active boolean default true,
  sort_order int default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  deleted_at timestamptz
);
create index idx_services_business on services(business_id) where deleted_at is null;

-- ============ AGENDA / HORARIOS ============

create table business_hours (           -- reemplaza a "config_jornada"
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  fecha date,                           -- null = regla por defecto; con valor = override puntual
  apertura int not null,                -- hora 0-23
  cierre int not null,
  intervalo int not null default 30,    -- minutos
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique (business_id, fecha)
);

create table blocked_dates (            -- reemplaza a "dias_libres"
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  fecha date not null,
  motivo text,
  created_at timestamptz default now(),
  created_by uuid references auth.users(id),
  unique (business_id, fecha)
);

create table blocked_slots (            -- reemplaza a "horas_bloqueadas"
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  fecha date not null,
  hora text not null,                   -- 'HH:MM'
  created_at timestamptz default now(),
  created_by uuid references auth.users(id),
  unique (business_id, fecha, hora)
);
create index idx_blocked_slots_fecha on blocked_slots(business_id, fecha);

-- ============ CLIENTES / RESERVAS ============

create table customers (                -- nuevo: normaliza nombre/teléfono repetidos en reservas
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  name text not null,
  phone text not null,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz,
  unique (business_id, phone)
);

create table reservations (             -- reemplaza a "turnos"
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  customer_id uuid references customers(id),
  service_id uuid references services(id),
  fecha date not null,
  hora text not null,
  estado text not null default 'pendiente',  -- pendiente|confirmada|rechazada|cancelada|finalizada|no_asistio
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  updated_by uuid references auth.users(id),
  deleted_at timestamptz
);
create index idx_reservations_fecha on reservations(business_id, fecha) where deleted_at is null;
create index idx_reservations_estado on reservations(estado);

create table reservation_status_history (  -- nuevo: trazabilidad de cambios de estado
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid references reservations(id),
  from_estado text,
  to_estado text not null,
  changed_by uuid references auth.users(id),
  created_at timestamptz default now()
);

-- ============ CONTENIDO ============

create table gallery (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  media_id uuid references media(id),
  caption text,
  sort_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now(),
  deleted_at timestamptz
);

create table media (                    -- registro de archivos subidos a Supabase Storage
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  bucket text not null,
  path text not null,
  alt_text text,
  created_at timestamptz default now(),
  created_by uuid references auth.users(id)
);

create table faq (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  question text not null,
  answer text not null,
  sort_order int default 0,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table social_links (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  platform text not null,               -- whatsapp|instagram|facebook|tiktok|maps
  url text not null,
  is_active boolean default true,
  unique (business_id, platform)
);

-- ============ SISTEMA ============

create table notifications (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  type text not null,                   -- 'whatsapp_reserva' | 'email' | ...
  payload jsonb not null default '{}',
  status text not null default 'pendiente',
  created_at timestamptz default now()
);

create table audit_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  actor_id uuid references auth.users(id),
  action text not null,                 -- 'reservation.status_changed', 'service.updated', ...
  entity text not null,
  entity_id uuid,
  metadata jsonb default '{}',
  created_at timestamptz default now()
);

create table backups (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id),
  storage_path text not null,
  created_at timestamptz default now()
);


-- ============================================================================
-- Trigger genérico para actualizar `updated_at` automáticamente.
-- Aplicar con un `create trigger` por tabla que tenga esa columna.
-- ============================================================================
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;
