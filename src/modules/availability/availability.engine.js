/**
 * modules/availability/availability.engine.js
 *
 * MOTOR DE DISPONIBILIDAD — el corazón del sistema.
 *
 * Es una función PURA: no toca Supabase, no toca el DOM, no lee el reloj.
 * Todo lo que necesita entra por parámetro. Eso permite testearla con
 * casos borde reales (ver test/availability.engine.test.js) en vez de
 * "probar reservando a ver qué pasa".
 *
 * Trabaja siempre en MINUTOS DESDE LAS 00:00 del día que se está
 * calculando. La conversión desde/hacia 'HH:MM' y la resolución de la
 * zona horaria las hace availability.service.js antes de llamar acá.
 *
 * Regla central (la que pidió el negocio):
 *
 *     inicio - margenAntes  >= apertura del turno laboral
 *     inicio + duración + margenDespués <= cierre del turno laboral
 *     y el bloque [inicio - margenAntes, inicio + duración + margenDespués]
 *     no se solapa con ninguna ocupación ni bloqueo.
 */

export const MOTIVO = {
  LIBRE: 'libre',
  OCUPADO: 'ocupado',
  BLOQUEADO: 'bloqueado',
  PASADO: 'pasado',
  ANTICIPACION: 'anticipacion',
  NO_ENTRA: 'no_entra',
};

export const MOTIVO_DIA = {
  DISPONIBLE: 'disponible',
  CERRADO: 'cerrado',
  SIN_CUPO: 'sin_cupo',
  PASADO: 'pasado',
  FUERA_DE_RANGO: 'fuera_de_rango',
};

/** ¿Se solapan [aIni, aFin) y [bIni, bFin)? */
export function seSolapan(aIni, aFin, bIni, bFin) {
  return aIni < bFin && bIni < aFin;
}

/**
 * Normaliza una lista de rangos y los fusiona si se tocan. Sirve para que
 * el cálculo no dependa de cuántas filas separadas haya en la base.
 */
export function fusionarRangos(rangos) {
  const ordenados = [...rangos]
    .filter((r) => Number.isFinite(r.inicio) && Number.isFinite(r.fin) && r.fin > r.inicio)
    .sort((a, b) => a.inicio - b.inicio);

  const salida = [];
  for (const r of ordenados) {
    const ultimo = salida[salida.length - 1];
    if (ultimo && r.inicio <= ultimo.fin) ultimo.fin = Math.max(ultimo.fin, r.fin);
    else salida.push({ inicio: r.inicio, fin: r.fin });
  }
  return salida;
}

/**
 * Calcula los horarios disponibles de UN día.
 *
 * @param {object} params
 * @param {string}  params.fecha            'YYYY-MM-DD' del día a calcular.
 * @param {string}  params.hoy              'YYYY-MM-DD' de hoy, en la zona del negocio.
 * @param {number}  params.minutosAhora     Minutos transcurridos hoy, en la zona del negocio.
 * @param {Array}   params.jornadas         Turnos laborales: [{ inicio, fin }] en minutos. Vacío = cerrado.
 * @param {number}  params.intervalo        Paso de la grilla (5 | 10 | 15 | 30).
 * @param {number}  params.duracion         Suma de duraciones de los servicios elegidos.
 * @param {number}  [params.margenAntes=0]  Minutos de preparación previos.
 * @param {number}  [params.margenDespues=0] Minutos de limpieza posteriores.
 * @param {Array}   [params.ocupaciones=[]] Citas existentes: [{ inicio, fin }] YA con sus márgenes incluidos.
 * @param {Array}   [params.bloqueos=[]]    Bloqueos manuales: [{ inicio, fin }].
 * @param {boolean} [params.cerrado=false]  Día cerrado explícitamente (feriado, vacaciones, día libre).
 * @param {number}  [params.anticipacionMin=0]  Minutos mínimos entre "ahora" y el inicio del turno.
 * @param {number}  [params.anticipacionMaxDias=60] Cuántos días hacia adelante se puede reservar.
 * @param {boolean} [params.ignorarAnticipacion=false] true para citas creadas por el barbero en el local.
 * @param {boolean} [params.incluirNoDisponibles=false] true devuelve también los slots inválidos, con su motivo.
 *
 * @returns {{ abierto: boolean, motivoDia: string, slots: Array<{hora:number, disponible:boolean, motivo:string, fin:number}> }}
 */
export function calcularDisponibilidadDia({
  fecha,
  hoy,
  minutosAhora,
  jornadas = [],
  intervalo = 15,
  duracion = 30,
  margenAntes = 0,
  margenDespues = 0,
  ocupaciones = [],
  bloqueos = [],
  cerrado = false,
  anticipacionMin = 0,
  anticipacionMaxDias = 60,
  diasHastaFecha = null,
  ignorarAnticipacion = false,
  incluirNoDisponibles = false,
}) {
  const vacio = (motivoDia) => ({ abierto: false, motivoDia, slots: [] });

  if (fecha < hoy) return vacio(MOTIVO_DIA.PASADO);
  if (cerrado || jornadas.length === 0) return vacio(MOTIVO_DIA.CERRADO);

  const dias = diasHastaFecha ?? 0;
  if (!ignorarAnticipacion && dias > anticipacionMaxDias) return vacio(MOTIVO_DIA.FUERA_DE_RANGO);

  const esHoy = fecha === hoy;
  const pisoTemporal = esHoy && !ignorarAnticipacion ? minutosAhora + anticipacionMin : -Infinity;

  const jornadasLimpias = fusionarRangos(jornadas);
  // Se fusionan por separado para poder decir al barbero si un hueco está
  // tomado por una cita o por un bloqueo manual (el cliente solo ve "no disponible").
  const ocupadas = fusionarRangos(ocupaciones);
  const bloqueadas = fusionarRangos(bloqueos);

  const duracionTotal = margenAntes + duracion + margenDespues;
  const slots = [];

  for (const jornada of jornadasLimpias) {
    // La grilla arranca en la apertura de cada turno laboral, no a las 00:00:
    // si el negocio abre 08:30 con intervalo 15, los slots son 08:30, 08:45…
    for (let inicio = jornada.inicio + margenAntes; inicio + duracion + margenDespues <= jornada.fin; inicio += intervalo) {
      const bloqueInicio = inicio - margenAntes;
      const bloqueFin = inicio + duracion + margenDespues;

      let motivo = MOTIVO.LIBRE;

      if (esHoy && inicio < minutosAhora) motivo = MOTIVO.PASADO;
      else if (inicio < pisoTemporal) motivo = MOTIVO.ANTICIPACION;
      else if (bloqueadas.some((b) => seSolapan(bloqueInicio, bloqueFin, b.inicio, b.fin))) {
        motivo = MOTIVO.BLOQUEADO;
      } else if (ocupadas.some((o) => seSolapan(bloqueInicio, bloqueFin, o.inicio, o.fin))) {
        motivo = MOTIVO.OCUPADO;
      }

      const disponible = motivo === MOTIVO.LIBRE;
      if (disponible || incluirNoDisponibles) {
        slots.push({ hora: inicio, fin: inicio + duracion, disponible, motivo, duracionTotal });
      }
    }
  }

  slots.sort((a, b) => a.hora - b.hora);

  const hayAlguno = slots.some((s) => s.disponible);
  return {
    abierto: true,
    motivoDia: hayAlguno ? MOTIVO_DIA.DISPONIBLE : MOTIVO_DIA.SIN_CUPO,
    slots,
  };
}

/**
 * Convierte una cita existente en el rango de minutos que realmente ocupa,
 * incluyendo los márgenes de preparación y limpieza de sus servicios.
 */
export function ocupacionDeTurno({ inicio, duracion, margenAntes = 0, margenDespues = 0 }) {
  return { inicio: inicio - margenAntes, fin: inicio + duracion + margenDespues };
}

/**
 * Estado resumido de un día, para la tira "Lun / Mar / Mié…" del paso 2 del
 * wizard: alcanza con saber si hay al menos un hueco, sin pintar la grilla.
 */
export function estadoDelDia(params) {
  const { motivoDia, abierto, slots } = calcularDisponibilidadDia(params);
  return {
    estado: motivoDia,
    abierto,
    cupos: slots.filter((s) => s.disponible).length,
  };
}
