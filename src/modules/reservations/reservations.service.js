/**
 * modules/reservations/reservations.service.js
 * Reglas de negocio de reservas. Migrado desde enviarSolicitudReserva(),
 * liberarTurno(), cambiarEstadoTurno() y cargarHistorialGeneral() del
 * index.html original.
 *
 * IMPORTANTE: la creación de una reserva sigue pasando por la misma
 * Supabase Edge Function que ya usa el proyecto en producción
 * (gestionar-reserva), no por un insert directo — así se preserva
 * cualquier validación/servidor que esa función ya hace hoy.
 */
import { reservationsRepository } from './reservations.repository.js';
import { EDGE_FUNCTION_URL } from '../../config/supabaseClient.js';
import { env } from '../../config/env.js';
import { hoyISO } from '../../shared/utils/date.utils.js';

export const ReservationsService = {
  /**
   * Envía la solicitud de reserva a la Edge Function.
   * @throws Error con mensaje amigable si falla la validación o la red.
   */
  async crearSolicitud({ fecha, hora, nombre, telefono, servicio }) {
    const hoyStr = hoyISO();
    if (!fecha || fecha < hoyStr || !hora) {
      throw new Error('Seleccioná fecha y horario válido.');
    }
    if (!nombre || !telefono) {
      throw new Error('Completá tu nombre y teléfono.');
    }
    if (!servicio) {
      throw new Error('Seleccioná un servicio.');
    }

    const response = await fetch(EDGE_FUNCTION_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
      },
      body: JSON.stringify({
        fecha,
        hora,
        cliente_nombre: nombre,
        cliente_telefono: telefono,
        servicio_nombre: servicio.nombre,
        precio: servicio.precio,
        duracion_min: servicio.duracion,
      }),
    });

    const resultado = await response.json();
    if (!response.ok) throw new Error(resultado.error || 'Error al enviar la solicitud.');
    return resultado;
  },

  async listarHistorial() {
    const { data, error } = await reservationsRepository.historialCompleto();
    if (error) throw error;
    return data || [];
  },

  /** Busca el turno recién creado (la Edge Function no devuelve su id) para poder mostrarlo/seguirlo. */
  async buscarRecienCreado({ fecha, hora, telefono }) {
    const { data } = await reservationsRepository.buscarPorFechaHoraTelefono(fecha, hora, telefono);
    return data || null;
  },

  /** Trae el estado actual de un turno puntual (para refrescar la tarjeta de seguimiento). */
  async obtenerPorId(id) {
    const { data } = await reservationsRepository.findById(id);
    return data || null;
  },

  /** Cuenta turnos de hoy por estado, para las tarjetas del Dashboard. */
  async estadisticasDeHoy(fechaHoy) {
    const { data } = await reservationsRepository.porFechaTodos(fechaHoy);
    const turnos = data || [];
    return {
      total: turnos.length,
      pendientes: turnos.filter((t) => t.estado === 'pendiente').length,
      confirmados: turnos.filter((t) => t.estado === 'confirmado').length,
      cancelados: turnos.filter((t) => t.estado === 'cancelado').length,
    };
  },

  /** Si el cliente estaba logueado al reservar, deja su turno guardado en su historial. */
  async vincularCliente(turnoId, clienteId) {
    if (!turnoId || !clienteId) return;
    try {
      await reservationsRepository.vincularCliente(turnoId, clienteId);
    } catch (e) {
      // No es crítico: la reserva ya se hizo igual, solo no queda en "Mis Turnos".
      console.error('[ReservationsService] no se pudo vincular el turno a la cuenta', e);
    }
  },

  /** Historial de reservas del cliente logueado, para "Mis Turnos". */
  async misTurnos(clienteId) {
    const { data, error } = await reservationsRepository.porClienteId(clienteId);
    if (error) throw error;
    return data || [];
  },

  async confirmar(id) {
    return reservationsRepository.cambiarEstado(id, 'confirmado');
  },

  async cambiarEstado(id, nuevoEstado) {
    return reservationsRepository.cambiarEstado(id, nuevoEstado);
  },

  async liberar(id) {
    return reservationsRepository.liberar(id);
  },
};
