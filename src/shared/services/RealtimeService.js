/**
 * shared/services/RealtimeService.js
 * Generaliza suscribirseRealtime() del index.html original: sigue escuchando
 * TODOS los cambios de postgres_changes en el schema public y notifica a
 * cualquier callback registrado, sin que cada módulo tenga que abrir su
 * propio canal.
 */
import { supabaseClient } from '../../config/supabaseClient.js';

const listeners = new Set();
let channel = null;

export const RealtimeService = {
  /** Registra un callback que se ejecuta ante cualquier cambio en la base. */
  onChange(callback) {
    listeners.add(callback);
    return () => listeners.delete(callback); // función de desuscripción
  },

  /** Abre (una sola vez) el canal global de cambios. */
  start() {
    if (channel) return;
    channel = supabaseClient
      .channel('cambios-globales')
      .on('postgres_changes', { event: '*', schema: 'public' }, () => {
        listeners.forEach((cb) => {
          try { cb(); } catch (e) { console.error('[RealtimeService] listener error', e); }
        });
      })
      .subscribe();
  },
};
