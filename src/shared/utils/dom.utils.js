/**
 * shared/utils/dom.utils.js
 * Helpers mínimos para no repetir document.getElementById en cada archivo.
 */
export const qs = (id) => document.getElementById(id);

export function mostrarMensaje(elId, texto, tipo = 'info') {
  const el = qs(elId);
  if (!el) return;
  el.textContent = texto;
  const color = tipo === 'error' ? 'text-bloqueado' : tipo === 'ok' ? 'text-libre' : 'text-bone-dim';
  el.className = `text-xs mt-3 text-center font-mono ${color}`;
}

export function refreshIcons() {
  if (window.lucide) window.lucide.createIcons();
}
