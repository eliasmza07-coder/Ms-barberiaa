/**
 * modules/availability/availability.service.js
 *
 * Orquesta: trae los datos (repository) → los convierte a minutos → llama
 * al motor puro (engine) → devuelve algo listo para pintar.
 *
 * Incluye `calcularDisponibilidadCliente()`, con la MISMA firma y la misma
 * forma de respuesta que la función homónima de schedule.service.js. Eso
 * permite migrar el front-end cambiando una sola línea de import y volver
 * atrás si algo sale mal (ver docs/PLAN_IMPLEMENTACION.md, paso 4).
 */
import { availabilityRepository } from './availability.repository.js';
import {
  calcularDisponibilidadDia,
  estadoDelDia,
  MOTIVO,
  MOTIVO_DIA,
} from './availability.engine.js';
import {
  ahoraEnZona,
  aMinutos,
  aHora,
  sumarDias,
  diferenciaEnDias,
  ZONA_POR_DEFECTO,
} from '../../shared/utils/datetime.utils.js';

const CONFIG_POR_DEFECTO = {
  zona_horaria: ZONA_POR_DEFECTO,
  intervalo_slot_min: 15,
  margen_antes_min: 0,
  margen_despues_min: 5,
  anticipacion_min_min: 30,
  anticipacion_max_dias: 60,
  limite_cancelacion_horas: 3,
  hold_minutos: 5,
};

let configCache = null;

export const AvailabilityService = {
  /** La config cambia poco: se cachea en memoria y se invalida a mano tras editarla. */
  async config() {
    if (configCache) return configCache;
    try {
      configCache = (await availabilityRepository.obtenerConfig()) || CONFIG_POR_DEFECTO;
    } catch (e) {
      console.error('[AvailabilityService] usando configuración por defecto:', e);
      configCache = CONFIG_POR_DEFECTO;
    }
    return configCache;
  },

  invalidarConfig() {
    configCache = null;
  },

  /**
   * Duración, precio y márgenes del combo de servicios elegido.
   * @param {Array} servicios - objetos del catálogo ya seleccionados.
   */
  resumenServicios(servicios, cfg) {
    const lista = servicios.filter(Boolean);
    return {
      duracion: lista.reduce((acc, s) => acc + Number(s.duracion || 0), 0),
      precio: lista.reduce((acc, s) => acc + Number(s.precio || 0), 0),
      // Los márgenes NO se suman: la limpieza se hace una vez al final.
      margenAntes: Math.max(0, ...lista.map((s) => s.margen_antes_min ?? cfg.margen_antes_min)),
      margenDespues: Math.max(0, ...lista.map((s) => s.margen_despues_min ?? cfg.margen_despues_min)),
      nombres: lista.map((s) => s.nombre).join(' + '),
      ids: lista.map((s) => s.id),
    };
  },

  /**
   * Disponibilidad de UN día para un combo de servicios.
   * @returns {{ abierto, motivoDia, slots: Array<{hora:string, disponible, motivo}> , jornadas }}
   */
  async disponibilidadDia(fecha, servicios, { ignorarAnticipacion = false } = {}) {
    const [cfg, jornadasRaw, ocupacionRaw] = await Promise.all([
      this.config(),
      availabilityRepository.jornadas(fecha, fecha),
      availabilityRepository.ocupacion(fecha, fecha),
    ]);

    const resumen = this.resumenServicios(servicios, cfg);
    const ahora = ahoraEnZona(cfg.zona_horaria);

    const resultado = calcularDisponibilidadDia({
      fecha,
      hoy: ahora.fecha,
      minutosAhora: ahora.minutos,
      diasHastaFecha: diferenciaEnDias(ahora.fecha, fecha),
      jornadas: jornadasRaw.map((j) => ({ inicio: aMinutos(j.hora_inicio), fin: aMinutos(j.hora_fin) })),
      intervalo: cfg.intervalo_slot_min,
      duracion: resumen.duracion || 30,
      margenAntes: resumen.margenAntes,
      margenDespues: resumen.margenDespues,
      ocupaciones: ocupacionRaw
        .filter((o) => o.tipo !== 'bloqueo')
        .map((o) => ({ inicio: aMinutos(o.hora_inicio), fin: aMinutos(o.hora_fin) })),
      bloqueos: ocupacionRaw
        .filter((o) => o.tipo === 'bloqueo')
        .map((o) => ({ inicio: aMinutos(o.hora_inicio), fin: aMinutos(o.hora_fin) })),
      anticipacionMin: cfg.anticipacion_min_min,
      anticipacionMaxDias: cfg.anticipacion_max_dias,
      ignorarAnticipacion,
      incluirNoDisponibles: ignorarAnticipacion, // el barbero sí ve por qué un hueco no sirve
    });

    return {
      ...resultado,
      slots: resultado.slots.map((s) => ({ ...s, hora: aHora(s.hora), horaFin: aHora(s.fin) })),
      resumen,
    };
  },

  /**
   * Estado de cada día de un rango, para la tira "Lun / Mar / Mié…" del
   * paso 2 del wizard. Una sola ida a la base para toda la semana.
   *
   * @returns {Array<{fecha, estado, cupos}>}  estado ∈ disponible | sin_cupo | cerrado | pasado | fuera_de_rango
   */
  async resumenDias(desde, cantidadDias, servicios) {
    const hasta = sumarDias(desde, cantidadDias - 1);
    const [cfg, jornadasRaw, ocupacionRaw] = await Promise.all([
      this.config(),
      availabilityRepository.jornadas(desde, hasta),
      availabilityRepository.ocupacion(desde, hasta),
    ]);

    const resumen = this.resumenServicios(servicios, cfg);
    const ahora = ahoraEnZona(cfg.zona_horaria);

    const porFecha = (lista) =>
      lista.reduce((acc, x) => {
        (acc[x.fecha] ||= []).push(x);
        return acc;
      }, {});
    const jornadasPorFecha = porFecha(jornadasRaw);
    const ocupacionPorFecha = porFecha(ocupacionRaw);

    const dias = [];
    for (let i = 0; i < cantidadDias; i++) {
      const fecha = sumarDias(desde, i);
      const js = jornadasPorFecha[fecha] || [];
      const os = ocupacionPorFecha[fecha] || [];

      const { estado, cupos } = estadoDelDia({
        fecha,
        hoy: ahora.fecha,
        minutosAhora: ahora.minutos,
        diasHastaFecha: diferenciaEnDias(ahora.fecha, fecha),
        jornadas: js.map((j) => ({ inicio: aMinutos(j.hora_inicio), fin: aMinutos(j.hora_fin) })),
        intervalo: cfg.intervalo_slot_min,
        duracion: resumen.duracion || 30,
        margenAntes: resumen.margenAntes,
        margenDespues: resumen.margenDespues,
        ocupaciones: os
          .filter((o) => o.tipo !== 'bloqueo')
          .map((o) => ({ inicio: aMinutos(o.hora_inicio), fin: aMinutos(o.hora_fin) })),
        bloqueos: os
          .filter((o) => o.tipo === 'bloqueo')
          .map((o) => ({ inicio: aMinutos(o.hora_inicio), fin: aMinutos(o.hora_fin) })),
        anticipacionMin: cfg.anticipacion_min_min,
        anticipacionMaxDias: cfg.anticipacion_max_dias,
      });

      dias.push({ fecha, estado, cupos });
    }
    return dias;
  },

  // ------------------------------------------------------------------
  // Adaptador de compatibilidad
  // ------------------------------------------------------------------
  /**
   * Misma firma y misma forma de respuesta que
   * ScheduleService.calcularDisponibilidadCliente(fecha, duracionMin).
   * Permite enchufar el motor nuevo sin tocar reservations.controller.js.
   */
  async calcularDisponibilidadCliente(fecha, duracionServicioMin = 30) {
    const cfg = await this.config();
    const servicioFicticio = [{ id: '__tmp__', nombre: '', precio: 0, duracion: duracionServicioMin }];
    const r = await this.disponibilidadDia(fecha, servicioFicticio);

    const jornadaInicio = r.slots.length ? aMinutos(r.slots[0].hora) : 8 * 60;
    return {
      jornada: {
        apertura: Math.floor(jornadaInicio / 60),
        cierre: 20,
        intervalo: cfg.intervalo_slot_min,
      },
      bloques: r.slots.map((s) => ({
        hora: s.hora,
        estado: s.disponible ? 'libre' : s.motivo === MOTIVO.BLOQUEADO ? 'bloqueado' : 'reservado',
      })),
      motivoDia: r.motivoDia,
    };
  },
};

export { MOTIVO, MOTIVO_DIA };
