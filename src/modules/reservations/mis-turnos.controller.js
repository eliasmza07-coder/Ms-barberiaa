/**
 * modules/reservations/mis-turnos.controller.js
 * Historial de reservas del cliente logueado. Se muestra desde el botón
 * "Mi Cuenta" del navbar (visible solo con sesión de cliente activa) o
 * desde el enlace dentro del wizard de reserva.
 */
import { qs, refreshIcons } from '../../shared/utils/dom.utils.js';
import { formatoGs } from '../../shared/utils/currency.utils.js';
import { AuthService } from '../../shared/services/AuthService.js';
import { ReservationsService } from './reservations.service.js';

const ESTILOS_ESTADO = {
  confirmado: 'text-libre',
  cancelado: 'text-bloqueado',
  pendiente: 'text-pendiente',
};

function renderTurnos(container, turnos) {
  if (turnos.length === 0) {
    container.innerHTML = `<p class="text-bone-dim text-sm text-center font-mono py-10">Todavía no hiciste ninguna reserva con esta cuenta.</p>`;
    return;
  }
  container.innerHTML = turnos
    .map(
      (t, i) => `
    <div class="card-edge bg-ink-surface rounded-xl p-4 opacity-0 animate-fade-in-up" style="animation-delay:${Math.min(i * 50, 300)}ms">
      <div class="flex items-center justify-between mb-1.5">
        <p class="text-bone font-medium text-sm">${t.servicio_nombre}</p>
        <span class="text-[10px] uppercase tracking-widest font-mono ${ESTILOS_ESTADO[t.estado] || 'text-bone-dim'}">${t.estado}</span>
      </div>
      <div class="flex items-center justify-between text-xs font-mono text-bone-dim">
        <span>${t.fecha} · ${t.hora.slice(0, 5)}</span>
        <span class="text-gold">${formatoGs(t.precio || 0)}</span>
      </div>
    </div>
  `
    )
    .join('');
  refreshIcons();
}

async function abrirMisTurnos() {
  const sesion = await AuthService.getSession();
  const modal = qs('modalMisTurnos');
  const lista = qs('listaMisTurnos');

  if (!sesion) {
    // No hay cuenta activa — lo mandamos a reservar (ahí puede iniciar sesión o crear cuenta).
    document.querySelector('[data-action="abrir-reserva"]')?.click();
    return;
  }

  modal.classList.remove('hidden');
  qs('modalReserva').classList.add('hidden');
  document.body.style.overflow = 'hidden';
  lista.innerHTML = `<p class="text-bone-dim text-xs text-center font-mono py-10 animate-pulse">Cargando tus turnos...</p>`;

  try {
    const turnos = await ReservationsService.misTurnos(sesion.user.id);
    renderTurnos(lista, turnos);
  } catch (err) {
    lista.innerHTML = `<p class="text-bloqueado text-xs text-center font-mono py-10">Error al cargar tus turnos.</p>`;
  }
}

function cerrarMisTurnos() {
  qs('modalMisTurnos').classList.add('hidden');
  document.body.style.overflow = '';
}

/** Muestra u oculta el botón "Mi Cuenta" del navbar según haya o no sesión de cliente. */
export async function actualizarBotonMiCuenta() {
  const perfil = await AuthService.getPerfilActual();
  const btn = qs('btnMiCuenta');
  const mostrar = perfil && perfil.rol !== 'barbero';
  btn.classList.toggle('hidden', !mostrar);
  btn.classList.toggle('flex', mostrar);
}

export const MisTurnosController = {
  init() {
    document.querySelectorAll('[data-action="abrir-mis-turnos"]').forEach((el) => {
      el.addEventListener('click', (e) => {
        e.preventDefault();
        abrirMisTurnos();
      });
    });
    qs('btnCerrarMisTurnos').addEventListener('click', cerrarMisTurnos);

    AuthService.onAuthStateChange(() => actualizarBotonMiCuenta());
    actualizarBotonMiCuenta();
  },
};
