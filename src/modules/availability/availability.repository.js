/**
 * modules/availability/availability.repository.js
 *
 * Único punto de acceso a los datos que necesita el motor de
 * disponibilidad. Nada de esto consulta `turnos` directamente: la tabla
 * pasó a estar protegida por RLS (migración 005) y la ocupación se lee por
 * `ocupacion_rango()`, que devuelve solo rangos horarios — sin nombres ni
 * teléfonos. El navegador ya no necesita ver los datos de tus clientes
 * para pintar la grilla, así que no los recibe.
 */
import { supabaseClient } from '../../config/supabaseClient.js';

export const availabilityRepository = {
  /** Configuración del negocio (zona horaria, márgenes, anticipación…). */
  async obtenerConfig() {
    const { data, error } = await supabaseClient.from('negocio_config').select('*').limit(1).maybeSingle();
    if (error) throw error;
    return data;
  },

  /** Jornadas laborales ya resueltas (semanal + excepciones) para un rango. */
  async jornadas(desde, hasta) {
    const { data, error } = await supabaseClient.rpc('jornadas_rango', { p_desde: desde, p_hasta: hasta });
    if (error) throw error;
    return data || [];
  },

  /** Franjas ocupadas (turnos + bloqueos + holds vigentes) de un rango. */
  async ocupacion(desde, hasta) {
    const { data, error } = await supabaseClient.rpc('ocupacion_rango', { p_desde: desde, p_hasta: hasta });
    if (error) throw error;
    return data || [];
  },

  /** Aparta un horario mientras el cliente completa sus datos. */
  async crearHold({ fecha, hora, servicios }) {
    const { data, error } = await supabaseClient.rpc('crear_hold', {
      p_fecha: fecha,
      p_hora: hora,
      p_servicios: servicios,
    });
    if (error) throw error;
    return data;
  },

  async liberarHold(holdId) {
    if (!holdId) return;
    await supabaseClient.rpc('liberar_hold', { p_hold_id: holdId });
  },

  /** Crea la reserva. Toda la validación real ocurre del lado del servidor. */
  async crearReserva({ fecha, hora, nombre, telefono, servicios, comentario, holdId, origen = 'web' }) {
    const { data, error } = await supabaseClient.rpc('crear_reserva', {
      p_fecha: fecha,
      p_hora: hora,
      p_nombre: nombre,
      p_telefono: telefono,
      p_servicios: servicios,
      p_comentario: comentario ?? null,
      p_hold_id: holdId ?? null,
      p_origen: origen,
    });
    if (error) throw error;
    return data;
  },

  async turnoPorToken(token) {
    const { data, error } = await supabaseClient.rpc('turno_por_token', { p_token: token });
    if (error) throw error;
    return data;
  },

  async cancelarConToken(token, motivo) {
    const { data, error } = await supabaseClient.rpc('cancelar_turno_cliente', {
      p_token: token,
      p_motivo: motivo ?? null,
    });
    if (error) throw error;
    return data;
  },

  async reprogramar({ turnoId, fecha, hora }) {
    const { data, error } = await supabaseClient.rpc('reprogramar_turno', {
      p_turno_id: turnoId,
      p_fecha: fecha,
      p_hora: hora,
    });
    if (error) throw error;
    return data;
  },

  async cambiarEstado({ turnoId, estado, motivo }) {
    const { data, error } = await supabaseClient.rpc('cambiar_estado_turno', {
      p_turno_id: turnoId,
      p_nuevo_estado: estado,
      p_motivo: motivo ?? null,
    });
    if (error) throw error;
    return data;
  },
};
