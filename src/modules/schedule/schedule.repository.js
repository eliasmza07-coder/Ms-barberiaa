/**
 * modules/schedule/schedule.repository.js
 * Acceso a las 3 tablas de horarios/agenda del proyecto original:
 * config_jornada, dias_libres, horas_bloqueadas. Mismos nombres que ya
 * existen en la base en producción — no se renombran acá.
 */
import { supabaseClient } from '../../config/supabaseClient.js';

export const scheduleRepository = {
  async obtenerConfigJornada(fecha) {
    return supabaseClient.from('config_jornada').select('*').eq('fecha', fecha).maybeSingle();
  },

  async guardarConfigJornada({ fecha, apertura, cierre, intervalo }) {
    return supabaseClient
      .from('config_jornada')
      .upsert({ fecha, apertura, cierre, intervalo }, { onConflict: 'fecha' });
  },

  async obtenerDiaBloqueado(fecha) {
    // OJO: NO se usa .maybeSingle() acá a propósito. En la tabla real,
    // `id` es la primary key (no `fecha`), así que nada impide que existan
    // dos filas con la misma fecha si en algún momento se insertó dos
    // veces (ej. doble clic). .maybeSingle() rompía apenas eso pasaba
    // ("multiple rows returned"), dejando el estado de "día bloqueado"
    // desincronizado. Acá se trae la lista completa y se decide por
    // longitud — funciona haya 0, 1 o más filas.
    return supabaseClient.from('dias_libres').select('*').eq('fecha', fecha);
  },

  async bloquearDia(fecha) {
    // Idempotente: si ya existe una fila para esa fecha, no inserta otra.
    const { data } = await this.obtenerDiaBloqueado(fecha);
    if (data && data.length > 0) return { data, error: null };
    return supabaseClient.from('dias_libres').insert({ fecha });
  },

  async desbloquearDia(fecha) {
    // Borra TODAS las filas de esa fecha (limpia también duplicados viejos).
    return supabaseClient.from('dias_libres').delete().eq('fecha', fecha);
  },

  async obtenerHorasBloqueadas(fecha) {
    return supabaseClient.from('horas_bloqueadas').select('*').eq('fecha', fecha);
  },

  async bloquearHora(fecha, hora) {
    return supabaseClient.from('horas_bloqueadas').insert({ fecha, hora });
  },
};
