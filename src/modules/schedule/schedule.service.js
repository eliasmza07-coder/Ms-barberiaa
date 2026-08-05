/**
 * modules/schedule/schedule.service.js
 *
 * Contiene la regla de negocio más sensible del proyecto: calcular qué
 * bloques horarios están libres/reservados/bloqueados/pasados para una
 * fecha y un servicio dados. Migrado 1:1 desde cargarHorariosCliente() y
 * cargarAgendaAdmin() del index.html original — misma matemática, mismos
 * criterios, solo separado de la manipulación del DOM.
 */
import { scheduleRepository } from './schedule.repository.js';
import { supabaseClient } from '../../config/supabaseClient.js';
import { generarBloques, convertirMinutos, minutosAHora, hoyISO } from '../../shared/utils/date.utils.js';
import { JORNADA_DEFAULT, ESTADO_SLOT } from '../../config/constants.js';
import { store } from '../../shared/state/store.js';

export const ScheduleService = {
  async obtenerConfigJornada(fecha) {
    try {
      const { data } = await scheduleRepository.obtenerConfigJornada(fecha);
      if (data) return { apertura: data.apertura, cierre: data.cierre, intervalo: data.intervalo };
    } catch (e) { /* usa default */ }
    return store.configJornadaActual || JORNADA_DEFAULT;
  },

  async guardarConfigJornada({ fecha, apertura, cierre, intervalo }) {
    if (apertura >= cierre) throw new Error('Apertura debe ser menor al cierre.');
    return scheduleRepository.guardarConfigJornada({ fecha, apertura, cierre, intervalo });
  },

  /**
   * Calcula la disponibilidad de horarios de un día para el cliente,
   * considerando la duración del servicio elegido (para que un slot solo
   * aparezca libre si hay espacio contiguo suficiente).
   * Devuelve: { jornada, bloques: [{ hora, estado }] }
   */
  async calcularDisponibilidadCliente(fecha, duracionServicioMin = 30) {
    const jornada = await this.obtenerConfigJornada(fecha);

    const [{ data: diaBloqueadoRow }, { data: horasBloq }, { data: turnos }] = await Promise.all([
      scheduleRepository.obtenerDiaBloqueado(fecha),
      scheduleRepository.obtenerHorasBloqueadas(fecha),
      supabaseClient.from('turnos').select('*').eq('fecha', fecha).neq('estado', 'cancelado'),
    ]);

    const bloquesBase = generarBloques(jornada.apertura, jornada.cierre, jornada.intervalo);
    const horasBloqSet = new Set((horasBloq || []).map((h) => h.hora.slice(0, 5)));
    const diaEstaBloqueado = !!(diaBloqueadoRow && diaBloqueadoRow.length > 0);

    const turnosOcupadosMinutos = new Set();
    (turnos || []).forEach((t) => {
      const tInicio = convertirMinutos(t.hora.slice(0, 5));
      const tDuracion = t.duracion_min || 30;
      for (let m = tInicio; m < tInicio + tDuracion; m += jornada.intervalo) {
        turnosOcupadosMinutos.add(minutosAHora(m));
      }
    });

    const bloquesNecesariosCount = Math.ceil(duracionServicioMin / jornada.intervalo);

    const ahora = new Date();
    const hoyStr = hoyISO();
    const esHoy = fecha === hoyStr;
    const horaActualMin = ahora.getHours() * 60 + ahora.getMinutes();

    const bloques = bloquesBase.map((hora) => {
      const horaMin = convertirMinutos(hora);
      let estado = ESTADO_SLOT.LIBRE;

      let libreHaciaAdelante = true;
      for (let i = 0; i < bloquesNecesariosCount; i++) {
        const slotCheckMin = horaMin + i * jornada.intervalo;
        const slotCheckStr = minutosAHora(slotCheckMin);
        if (
          slotCheckMin >= jornada.cierre * 60 ||
          diaEstaBloqueado ||
          horasBloqSet.has(slotCheckStr) ||
          turnosOcupadosMinutos.has(slotCheckStr)
        ) {
          libreHaciaAdelante = false;
          break;
        }
      }

      if (diaEstaBloqueado || horasBloqSet.has(hora)) estado = ESTADO_SLOT.BLOQUEADO;
      else if (esHoy && horaMin <= horaActualMin) estado = ESTADO_SLOT.PASADO;
      else if (!libreHaciaAdelante || turnosOcupadosMinutos.has(hora)) estado = ESTADO_SLOT.RESERVADO;

      return { hora, estado };
    });

    return { jornada, bloques };
  },

  /**
   * Calcula la grilla completa para el admin (incluye datos del turno,
   * no solo el estado), igual que cargarAgendaAdmin() del original.
   */
  async calcularAgendaAdmin(fecha) {
    const jornada = await this.obtenerConfigJornada(fecha);

    const [{ data: diaRow }, { data: horasBloq }, { data: turnos }] = await Promise.all([
      scheduleRepository.obtenerDiaBloqueado(fecha),
      scheduleRepository.obtenerHorasBloqueadas(fecha),
      supabaseClient.from('turnos').select('*').eq('fecha', fecha).neq('estado', 'cancelado'),
    ]);

    store.diaBloqueado = !!(diaRow && diaRow.length > 0);
    store.horasBloqueadasDia = horasBloq || [];
    store.turnosDia = turnos || [];

    const bloques = generarBloques(jornada.apertura, jornada.cierre, jornada.intervalo);
    const horasBloqMap = new Map(store.horasBloqueadasDia.map((h) => [h.hora.slice(0, 5), h]));
    const turnosMap = new Map(store.turnosDia.map((t) => [t.hora.slice(0, 5), t]));

    const filas = bloques.map((hora) => {
      let estado = ESTADO_SLOT.LIBRE;
      const turno = turnosMap.get(hora);
      const bloqueoHora = horasBloqMap.get(hora);

      if (store.diaBloqueado) estado = ESTADO_SLOT.BLOQUEADO;
      else if (turno) estado = ESTADO_SLOT.RESERVADO;
      else if (bloqueoHora) estado = ESTADO_SLOT.BLOQUEADO;

      return { hora, estado, turno: turno || null };
    });

    return { jornada, filas };
  },

  async toggleDiaCompleto(fecha) {
    if (store.diaBloqueado) await scheduleRepository.desbloquearDia(fecha);
    else await scheduleRepository.bloquearDia(fecha);
  },

  async bloquearHora(fecha, hora) {
    return scheduleRepository.bloquearHora(fecha, hora);
  },
};
