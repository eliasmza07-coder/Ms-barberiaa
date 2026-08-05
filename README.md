# MS Barbería y Peluquería

Landing pública + sistema de reservas + panel administrativo, en JavaScript
puro (ES Modules) con Vite y Supabase. Sin frameworks (React/Vue/Angular).

Este proyecto es el rediseño arquitectónico del `index.html` original de
una sola pieza: **mismo comportamiento, misma base de datos, misma Edge
Function** — reorganizado en capas (`UI → Controllers → Services →
Repositories → Supabase`) y en módulos por feature. El detalle completo de
la arquitectura, el modelo de datos y el plan de migración está en
[`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md).

## Requisitos

- Node.js 18+
- Una cuenta/proyecto de Supabase (ya existe uno en producción; ver `.env.example`)

## Puesta en marcha

```bash
npm install
npm run dev             # levanta Vite en http://localhost:5173
```

No hace falta crear un `.env` para probarlo: `src/config/env.js` ya trae
como *fallback* las mismas credenciales que traía el `index.html` original
(la anon key de Supabase está pensada para ser pública). Si más adelante
querés apuntar a otro proyecto de Supabase (staging, otra barbería), copiá
`.env.example` a `.env` y completá esas variables — tienen prioridad sobre
el fallback.

Build de producción:

```bash
npm run build     # genera dist/
npm run preview   # sirve el build localmente para verificarlo
```

## Estructura

```
src/
  config/        → conexión a Supabase, variables de entorno, constantes
  shared/        → utilidades, repository base, servicios transversales (auth, realtime)
  modules/       → una carpeta por feature: landing, reservations, services-catalog,
                   schedule, auth, admin — cada una con su controller/service/repository
  styles/        → CSS global dividido por responsabilidad (variables, base, animaciones)
db/
  migrations/    → 000 = esquema actual (referencia), 001 = esquema futuro propuesto (NO ejecutar aún)
docs/
  ARCHITECTURE.md → documento completo de arquitectura, DB, convenciones y plan de migración
```

## Base de datos

**Para configurar todo de una sola vez:** corré
`db/migrations/SETUP_COMPLETO.sql` en el SQL Editor de Supabase — junta
las migraciones 002, 003 y 004 en un solo script, es seguro correrlo más
de una vez (no falla si ya ejecutaste algo de esto antes), y no toca
ninguna tabla existente. Los archivos `002_*.sql` a `004_*.sql` se
mantienen por separado solo como referencia histórica de qué se agregó y
cuándo.

El código apunta a las mismas tablas que ya existían en producción:
`servicios`, `turnos`, `dias_libres`, `horas_bloqueadas`, `config_jornada`,
y a la Edge Function `gestionar-reserva` para crear una reserva. Nada de
esto se modificó.

Además, ahora suma 6 tablas de contenido/reseñas y una tabla de perfiles
para que el barbero administre **todo** el sitio desde el panel, sin
depender del programador: `sitio_config`, `redes_sociales`,
`experiencia_items`, `galeria`, `faq`, `resenas` y `perfiles` (cuentas
opcionales de cliente). Están definidas en `db/migrations/002` a `004` —
todas 100% aditivas, no tocan ni borran ninguna tabla existente, y se
pueden correr tal cual sobre la base actual desde el SQL Editor de
Supabase (en orden: 002, 003, 004).

`004_cuentas_clientes.sql` agrega cuentas de cliente **opcionales** en el
flujo de reservas ("Iniciar sesión" / "Crear cuenta" / seguir como
invitado — el invitado sigue funcionando exactamente igual que siempre).
Usa el mismo Supabase Auth que el panel admin, separado por rol
(`perfiles.rol`: `'cliente'` o `'barbero'`) — un cliente que inicia sesión
nunca ve el panel admin. **Requiere un paso manual único** después de
correr la migración: asignarte el rol `'barbero'` a tu cuenta de admin ya
existente (instrucciones al final del archivo SQL).

El esquema ampliado multi-negocio (`reservations`, `services`, `customers`,
etc.) sigue siendo una propuesta a futuro en
`db/migrations/001_future_schema_multi_tenant.sql` — no aplicado, no hace
falta para que el proyecto funcione.

## Diseño

Paleta monocromática blanco y negro (antes: dorado sobre fondo oscuro),
alineada al logo/flyer de la marca. El emblema circular "MS" del navbar es
una reconstrucción vectorial (SVG) inspirada en el logo original — si
tenés el archivo vectorial real del logo (.svg/.ai/.pdf), decímelo y lo
reemplazo por el original en vez de la reconstrucción.

Los colores funcionales del calendario (verde=libre, azul=reservado,
rojo=bloqueado) se mantuvieron a color a propósito — son indicadores de
estado, no parte de la identidad visual, y perderían utilidad en escala de
grises.

## Convenciones

Ver sección 9 de `docs/ARCHITECTURE.md` (nombres de archivos, carpetas,
commits). Regla no negociable: ningún componente de UI ni controller
importa `supabaseClient` directamente — solo los `*.repository.js` (y los
servicios transversales `AuthService`/`RealtimeService`) lo hacen.
