/**
 * shared/utils/local-storage.utils.js
 * Wrapper mínimo sobre localStorage para persistir el "último turno" del
 * cliente entre recargas de página (así la tarjeta de seguimiento no se
 * pierde si cierra o recarga el navegador). Todo dentro de try/catch por
 * si el navegador tiene localStorage bloqueado (modo privado estricto, etc.).
 */
const KEY = 'msBarberia_ultimoTurno';

export const turnoStorage = {
  guardar(turno) {
    try { localStorage.setItem(KEY, JSON.stringify(turno)); } catch (e) { /* ignorar */ }
  },
  leer() {
    try {
      const raw = localStorage.getItem(KEY);
      return raw ? JSON.parse(raw) : null;
    } catch (e) { return null; }
  },
  borrar() {
    try { localStorage.removeItem(KEY); } catch (e) { /* ignorar */ }
  },
};
