# MS Barbería — paquete de mejoras v14

Entrega modular sobre el proyecto `ms-barberia-v13`. **No reemplaza nada**:
son archivos nuevos que se copian sobre el proyecto existente, más
migraciones SQL que se corren en orden.

Todo está adaptado al esquema **real** de tu base de datos (el del diagrama
de Supabase), que en varios puntos no coincide con `db/SUPABASE_SETUP.sql`.

---

## Empezá acá

1. Leé `docs/DIAGNOSTICO.md` — qué está mal hoy y por qué.
2. Seguí `docs/PLAN_IMPLEMENTACION.md` — los 7 pasos de instalación.

Lo más urgente: **la tabla `turnos` no tiene RLS activo**. Cualquiera con la
anon key (que está en el bundle de JavaScript de tu página) puede
descargarse el nombre y el teléfono de todos tus clientes, o borrar la
agenda. Se arregla en el paso 2.

---

## Contenido

```
db/                                ← PARA PEGAR EN EL SQL EDITOR DE SUPABASE
  1. SUPABASE_VERIFICAR.sql        Solo lectura. Radiografía de tu base. Correr PRIMERO.
  2. SUPABASE_INSTALAR_TODO.sql    Todo el sistema, en un solo bloque. Idempotente.
  3. SUPABASE_CONFIGURAR.sql       TUS horarios y TUS reglas. Editar antes de correr.
  4. SUPABASE_VERIFICAR_POST.sql   Solo lectura. Confirma que quedó todo bien.

db/migrations/                     ← lo mismo, separado por si preferís ir de a poco
  005_preflight_verificacion.sql   = SUPABASE_VERIFICAR.sql
  006_normalizacion_base.sql       Empareja tu base real con lo que el código asume.
  007_motor_disponibilidad.sql     Modelo de agenda nuevo + estados + RLS + anti-doble-reserva.
  008_funciones_reserva.sql        Validación y creación de reservas en el servidor (RPC).
  009_limpieza_opcional.sql        Higiene. El único que borra cosas. NO es obligatorio.
  (006 + 007 + 008 = SUPABASE_INSTALAR_TODO.sql)

src/
  shared/utils/datetime.utils.js               Fechas en la zona horaria del negocio.
  modules/availability/availability.engine.js  Motor de disponibilidad (función pura).
  modules/availability/availability.repository.js
  modules/availability/availability.service.js Orquestación + adaptador compatible.
  modules/services-catalog/*.js                Versión corregida (arregla el error 400).

test/
  availability.engine.test.js      18 tests con los casos borde del pliego.

docs/
  DIAGNOSTICO.md                   Los 22 hallazgos, ordenados por riesgo real.
  PLAN_IMPLEMENTACION.md           Instalación paso a paso + roadmap de lo que falta.
```

---

## Correr los tests

No hace falta instalar nada: usa el runner nativo de Node (v18+).

```bash
cd ms-barberia-v14
npm test
```

Los 18 tests tienen que pasar. Cubren jornada partida, márgenes de
limpieza, servicios combinados, anticipación mínima, horarios pasados,
zona horaria y solapamiento con citas fuera de la grilla.

---

## Orden de aplicación, resumido

```
BACKUP
  → SUPABASE_VERIFICAR.sql       (leer el reporte, resolver los PROBLEMA)
  → SUPABASE_INSTALAR_TODO.sql   (una sola pegada)
  → SUPABASE_CONFIGURAR.sql      (editado con tus horarios)
  → SUPABASE_VERIFICAR_POST.sql  (todo tiene que decir OK)
  → curl con la anon key         (tiene que devolver [])
  → copiar src/ al proyecto
  → migrations/009               (opcional, semanas después)
```

El instalador tiene un **candado**: si no hay ningún usuario con rol
`barbero`, corta la ejecución antes de activar RLS y te dice exactamente
qué correr. Sin ese freno, activar la seguridad te dejaría afuera de tu
propio panel.

Ningún script borra datos salvo el 009, que está claramente marcado y se
puede saltear indefinidamente.
