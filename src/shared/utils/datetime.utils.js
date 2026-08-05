/**
 * shared/utils/datetime.utils.js
 *
 * Reemplaza a hoyISO() de date.utils.js, que usaba toISOString() y por lo
 * tanto devolvía la fecha en UTC. En Paraguay (UTC-3) eso significa que
 * todos los días entre las 21:00 y la medianoche el sistema creía que ya
 * era "mañana": ocultaba los turnos de la noche de hoy y dejaba reservar
 * horarios ya pasados. Acá todo se calcula explícitamente en la zona
 * horaria del negocio (configurable en `negocio_config.zona_horaria`).
 *
 * Ninguna función de este archivo depende del reloj del navegador para
 * decidir reglas de negocio: el instante viene de afuera y la zona
 * horaria también, así que es 100% testeable.
 */

export const ZONA_POR_DEFECTO = 'America/Asuncion';

/**
 * Devuelve la fecha (YYYY-MM-DD) y los minutos transcurridos del día en la
 * zona horaria indicada, para un instante dado.
 * @returns {{ fecha: string, minutos: number, diaSemana: number }}
 */
export function ahoraEnZona(zona = ZONA_POR_DEFECTO, instante = new Date()) {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: zona,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  });
  const p = Object.fromEntries(
    fmt.formatToParts(instante).filter((x) => x.type !== 'literal').map((x) => [x.type, x.value])
  );
  const fecha = `${p.year}-${p.month}-${p.day}`;
  return {
    fecha,
    minutos: Number(p.hour) * 60 + Number(p.minute),
    diaSemana: diaSemana(fecha),
  };
}

/** Fecha de hoy (YYYY-MM-DD) en la zona del negocio. Sustituto directo de hoyISO(). */
export function hoyEnZona(zona = ZONA_POR_DEFECTO, instante = new Date()) {
  return ahoraEnZona(zona, instante).fecha;
}

/** 0 = domingo … 6 = sábado. Calculado en UTC para que no lo mueva el huso del navegador. */
export function diaSemana(fechaISO) {
  const [a, m, d] = fechaISO.split('-').map(Number);
  return new Date(Date.UTC(a, m - 1, d)).getUTCDay();
}

/** Suma (o resta) días a una fecha ISO sin pasar por husos horarios ni horario de verano. */
export function sumarDias(fechaISO, dias) {
  const [a, m, d] = fechaISO.split('-').map(Number);
  const base = new Date(Date.UTC(a, m - 1, d));
  base.setUTCDate(base.getUTCDate() + dias);
  return base.toISOString().slice(0, 10);
}

/** Diferencia en días entre dos fechas ISO (b - a). */
export function diferenciaEnDias(fechaISOa, fechaISOb) {
  const ms = Date.UTC(...fechaISOb.split('-').map(Number).map((v, i) => (i === 1 ? v - 1 : v)))
    - Date.UTC(...fechaISOa.split('-').map(Number).map((v, i) => (i === 1 ? v - 1 : v)));
  return Math.round(ms / 86400000);
}

/** 'HH:MM' o 'HH:MM:SS' → minutos desde las 00:00. */
export function aMinutos(horaStr) {
  if (typeof horaStr === 'number') return horaStr;
  const [h, m] = String(horaStr).split(':').map(Number);
  return h * 60 + (m || 0);
}

/** Minutos desde las 00:00 → 'HH:MM'. */
export function aHora(minutos) {
  const h = Math.floor(minutos / 60);
  const m = minutos % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

/** Nombre corto del día ('lun', 'mar', …) para la tira de días del wizard. */
export function nombreDia(fechaISO, locale = 'es-PY') {
  const [a, m, d] = fechaISO.split('-').map(Number);
  return new Date(Date.UTC(a, m - 1, d)).toLocaleDateString(locale, { weekday: 'short', timeZone: 'UTC' });
}

/** '2026-08-05' → '5 de agosto' */
export function fechaLegible(fechaISO, locale = 'es-PY') {
  const [a, m, d] = fechaISO.split('-').map(Number);
  return new Date(Date.UTC(a, m - 1, d)).toLocaleDateString(locale, {
    day: 'numeric',
    month: 'long',
    timeZone: 'UTC',
  });
}
