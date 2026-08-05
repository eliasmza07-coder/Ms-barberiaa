/**
 * modules/admin/dashboard.controller.js
 * Pantalla de bienvenida del panel: estadísticas del día y accesos
 * rápidos a las secciones más usadas. Es la primera pantalla que ve el
 * barbero al entrar (antes, entraba directo a la agenda sin contexto).
 */
import { qs, refreshIcons } from '../../shared/utils/dom.utils.js';
import { hoyISO } from '../../shared/utils/date.utils.js';
import { ReservationsService } from '../reservations/reservations.service.js';

const TARJETAS = [
  { key: 'total', label: 'Turnos hoy', icono: 'calendar', color: 'text-bone' },
  { key: 'pendientes', label: 'Pendientes', icono: 'clock', color: 'text-pendiente' },
  { key: 'confirmados', label: 'Confirmados', icono: 'check-circle-2', color: 'text-libre' },
  { key: 'cancelados', label: 'Cancelados', icono: 'x-circle', color: 'text-bloqueado' },
];

function renderStats(container, stats) {
  container.innerHTML = TARJETAS.map(
    (t, i) => `
    <div class="stat-card opacity-0 animate-fade-in-up" style="animation-delay:${i * 60}ms">
      <div class="flex items-center justify-between mb-2">
        <span class="text-[10px] uppercase tracking-widest text-bone-dim font-mono">${t.label}</span>
        <i data-lucide="${t.icono}" class="w-3.5 h-3.5 ${t.color}"></i>
      </div>
      <p class="font-display text-3xl ${t.color}">${stats[t.key]}</p>
    </div>
  `
  ).join('');
  refreshIcons();
}

export const DashboardController = {
  init(onIrA) {
    document.querySelectorAll('[data-ir-a]').forEach((btn) => {
      btn.addEventListener('click', () => onIrA(btn.dataset.irA));
    });
  },

  async cargar() {
    const hoy = hoyISO();
    qs('dashFechaHoy').textContent = new Date(hoy + 'T12:00:00').toLocaleDateString('es-PY', {
      weekday: 'long', day: 'numeric', month: 'long',
    });

    const stats = await ReservationsService.estadisticasDeHoy(hoy);
    renderStats(qs('dashStats'), stats);
  },
};
