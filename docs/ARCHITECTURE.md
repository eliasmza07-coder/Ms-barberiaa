# Arquitectura Profesional — MS Barbería y Peluquería

**Propuesta de rediseño arquitectónico** | Vanilla JS + Vite + Supabase | Feature-Based / Layered Architecture

> Este documento propone reorganizar el proyecto actual (un único `index.html` de ~1050 líneas, con Tailwind por CDN, Supabase inyectado directamente en el DOM y toda la lógica en funciones globales) hacia una aplicación modular, capaz de crecer 10 años y eventualmente convertirse en un producto multi-tenant. **No se modifica ninguna regla de negocio**: las mismas tablas, los mismos estados, el mismo flujo de reserva. Solo cambia *dónde vive cada cosa* y *cómo se comunican las piezas*.

---

## 0. Diagnóstico del proyecto actual

Del `index.html` analizado se identifican estos bloques de lógica, que son exactamente lo que se va a preservar y reubicar (no reescribir):

| Bloque actual | Función/responsabilidad | Tablas Supabase que toca |
|---|---|---|
| Carga pública de servicios | `cargarServiciosDB`, `renderServiciosCliente`, `poblarSelectServicios` | `servicios` |
| Reserva de turno (cliente) | `cargarHorariosCliente`, `generarBloques`, `seleccionarHora`, `enviarSolicitudReserva` | `turnos`, `dias_libres`, `horas_bloqueadas`, `config_jornada` |
| Tiempo real | `suscribirseRealtime` (postgres_changes) | `turnos` |
| Auth admin | `iniciarSesion`, `cerrarSesionAdmin`, `abrirAdmin` | Supabase Auth |
| Agenda admin | `cargarAgendaAdmin`, `cambiarDiaAdmin`, `toggleDiaCompleto`, `bloquearHora`, `liberarTurno`, `cambiarEstadoTurno`, `abrirPopoverSlot` | `turnos`, `dias_libres`, `horas_bloqueadas`, `config_jornada` |
| CRUD de servicios (admin) | `renderServiciosAdmin`, `abrirModalServicio`, `guardarServicioDB`, `eliminarServicio` | `servicios` |
| Historial | `cargarHistorialGeneral` | `turnos` |
| Utilidades | `formatoGs`, `convertirMinutos`, `minutosAHora` | — |

Esto confirma que hoy el flujo es:

```
HTML (onclick="...") → función global → supabaseClient.from(...) directo
```

Y el objetivo es:

```
UI (componente) → Controller → Service → Repository → Supabase
```

Sin excepción: **ningún componente de UI debe importar `supabaseClient` directamente**.

---

## 1. Árbol completo de carpetas

```
ms-barberia/
├── index.html                          # Shell mínimo: monta layout + carga main.js
├── vite.config.js
├── .env                                 # SUPABASE_URL, SUPABASE_ANON_KEY
├── .env.example
├── package.json
│
├── public/
│   ├── favicon.ico
│   └── robots.txt
│
├── src/
│   ├── main.js                          # Punto de entrada: inicializa app, router simple, layout
│   │
│   ├── config/
│   │   ├── supabaseClient.js            # ÚNICO lugar que crea el cliente Supabase
│   │   ├── env.js                       # Lee variables de entorno (Vite import.meta.env)
│   │   └── constants.js                 # Estados de turno, roles, límites, etc.
│   │
│   ├── shared/
│   │   ├── components/                  # Componentes de UI reutilizables entre módulos
│   │   │   ├── Modal/
│   │   │   │   ├── Modal.js
│   │   │   │   └── modal.css
│   │   │   ├── Toast/
│   │   │   │   ├── Toast.js
│   │   │   │   └── toast.css
│   │   │   ├── Button/
│   │   │   ├── Spinner/
│   │   │   └── Popover/
│   │   │
│   │   ├── services/                    # Servicios transversales (no pertenecen a un solo módulo)
│   │   │   ├── AuthService.js           # login, logout, sesión, onAuthStateChange
│   │   │   ├── RealtimeService.js       # wrapper genérico sobre postgres_changes
│   │   │   ├── NotificationService.js   # WhatsApp links, toasts, futuros emails
│   │   │   └── StorageService.js        # subida de imágenes a Supabase Storage
│   │   │
│   │   ├── repositories/
│   │   │   └── BaseRepository.js        # CRUD genérico (select/insert/update/delete/upsert)
│   │   │
│   │   ├── utils/
│   │   │   ├── date.utils.js            # convertirMinutos, minutosAHora, generarBloques
│   │   │   ├── currency.utils.js        # formatoGs
│   │   │   ├── validators.js            # validación de teléfono, nombre, formularios
│   │   │   └── dom.utils.js             # helpers de render (crear nodos, limpiar listas)
│   │   │
│   │   └── state/
│   │       └── store.js                 # Estado global mínimo (usuario admin, config cacheada)
│   │
│   ├── modules/
│   │   │
│   │   ├── landing/                     # Página pública (marketing)
│   │   │   ├── components/
│   │   │   │   ├── Navbar/
│   │   │   │   ├── Hero/
│   │   │   │   ├── Experiencia/
│   │   │   │   ├── Servicios/           # listado público de servicios
│   │   │   │   ├── Ubicacion/
│   │   │   │   ├── Gallery/
│   │   │   │   ├── FAQ/
│   │   │   │   └── Footer/
│   │   │   ├── landing.controller.js
│   │   │   └── landing.css
│   │   │
│   │   ├── reservations/                # Reservas (cliente)
│   │   │   ├── components/
│   │   │   │   └── ReservationForm/
│   │   │   │       ├── ReservationForm.js
│   │   │   │       └── reservation-form.css
│   │   │   ├── reservations.controller.js
│   │   │   ├── reservations.service.js  # reglas: validar cupo, armar payload, notificar WhatsApp
│   │   │   └── reservations.repository.js  # turnos
│   │   │
│   │   ├── services-catalog/            # Catálogo de servicios (compartido cliente/admin)
│   │   │   ├── services-catalog.service.js
│   │   │   └── services-catalog.repository.js  # servicios
│   │   │
│   │   ├── schedule/                    # Horarios, días libres, bloqueos, config de jornada
│   │   │   ├── schedule.service.js      # generarBloques, disponibilidad
│   │   │   └── schedule.repository.js   # config_jornada, dias_libres, horas_bloqueadas
│   │   │
│   │   ├── auth/                        # Login del panel admin
│   │   │   ├── components/
│   │   │   │   └── LoginModal/
│   │   │   ├── auth.controller.js
│   │   │   └── auth.css
│   │   │
│   │   └── admin/                       # Panel administrativo (privado)
│   │       ├── layouts/
│   │       │   └── AdminLayout/
│   │       │       ├── AdminLayout.js
│   │       │       └── admin-layout.css
│   │       ├── components/
│   │       │   ├── Sidebar/
│   │       │   ├── Calendar/            # grilla diaria/horaria tipo Google Calendar
│   │       │   │   ├── Calendar.js
│   │       │   │   └── calendar.css
│   │       │   ├── Dashboard/
│   │       │   ├── ServiciosAdmin/
│   │       │   ├── Historial/
│   │       │   ├── Clientes/
│   │       │   ├── Contenido/           # editor del CMS
│   │       │   ├── Galeria/
│   │       │   ├── RedesSociales/
│   │       │   ├── Horarios/
│   │       │   ├── SEO/
│   │       │   └── Apariencia/
│   │       ├── admin.controller.js      # orquesta tabs, delega a cada sub-controller
│   │       └── admin.css
│   │
│   ├── layouts/
│   │   └── PublicLayout/                # header + main + footer de la página pública
│   │
│   ├── pages/
│   │   ├── HomePage.js                  # compone landing + reservations
│   │   └── AdminPage.js                 # compone admin (protegida por AuthService)
│   │
│   └── styles/
│       ├── main.css                     # único archivo que se importa en index.html; hace @import del resto
│       ├── variables.css                # tokens: colores (ink/gold/bone), tipografías, spacing
│       ├── base.css                     # reset, scroll-behavior, scrollbar, selection
│       ├── animations.css               # fadeIn, fadeInUp, scaleIn, pulse-slow
│       └── responsive.css               # media queries transversales
│
├── db/
│   ├── migrations/                      # scripts SQL versionados (ver sección 12)
│   └── seed.sql
│
└── docs/
    └── ARCHITECTURE.md                  # este documento, versionado junto al código
```

**Regla de dependencia (de afuera hacia adentro, nunca al revés):**

```
components (UI)  →  controllers  →  services  →  repositories  →  supabaseClient
     ↑                                                    ↓
   nunca                                          único punto de acceso
   importa                                         a Supabase en todo
   supabase                                        el proyecto
```

---

## 2. Organización de módulos (Feature-Based)

Cada carpeta dentro de `modules/` es una *feature* autocontenida:

- Tiene su propio `*.controller.js` (orquesta), `*.service.js` (reglas de negocio) y `*.repository.js` (acceso a datos) cuando aplica.
- Sus componentes de UI viven en `components/` dentro del mismo módulo si son exclusivos de esa feature; si se reutilizan en 2+ módulos, suben a `shared/components/`.
- Un módulo **nunca importa el repository de otro módulo directamente**; si necesita datos de otra feature, pasa por el `service` público de esa feature (ej. `reservations.service.js` puede llamar a `services-catalog.service.js`, pero no a `services-catalog.repository.js`).
- Agregar un módulo nuevo (ej. `inventario/`) implica crear su carpeta con la misma forma; **no se toca ningún archivo existente**, solo se registra su ruta/tab en `admin.controller.js` o en el router de `main.js`.

Esto es lo que garantiza el requisito "agregar módulos sin modificar los existentes": el punto de extensión son *registros* (listas de rutas, listas de tabs), nunca *if/else* dentro de la lógica existente.

---

## 3. Organización del CSS

Un archivo por responsabilidad, cada componente trae el suyo, y `main.css` es el único `<link>` en `index.html`:

```
styles/variables.css      → --color-ink, --color-gold, --color-bone, --font-display, --font-body, --radius, --spacing-*
styles/base.css           → reset, body, scrollbar, texture-noise, selection
styles/animations.css     → @keyframes fadeIn / fadeInUp / scaleIn / pulse
styles/responsive.css     → breakpoints compartidos (si un componente necesita algo muy propio, va en su CSS local)

shared/components/Modal/modal.css
shared/components/Toast/toast.css
shared/components/Button/buttons.css
shared/components/Popover/popover.css

modules/landing/landing.css          → hero, experiencia, ubicación (secciones propias de la landing)
modules/reservations/reservation-form.css
modules/admin/admin.css              → layout general del panel
modules/admin/components/Calendar/calendar.css
modules/auth/auth.css
```

`main.css`:

```css
@import "./variables.css";
@import "./base.css";
@import "./animations.css";
@import "./responsive.css";
/* Vite resuelve los imports de cada componente por su propio JS con `import './x.css'` */
```

Migración concreta: hoy todo el CSS custom está en un `<style>` inline (`texture-noise`, `.card-edge`, `.editorial-frame`, scrollbar, `input[type=date]`). Esto se mueve **tal cual, sin reescribir una sola regla**, a `variables.css` (los colores hoy definidos en `tailwind.config`) y `base.css` (el resto). Tailwind se mantiene igual (vía CDN o, si se decide más adelante, como plugin de Vite) — reorganizar CSS no implica abandonar Tailwind, solo dejar de tener utilidades y CSS custom mezclados en un único bloque gigante.

---

## 4. Organización del JavaScript

Cuatro capas, cada una con una única responsabilidad:

### 4.1 UI / Componentes
Renderizan HTML y capturan eventos. **No llaman a Supabase.** No contienen reglas de negocio (ej. no deciden si un horario está disponible, solo pintan lo que el controller les da).

```js
// modules/reservations/components/ReservationForm/ReservationForm.js
export function renderReservationForm(container, { servicios, onSubmit }) { ... }
```

### 4.2 Controllers
Uno por módulo. Escuchan eventos de la UI, llaman a los services, y le devuelven el resultado a la UI (loading, error, éxito). Reemplazan a las funciones sueltas como `enviarSolicitudReserva`, `cambiarTabAdmin`.

```js
// modules/reservations/reservations.controller.js
import { crearReserva } from './reservations.service.js';

export async function handleEnviarReserva(formData) {
  try {
    await crearReserva(formData);
    // notifica a la UI (toast, cierre de modal)
  } catch (e) {
    // notifica error a la UI
  }
}
```

### 4.3 Services
Contienen las reglas de negocio: validar disponibilidad, calcular bloques horarios (`generarBloques`), decidir si un día está bloqueado, armar el link de WhatsApp. No conocen Supabase directamente, solo su Repository.

```js
// modules/reservations/reservations.service.js
import { reservationsRepository } from './reservations.repository.js';
import { scheduleService } from '../schedule/schedule.service.js';

export async function crearReserva({ servicioId, fecha, hora, nombre, telefono }) {
  const disponible = await scheduleService.horaDisponible(fecha, hora);
  if (!disponible) throw new Error('Horario ya no disponible');
  return reservationsRepository.crear({ servicioId, fecha, hora, nombre, telefono, estado: 'pendiente' });
}
```

### 4.4 Repositories
Único lugar donde aparece `supabaseClient.from(...)`. Un repository por tabla (o por agregado de tablas muy relacionadas). Extienden `BaseRepository` para no repetir CRUD.

```js
// shared/repositories/BaseRepository.js
import { supabaseClient } from '../../config/supabaseClient.js';

export class BaseRepository {
  constructor(table) { this.table = table; }
  async findAll(query = {}) { return supabaseClient.from(this.table).select(query.select ?? '*'); }
  async findById(id) { return supabaseClient.from(this.table).select('*').eq('id', id).maybeSingle(); }
  async create(payload) { return supabaseClient.from(this.table).insert(payload); }
  async update(id, payload) { return supabaseClient.from(this.table).update(payload).eq('id', id); }
  async upsert(payload, opts) { return supabaseClient.from(this.table).upsert(payload, opts); }
  async remove(id) { return supabaseClient.from(this.table).delete().eq('id', id); }
}
```

```js
// modules/reservations/reservations.repository.js
import { BaseRepository } from '../../shared/repositories/BaseRepository.js';

class ReservationsRepository extends BaseRepository {
  constructor() { super('reservations'); }
  async porFecha(fecha) {
    return this.client.from(this.table).select('*').eq('fecha', fecha).neq('estado', 'cancelado');
  }
}
export const reservationsRepository = new ReservationsRepository();
```

Con esto, `suscribirseRealtime` pasa a vivir en `shared/services/RealtimeService.js` como un wrapper genérico, y cada módulo lo usa suscribiéndose solo a su tabla, sin repetir la lógica de canal.

---

## 5. Organización del CMS

Objetivo: nada de texto queda "hardcodeado" en HTML. Todo sale de tablas editables desde `admin/components/Contenido`.

- **`landing_sections`**: cada sección de la home (hero, experiencia, ubicación, footer) es una fila con un `key` único (`hero`, `experiencia`, `ubicacion`, `footer`) y un `content JSONB` con los campos propios de esa sección (título, subtítulo, texto, textos de botones, imagen).
- **`app_settings`**: configuración global no seccional (nombre del negocio, logo, favicon, WhatsApp, modo mantenimiento) también en JSONB, agrupado por clave (`theme`, `seo`, `social`, `business`).
- **`services`**, **`gallery`**, **`faq`**, **`social_links`**: ya son entidades con forma propia (no ameritan JSONB, van en columnas).

El módulo `landing` en runtime hace: `landingContentService.getSection('hero')` → repository lee `landing_sections` → controller inyecta esos datos al componente `Hero`. Si mañana se agrega un campo nuevo al hero, se agrega una clave dentro del JSONB — **no se migra la tabla**.

Esto también resuelve "el cliente debe poder modificar colores/fuentes sin tocar código": la tabla `appearance` (o la clave `theme` de `app_settings`) guarda los valores que hoy están fijos en `tailwind.config` (`ink`, `gold`, `bone`, fuentes `Cormorant Garamond` / `Jost`), y `variables.css` los aplica vía `:root { --color-gold: var(--from-db) }` seteado en runtime por un pequeño script de arranque (`applyTheme.js`), sin recompilar nada.

---

## 6. Organización del Panel Admin

El admin deja de ser 3 tabs (Agenda, Servicios, Historial) para ser un layout con sidebar y secciones registradas (agregar una sección nueva = agregar una entrada al arreglo, no tocar el layout):

```
Dashboard      → métricas rápidas (turnos hoy, pendientes, ingresos del mes)
Agenda         → Calendar.js (grilla horaria) — hoy: cargarAgendaAdmin, toggleDiaCompleto, bloquearHora, cambiarEstadoTurno
Servicios      → ServiciosAdmin.js — hoy: renderServiciosAdmin, guardarServicioDB, eliminarServicio
Clientes       → nuevo: listado derivado de reservations (nombre/teléfono únicos), sin tabla propia al inicio
Configuración  → Horarios (config_jornada → business_hours) + datos de contacto
Contenido      → editor de landing_sections y app_settings (CMS)
Galería        → CRUD sobre `gallery` + subida a Supabase Storage
Redes Sociales → CRUD sobre `social_links`
Horarios       → business_hours, blocked_dates, blocked_slots
SEO            → campos meta (título, descripción, og:image) dentro de app_settings.seo
Apariencia     → colores/fuentes (appearance)
Historial      → cargarHistorialGeneral, ahora paginado
```

`admin.controller.js` mantiene un registro simple:

```js
const ADMIN_SECTIONS = [
  { key: 'dashboard', label: 'Dashboard', render: renderDashboard },
  { key: 'agenda', label: 'Agenda', render: renderAgenda },
  // agregar una fila acá == agregar una sección al panel
];
```

Esto reemplaza el `cambiarTabAdmin(tab)` con `if/else` por un `switch` implícito basado en datos, que es lo que permite crecer sin tocar lo existente.

---

## 7. Modelo completo de base de datos

Convenciones aplicadas a **todas** las tablas: `id UUID DEFAULT gen_random_uuid() PRIMARY KEY`, `created_at`, `updated_at` (con trigger), `created_by`, `updated_by` (referencian `auth.users`), `deleted_at` (soft delete), índices en toda FK y en columnas de búsqueda frecuente (`fecha`, `estado`, `key`).

```sql
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
```

**Trigger genérico para `updated_at`** (se aplica a cada tabla con esa columna, una sola función reutilizada):

```sql
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_services_updated_at before update on services
  for each row execute function set_updated_at();
-- (repetir por tabla)
```

---

## 8. Relaciones entre tablas

```
businesses (1) ───< app_settings, appearance, landing_sections, categories, services,
                     business_hours, blocked_dates, blocked_slots, customers, reservations,
                     gallery, media, faq, social_links, notifications, audit_logs, backups

categories (1) ───< services

customers (1) ───< reservations

services (1) ───< reservations

reservations (1) ───< reservation_status_history

media (1) ───< gallery

auth.users (1) ───< audit_logs (actor_id)
auth.users (1) ───< reservation_status_history (changed_by)
auth.users (1) ───< *.created_by / *.updated_by (todas las tablas administrables)
```

`business_id` está presente en prácticamente todas las tablas a propósito: aunque hoy solo existe **una fila** en `businesses` (MS Barbería), este campo es lo que permite en el futuro convertir el producto en multi-tenant sin rediseñar el esquema — solo agregando filas a `businesses` y filtrando por ese id (con Row Level Security de Supabase).

---

## 9. Convenciones de nombres

**Base de datos:** tablas en plural, `snake_case`, en inglés (`reservations`, no `turnos`) para consistencia con el resto del ecosistema Supabase/PostgreSQL; columnas `snake_case`; claves foráneas `<tabla_singular>_id`.

**JavaScript:** archivos en `kebab-case.tipo.js` (`reservations.service.js`), componentes en `PascalCase/ComponentName.js`, funciones y variables en `camelCase`, constantes globales en `UPPER_SNAKE_CASE` (`RESERVATION_STATUS.PENDIENTE`).

**CSS:** clases utilitarias vienen de Tailwind; clases custom en `kebab-case` con prefijo de componente cuando aplica (`.calendar-slot`, `.card-edge`).

**Carpetas:** `modules/<feature-en-kebab-case>/`, siempre con subcarpetas `components/`, y archivos `feature.controller.js`, `feature.service.js`, `feature.repository.js`.

**Git / commits:** `feat(reservations): ...`, `fix(admin): ...`, `refactor(schedule): ...` — Conventional Commits, útil para changelog automático a 10 años.

---

## 10. Flujo completo de datos (ejemplo: reserva de turno)

```
1. Usuario abre #reservas → ReservationForm (UI) pide servicios
2. ReservationForm → reservations.controller.js → services-catalog.service.js
   → services-catalog.repository.js → supabaseClient.from('services') → Supabase
3. Usuario elige fecha → reservations.controller.js → schedule.service.js
   (combina business_hours + blocked_dates + blocked_slots + reservations del día)
   → schedule.repository.js → Supabase → UI pinta el grid de horarios
4. Usuario elige hora y confirma → ReservationForm dispara evento
   → reservations.controller.js.handleEnviarReserva(formData)
   → reservations.service.js.crearReserva()
       a. valida disponibilidad vía schedule.service.js
       b. busca o crea customer vía customers.service.js
       c. inserta en reservations.repository.js (estado: 'pendiente')
       d. dispara NotificationService (link de WhatsApp al barbero)
   → controller informa éxito → UI muestra Toast
5. RealtimeService (suscrito a 'reservations') notifica a cualquier cliente
   con el formulario abierto que ese slot ya no está libre → UI re-renderiza el grid
6. Admin entra a Agenda → Calendar.js pide reservations del día vía
   reservations.service.js → repository → Supabase, pinta la grilla por estado
7. Admin confirma/rechaza → mismo controller → reservations.service.js.cambiarEstado()
   → actualiza reservations + inserta fila en reservation_status_history
   → RealtimeService notifica al cliente si sigue con la página abierta
```

Ningún paso de este flujo cambia respecto al comportamiento actual: **es el mismo recorrido**, solo con nombres de capa explícitos en vez de funciones sueltas en el `<script>` global.

---

## 11. Buenas prácticas aplicadas

- **SRP**: cada archivo hace una sola cosa (un componente pinta, un service decide, un repository persiste).
- **DRY**: `BaseRepository` elimina la repetición de `select/insert/update/delete` que hoy se repite en cada función; `RealtimeService` elimina repetir la suscripción a canales.
- **KISS/YAGNI**: no se agregan tablas ni módulos que el negocio no pidió (inventario, facturación, empleados quedan documentados como *extensión futura*, no implementados).
- **Repository Pattern**: aísla Supabase; si el día de mañana se migra de proveedor, solo cambian los repositories.
- **Service Pattern**: centraliza reglas de negocio, testeable sin DOM y sin red (se puede mockear el repository).
- **Composición sobre herencia** en componentes de UI: reciben `props` (datos + callbacks), no acceden a estado global salvo lo mínimo en `shared/state/store.js`.
- **Feature flags simples** vía `app_settings.maintenance` para modo mantenimiento sin tocar código.
- **Row Level Security** en Supabase: público solo lee (`services`, `landing_sections`, etc. activos) e inserta en `reservations`/`customers`; solo `auth.users` autenticado (el barbero) puede actualizar/eliminar.

---

## 12. Plan de migración desde el proyecto actual

Migración incremental, **sin downtime funcional**, en fases pequeñas y verificables:

**Fase 0 — Setup del proyecto**
1. Crear proyecto Vite (`npm create vite@latest` con template vanilla).
2. Crear estructura de carpetas de la sección 1 (vacía).
3. Mover el `<script>` de Supabase a `config/supabaseClient.js`, `config/env.js` con variables de `.env`.

**Fase 1 — Base de datos**
4. Escribir migraciones SQL (sección 7) en un proyecto Supabase **de staging**.
5. Script de migración de datos: `servicios→services`, `turnos→reservations` (+ crear `customers` a partir de nombre/teléfono únicos), `dias_libres→blocked_dates`, `horas_bloqueadas→blocked_slots`, `config_jornada→business_hours`. Todo bajo una única `business_id` (MS Barbería).
6. Verificar en staging que los conteos y datos cuadran 1 a 1 con las tablas viejas.

**Fase 2 — Capa de datos (repositories)**
7. Crear `BaseRepository` y un repository por tabla nueva.
8. No tocar todavía la UI: se puede probar cada repository desde la consola del navegador.

**Fase 3 — Services**
9. Extraer la lógica de `generarBloques`, `convertirMinutos`, `minutosAHora`, `formatoGs` a `utils/`.
10. Crear `schedule.service.js`, `reservations.service.js`, `services-catalog.service.js` moviendo la lógica de negocio hoy embebida en las funciones globales, **verbatim**, solo reubicada.

**Fase 4 — UI pública**
11. Migrar sección por sección (Navbar, Hero, Servicios, Ubicación, ReservationForm) a componentes, conectados a sus controllers. Comparar visualmente contra el `index.html` original en cada paso.

**Fase 5 — Auth + Admin**
12. Migrar login (`iniciarSesion`/`cerrarSesionAdmin`) a `auth` module.
13. Migrar Agenda, Servicios, Historial a componentes del `admin` module, reemplazando `cambiarTabAdmin` por el registro de secciones.

**Fase 6 — CMS**
14. Cargar `landing_sections` y `app_settings` con el contenido que hoy está fijo en el HTML (textos del hero, footer, etc.).
15. Conectar la UI pública a esas tablas en vez de texto fijo.
16. Construir el editor de Contenido en el admin.

**Fase 7 — Corte**
17. Apuntar el dominio de producción al nuevo build de Vite.
18. Mantener el `index.html` viejo respaldado por 30 días por si hay que hacer rollback.
19. Monitorear `audit_logs`/errores de consola la primera semana.

Cada fase es un PR independiente, revisable y revertible — a diferencia de un "big bang rewrite".

---

## 13. Recomendaciones para mantener el proyecto durante 10 años

1. **No romper la regla de capas**: cualquier PR que importe `supabaseClient` fuera de un `*.repository.js` debe rechazarse en code review.
2. **`docs/ARCHITECTURE.md` vivo**: cada módulo nuevo se documenta acá antes de mergear, no después.
3. **Versionar el esquema de base de datos** (`db/migrations/`) igual que el código — nunca cambios manuales directos en el dashboard de Supabase en producción.
4. **Tests de service, no de UI**: al estar los services desacoplados del DOM, priorizar tests unitarios sobre `*.service.js` (son los que contienen las reglas que más cuestan de recuperar si se rompen).
5. **JSONB con disciplina**: cada clave nueva dentro de un `content`/`value` JSONB se documenta en `ARCHITECTURE.md` con su forma esperada, para que no se vuelva un cajón de sastre.
6. **`business_id` desde el día uno**: aunque hoy hay un solo negocio, nunca se debe escribir una query sin filtrar por `business_id` — es lo que evita una migración dolorosa el día que haya una segunda barbería.
7. **Revisar dependencias del CDN**: Tailwind y Lucide por CDN son válidos hoy; si el proyecto crece, evaluar pasarlos a dependencias de Vite (`npm i -D tailwindcss`) para tener build reproducible y offline, sin cambiar ninguna clase existente.
8. **Changelog por versión** (`CHANGELOG.md`) usando los commits convencionales de la sección 9 — a 10 años, saber *cuándo y por qué* cambió cada regla vale más que el código mismo.
9. **Revisión anual de arquitectura**: una vez al año, verificar que ningún módulo haya empezado a "filtrarse" en otro (import cruzado de repositories, lógica de negocio colada en componentes).
10. **Backups reales**: la tabla `backups` es un registro, no un backup en sí — configurar backups automáticos de Supabase (point-in-time recovery) desde el día del corte a producción.
