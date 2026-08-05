# Diagnóstico del sistema actual — MS Barbería v13

Análisis de los 76 archivos del proyecto (~6.300 líneas) **y del esquema
real de la base de datos** antes de tocar nada. Los problemas están ordenados por riesgo real para el negocio, no por
dificultad técnica.

La arquitectura de carpetas es buena: la separación
controller → service → repository está bien hecha y los comentarios
explican decisiones reales. Lo que falla no es el orden del código, sino
**el modelo de datos y la seguridad**. Casi todo lo que sigue nace de la
misma raíz: reglas de negocio que viven en el navegador en vez de en la
base de datos.

---

## 🔴 Críticos — arreglar antes de vender el sistema

### 1. Los datos de todos tus clientes son públicos

`db/SUPABASE_SETUP.sql` activa RLS en `sitio_config`, `redes_sociales`,
`experiencia_items`, `galeria`, `faq`, `resenas` y `perfiles`.

**No lo activa en `turnos` ni en `servicios`.**

Con RLS desactivado, PostgREST expone la tabla completa a la anon key —
que es pública por diseño y está en el bundle de JavaScript
(`src/config/env.js`, línea 17). Cualquiera puede correr:

```
curl "https://TU_PROYECTO.supabase.co/rest/v1/turnos?select=*" -H "apikey: LA_ANON_KEY"
```

y descargar **nombre, teléfono, fecha y hora de todos los clientes que
alguna vez reservaron**. Con `DELETE` o `PATCH` puede además borrar o
alterar la agenda entera. No hace falta ser programador: la key está a la
vista en el navegador.

Además, `FIX_DIAS_LIBRES_RLS.sql` crea esta política:

```sql
create policy "insercion publica dias_libres" on dias_libres
  for insert with check (true);
```

Un visitante anónimo puede insertar días libres y **cerrar la barbería
para siempre** desde la consola del navegador.

→ Resuelto en `007_motor_disponibilidad.sql`, sección 12.

### 2. La doble reserva es posible hoy mismo

No hay ninguna restricción a nivel base de datos: ni `unique(fecha, hora)`,
ni exclusión por solapamiento. La única defensa está en el JavaScript que
pinta la grilla, y en lo que sea que haga la Edge Function
`gestionar-reserva` (que consulta y después inserta: entre esas dos
operaciones entra perfectamente otra reserva).

Dos clientes tocando "Confirmar" con dos segundos de diferencia se llevan
el mismo horario. Con dos pestañas abiertas pasa igual.

→ Resuelto con `EXCLUDE USING gist` + `pg_advisory_xact_lock` en 007/008.

### 3. Bug de zona horaria: el sistema cambia de día a las 21:00

`src/shared/utils/date.utils.js`:

```js
export function hoyISO() {
  return new Date().toISOString().split('T')[0];   // ← UTC
}
```

`toISOString()` devuelve UTC. Paraguay está en UTC-3. Entre las 21:00 y la
medianoche, `hoyISO()` ya devuelve **mañana**. Consecuencias todas las
noches:

- `elFecha.min = hoy` bloquea el día de hoy.
- `esHoy` da `false`, así que **desaparece el filtro de horarios pasados**:
  el sistema ofrece las 09:00 de un día que ya terminó.
- La validación `fecha < hoyStr` de `crearSolicitud()` rechaza reservas
  legítimas para "hoy".

→ Resuelto en `src/shared/utils/datetime.utils.js` (todo se calcula en la
zona horaria del negocio, configurable).

### 4. El cálculo de solapamiento falla con turnos fuera de la grilla

`schedule.service.js`, líneas 52–59:

```js
for (let m = tInicio; m < tInicio + tDuracion; m += jornada.intervalo) {
  turnosOcupadosMinutos.add(minutosAHora(m));   // ← marca STRINGS de hora
}
```

Se marca ocupación comparando **textos** `'09:15'`, no rangos de tiempo. Si
un turno arranca a las 09:10 (cita cargada a mano, o un intervalo que se
cambió después de reservar), marca `09:10`, `09:25`, `09:40` — horas que no
existen en una grilla de 15 minutos. Resultado: **el slot de 09:15 aparece
libre y se puede reservar encima de un turno existente.**

→ Resuelto: el motor nuevo compara rangos (`seSolapan`), no strings. Hay un
test específico para este caso.

### 5. Cancelar borra la fila

`reservations.repository.js` → `liberar(id)` hace `DELETE`. Se pierde:

- el historial (no se puede saber cuántas cancelaciones hubo);
- la trazabilidad de quién canceló y por qué;
- cualquier posibilidad de medir ausencias.

Peor: `revisarEstadoSeguimiento()` **deduce** "cancelado" del hecho de que
la fila ya no existe. Si falla la consulta, el cliente ve "cancelado" sin
que nadie haya cancelado nada.

→ Resuelto: `cambiar_estado_turno()` con máquina de estados; el borrado
físico deja de usarse.


### 5-bis. La base real no coincide con `SUPABASE_SETUP.sql`

Comparando el diagrama de tu proyecto Supabase contra el script del repo
aparecen diferencias que ya están causando errores:

| | `SUPABASE_SETUP.sql` dice | Tu base real tiene | Consecuencia |
|---|---|---|---|
| `servicios.id` | `text primary key` | `int8` (bigint) | **Crear un servicio nuevo desde el panel falla siempre** |
| `config_jornada` | `fecha` es la PK | `id` es la PK, `fecha` con índice único | El `upsert onConflict:'fecha'` depende de ese índice; si se pierde, duplica |
| `turnos.precio` | `numeric` | `int8` | Sin impacto (los guaraníes no tienen decimales) |
| tabla `experiencia` | no existe | existe, duplicada de `experiencia_items` | Confusión: el código lee la otra |
| `sitio_config` | columnas consolidadas | conviven `titulo_hero_1`, `hero_titulo_1` y `hero_titulo` | La PARTE 4 del setup nunca se corrió |

El primero es un bug activo. En `services-catalog.service.js`:

```js
if (!id) payload.id = 'serv_' + Date.now();
```

Un id de texto contra una columna `bigint` devuelve
`invalid input syntax for type bigint` → error 400. Por eso **editar** un
servicio funciona (ahí ya viaja el id numérico que vino de la base) y
**crear** uno nuevo no. `FIX_SERVICIOS_400.sql` atacó la columna `orden`,
que era otro síntoma, pero no la causa.

→ Resuelto en `006_normalizacion_base.sql` (le da una secuencia a la
columna) + los archivos corregidos de `services-catalog`.

---

## 🟠 Importantes — bloquean que esto sea un producto vendible

### 6. El horario laboral se configura fecha por fecha

`config_jornada` tiene `fecha` como primary key, y `apertura`/`cierre` son
**enteros de hora**. Eso implica:

- no existe horario semanal recurrente: hay que cargar cada día a mano, o
  vivir con el default 08–20 de `constants.js`;
- no se puede abrir a las **08:30** (solo horas enteras);
- **no existe la pausa del mediodía**, que en Paraguay es la norma. Hoy el
  sistema ofrece turnos a las 12:30 y a las 13:00 sí o sí.

→ Resuelto: `horarios_semanales` (varias filas por día = jornada partida) +
`excepciones_horario` (feriados, vacaciones por rango, horario especial).

### 7. Un turno = un solo servicio

`turnos` guarda `servicio_nombre text`, `precio`, `duracion_min`. Para
vender "Corte + Barba" hoy hay que crear un servicio combinado a mano — que
es exactamente lo que hay en `SERVICIOS_FALLBACK`. No escala: 5 servicios
sueltos son 26 combinaciones.

→ Resuelto: tabla `turno_servicios`, con nombre y precio congelados al
momento de reservar (así cambiar un precio no reescribe el historial).

### 8. Faltan estados y no hay reglas de transición

Solo existen `pendiente`, `confirmado`, `cancelado`. Sin `en_atencion`,
`finalizado` ni `no_asistio`, no se puede medir facturación real ni
detectar clientes problemáticos.

→ Resuelto: 6 estados + `transicion_valida()`.

### 9. No hay márgenes, ni anticipación mínima, ni límite hacia el futuro

Un cliente puede reservar a las 14:29 para las 14:30. No hay tiempo de
limpieza entre turnos. No hay tope de cuántos meses hacia adelante se
puede reservar.

→ Resuelto: `negocio_config` (`margen_antes_min`, `margen_despues_min`,
`anticipacion_min_min`, `anticipacion_max_dias`, `limite_cancelacion_horas`).

### 10. No hay bloqueo temporal del horario

Dos clientes pueden estar completando el formulario para el mismo horario
al mismo tiempo; uno de los dos va a recibir un error después de escribir
todos sus datos.

→ Resuelto: `reservas_temporales` + `crear_hold()` (5 minutos, expira solo).

### 11. Los bloqueos son de a un slot

`horas_bloqueadas` guarda una hora suelta. Bloquear 14:00–16:00 son 8 clics
y 8 filas. Y si después cambiás el intervalo de 15 a 30 minutos, esos
bloqueos dejan de coincidir con la grilla y **desaparecen**.

→ Resuelto: tabla `bloqueos` con `hora_inicio`/`hora_fin`.

### 12. El turno recién creado se busca por fecha + hora + teléfono

`buscarPorFechaHoraTelefono()` existe porque la Edge Function no devuelve
el id. Es frágil (si hay dos turnos iguales trae cualquiera) y es un agujero
de privacidad: adivinando un teléfono se lee el turno de otra persona.

→ Resuelto: `crear_reserva()` devuelve `turno_id` y un `token_seguimiento`
(uuid). El seguimiento del invitado va por token.

---

## 🟡 Mejoras de producto y mantenimiento

| # | Hallazgo | Dónde |
|---|---|---|
| 13 | `servicios` no tiene `activo`: no se puede desactivar un servicio sin borrarlo | `servicios` |
| 14 | `historialCompleto()` trae **todos** los turnos sin paginar ni limitar | `reservations.repository.js` |
| 15 | Tailwind se carga por CDN (`cdn.tailwindcss.com`), que es una build de desarrollo: pesa de más y no debe usarse en producción | `index.html:10` |
| 16 | Lucide se carga desde `unpkg.com/lucide@latest`: dependencia sin versión fija que puede romper el sitio sin que toques nada | `index.html:70` |
| 17 | `alert()` y `confirm()` en el panel admin | `agenda.controller.js` |
| 18 | Sin `<meta name="description">`, Open Graph ni datos estructurados: el sitio no se comparte bien ni posiciona | `index.html` |
| 19 | No hay página pública de "días de la semana" (paso 2 del flujo pedido): se usa un `<input type="date">` seco | `index.html:338` |
| 20 | No hay recordatorios ni notificaciones de ningún tipo | — |
| 21 | Sin tests de ningún tipo | — |
| 22 | El historial se recarga entero ante cualquier cambio en cualquier tabla | `RealtimeService` |

---

## Lo que ya está bien y conviene no tocar

- Separación por módulos y capas (controller / service / repository).
- `main.js` con arranque tolerante a fallos: si un módulo revienta, el
  resto sigue funcionando.
- El fallback de servicios y de configuración de jornada.
- El CMS (`sitio_config`, `galeria`, `faq`, `redes_sociales`) ya cumple con
  buena parte del requisito "página pública editable sin programador".
- `es_barbero()` como función `SECURITY DEFINER` para evitar la recursión
  de RLS: está bien resuelto y se reutiliza en las políticas nuevas.
