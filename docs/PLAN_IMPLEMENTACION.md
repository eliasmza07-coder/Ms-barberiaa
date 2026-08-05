# Plan de implementación

Cómo instalar lo que está en esta entrega, y qué queda por hacer después.

---

## Qué incluye esta entrega

| Archivo | Qué hace |
|---|---|
| `db/migrations/005_preflight_verificacion.sql` | **Solo lectura.** Radiografía de tu base antes de tocarla |
| `db/migrations/006_normalizacion_base.sql` | Arregla las diferencias entre tu base real y el código (incluye el bug de creación de servicios) |
| `db/migrations/007_motor_disponibilidad.sql` | Modelo de agenda nuevo, estados, anti-doble-reserva, **RLS sobre `turnos`** |
| `db/migrations/008_funciones_reserva.sql` | Validación y creación de reservas del lado del servidor (RPC) |
| `db/migrations/009_limpieza_opcional.sql` | Higiene. Es el único que borra cosas; no es obligatorio |
| `src/modules/services-catalog/*.js` | Versión corregida (arregla el error 400 al crear servicios) |
| `src/shared/utils/datetime.utils.js` | Fechas y horas en la zona del negocio (reemplaza `hoyISO()`) |
| `src/modules/availability/availability.engine.js` | Motor de disponibilidad — función pura, sin I/O |
| `src/modules/availability/availability.repository.js` | Acceso a los datos vía RPC (sin exponer clientes) |
| `src/modules/availability/availability.service.js` | Orquestación + adaptador compatible con el código actual |
| `test/availability.engine.test.js` | 18 tests con los casos borde del pliego |

Nada de esto borra ni renombra lo que ya existe. Las tablas viejas
(`config_jornada`, `dias_libres`, `horas_bloqueadas`) siguen en su lugar y
sus datos se copian al modelo nuevo, así que podés volver atrás.

---

## Instalación, en orden

### Paso 0 — Backup y staging

En Supabase: **Database → Backups → Create backup**. Después duplicá el
proyecto (o creá uno nuevo y corré `SUPABASE_SETUP.sql`) para probar ahí
primero. Las migraciones tocan RLS: si algo sale mal en producción, el
sitio deja de mostrar horarios.

### Paso 1 — Radiografía (no modifica nada)

SQL Editor → pegar `005_preflight_verificacion.sql` → Run. Devuelve una
tabla de chequeos ordenada por gravedad. Guardá el resultado.

Si aparece `PROBLEMA` en **"hay al menos un usuario con rol barbero"**,
resolvelo antes de seguir: cuando se active RLS, sin ese rol nadie va a
poder administrar los turnos. La consulta C del final del archivo lo
arregla.

### Paso 2 — Correr las migraciones

En orden, una por una, verificando que cada una termine sin error:

1. `006_normalizacion_base.sql` — empareja tu base con lo que el código
   asume. Acá se arregla, entre otras cosas, el bug que impide crear
   servicios nuevos desde el panel.
2. `007_motor_disponibilidad.sql` — el modelo nuevo + RLS.
3. `008_funciones_reserva.sql` — las funciones de reserva.

Volvé a correr `005_preflight_verificacion.sql` después: todos los
`PROBLEMA` tienen que haber pasado a `OK`.

Si al final aparece un `WARNING: NO se pudo crear turnos_sin_solapamiento`,
es porque ya tenés turnos superpuestos cargados. Corré la consulta 13.a del
final del archivo 007, resolvé esos turnos a mano y volvé a correr el
script.

### Paso 3 — Verificar que el agujero de seguridad se cerró

Desde una terminal, con tu anon key real:

```bash
curl "https://TU_PROYECTO.supabase.co/rest/v1/turnos?select=*" -H "apikey: TU_ANON_KEY"
```

- **Antes:** devuelve todos tus clientes con nombre y teléfono.
- **Después:** tiene que devolver `[]`.

Si sigue devolviendo datos, RLS no quedó activo: revisá la consulta 13.c del archivo 007.

### Paso 4 — Cargar tu horario real

La migración deja un horario por defecto (lunes a sábado, 08–12 y 14–20).
Ajustalo a tu realidad:

```sql
delete from horarios_semanales;
insert into horarios_semanales (dia_semana, hora_inicio, hora_fin) values
  (1, '08:00', '12:00'), (1, '14:00', '20:00'),   -- lunes
  (2, '08:00', '12:00'), (2, '14:00', '20:00'),
  (3, '08:00', '12:00'), (3, '14:00', '20:00'),
  (4, '08:00', '12:00'), (4, '14:00', '20:00'),
  (5, '08:00', '12:00'), (5, '14:00', '21:00'),   -- viernes hasta más tarde
  (6, '08:00', '16:00');                          -- sábado corrido
```

Y revisá la configuración general:

```sql
update negocio_config set
  intervalo_slot_min    = 15,
  margen_despues_min    = 5,
  anticipacion_min_min  = 30,
  anticipacion_max_dias = 60,
  limite_cancelacion_horas = 3;
```

### Paso 5 — Enchufar el motor nuevo en el front-end

Copiá los archivos de `src/` a tu proyecto y cambiá **una línea** en
`src/modules/reservations/reservations.controller.js`:

```js
// import { ScheduleService } from '../schedule/schedule.service.js';
import { AvailabilityService as ScheduleService } from '../availability/availability.service.js';
```

El adaptador `calcularDisponibilidadCliente(fecha, duracion)` devuelve la
misma forma de siempre, así que la grilla sigue funcionando igual — pero
ahora con jornada partida, márgenes, anticipación y zona horaria correcta.
Si algo falla, descomentás la línea vieja y volvés al estado anterior.

### Paso 6 — Cambiar la creación de la reserva

En `reservations.service.js`, reemplazar la llamada a la Edge Function por:

```js
import { availabilityRepository } from '../availability/availability.repository.js';

async crearSolicitud({ fecha, hora, nombre, telefono, servicios, comentario, holdId }) {
  const r = await availabilityRepository.crearReserva({
    fecha, hora, nombre, telefono,
    servicios: servicios.map((s) => s.id),
    comentario, holdId,
  });
  if (!r.ok) throw new Error(r.mensaje || 'No pudimos tomar la reserva.');
  return r;   // { turno_id, token, estado, precio_total, ... }
}
```

Guardá `r.token` en localStorage en vez del objeto armado a mano, y usá
`turno_por_token(token)` para el seguimiento. Con esto se puede borrar
`buscarPorFechaHoraTelefono()`.

La Edge Function `gestionar-reserva` puede quedar como está durante la
transición, pero conviene reescribirla para que llame a `crear_reserva()`,
o eliminarla: ya no aporta nada que la función de base no haga mejor.

### Paso 7 — Correr los tests

```bash
node --test "test/*.test.js"
```

Los 18 tests tienen que pasar. Agregá uno cada vez que aparezca un caso
raro en producción: es la forma más barata de que no vuelva.

---

## Roadmap de lo que falta

Ordenado por relación valor / esfuerzo. La base de datos ya soporta todo
esto: lo que falta es interfaz.

### Fase A — Flujo de reserva (1–2 semanas)

1. **Paso 1 multi-servicio.** Tarjetas con checkbox en vez de selección
   única. Mostrar arriba el acumulado: "Corte + Barba · 50 min · Gs 65.000".
   `resumenServicios()` ya calcula duración, precio y márgenes.
2. **Paso 2: tira de días.** Reemplazar el `<input type="date">` por los
   próximos 14 días con su estado. `AvailabilityService.resumenDias()`
   devuelve exactamente eso (`disponible` / `sin_cupo` / `cerrado`) en una
   sola consulta.
3. **Paso 3: solo horarios posibles.** Ya funciona con el motor nuevo.
   Agrupar visualmente en Mañana / Tarde.
4. **Hold al elegir horario.** Llamar a `crear_hold()` al seleccionar y
   mostrar un contador: "Te guardamos este horario por 5:00". Al enviar,
   pasar el `holdId` a `crear_reserva()`.
5. **Comentario opcional** en el paso 4 (la columna `comentario` ya existe).

### Fase B — Panel del barbero (2–3 semanas)

6. **Dashboard con la información que importa:** próxima cita con nombre y
   hora, pendientes por confirmar, ingresos estimados del día
   (`sum(precio) where estado in ('confirmado','finalizado')`).
7. **Acciones rápidas por cita:** Confirmar / En atención / Finalizar /
   No asistió / Reprogramar / WhatsApp. Todo vía `cambiar_estado_turno()`
   y `reprogramar_turno()`; la máquina de estados ya impide combinaciones
   inválidas, así que la UI solo tiene que mostrar los botones válidos.
8. **Vista semana y vista mes.** La vista día actual (lista de slots) no
   escala: con intervalo de 15 minutos son 48 filas para ver 6 citas.
   Conviene una agenda por bloques donde cada cita ocupe su alto real.
9. **Crear cita manual** con `origen: 'local'` — el barbero puede saltear
   la anticipación mínima, pero **no** el control de solapamiento.
10. **Editor de horario semanal y vacaciones** con interfaz, en vez de SQL.
11. **Ficha de cliente:** historial, servicios usados, faltas. La tabla
    `clientes` ya se mantiene sola con triggers.
12. Reemplazar `alert()` / `confirm()` por modales del sistema de diseño.

### Fase C — Notificaciones (1 semana)

13. Tabla `notificaciones` (evento, canal, destinatario, estado, programada_para)
    + Edge Function con cron cada 15 minutos.
14. Eventos: nueva reserva → al barbero; confirmación / cancelación /
    reprogramación → al cliente; recordatorio 24 h y 2 h antes.
15. Canal 1: WhatsApp con link `wa.me` prearmado (ya está `whatsapp.utils.js`).
    Canal 2: email por Resend. Push más adelante.

### Fase D — Producción y multi-negocio

16. Sacar Tailwind del CDN: instalarlo como dependencia y compilarlo con
    Vite. Fijar la versión de Lucide (ya está en `package.json`, solo hay
    que importarla en vez de usar el `<script>` de unpkg).
17. SEO: meta description, Open Graph, `LocalBusiness` en JSON-LD, sitemap.
18. Paginar el historial.
19. Multi-negocio: `negocio_id` ya está en todas las tablas nuevas. Falta
    resolver el negocio por subdominio o slug y sumarlo a las políticas RLS.
20. Múltiples empleados: tabla `empleados` + `empleado_id` en `turnos` y en
    `horarios_semanales`. El motor no cambia — se ejecuta una vez por
    empleado y se unen los resultados.

---

## Decisiones de diseño, para el próximo que toque esto

**Por qué el motor es una función pura.** `availability.engine.js` no
consulta la base ni lee el reloj: todo entra por parámetro. Así se pueden
testear las 18 reglas en 400 ms, sin base de datos y sin esperar a que sean
las 14:20 para probar la anticipación mínima.

**Por qué la validación está duplicada (JS y SQL).** No es duplicación por
descuido. El motor de JS existe para la experiencia: no mostrar horarios
imposibles. `validar_slot()` existe para la seguridad: cualquiera puede
llamar a la API sin pasar por tu página. La regla es simple — el navegador
decide **qué se muestra**, la base decide **qué se acepta**.

**Por qué los márgenes no se suman entre servicios.** Corte (5 min de
limpieza) + Barba (5 min) no son 10: se limpia una vez al final. El motor
toma el máximo, no la suma.

**Por qué la ocupación se lee con una función y no con un SELECT.**
Para pintar la grilla, el navegador solo necesita saber *que* un rango está
ocupado, no *quién* lo ocupa. `ocupacion_rango()` devuelve horarios pelados.
Es lo que permite tener RLS estricto en `turnos` sin romper la página
pública.
