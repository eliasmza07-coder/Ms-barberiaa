/**
 * shared/utils/date.utils.js
 * Migrado 1:1 desde las funciones globales del index.html original:
 * generarBloques, convertirMinutos, minutosAHora.
 */

export function generarBloques(apertura, cierre, intervalo) {
  const bloques = [];
  for (let h = apertura; h < cierre; h++) {
    for (let m = 0; m < 60; m += intervalo) {
      bloques.push(`${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`);
    }
  }
  return bloques;
}

export function convertirMinutos(horaStr) {
  const [h, m] = horaStr.split(':').map(Number);
  return h * 60 + m;
}

export function minutosAHora(minutos) {
  const h = Math.floor(minutos / 60);
  const m = minutos % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

export function hoyISO() {
  return new Date().toISOString().split('T')[0];
}
