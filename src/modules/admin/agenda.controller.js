/**
 * modules/admin/agenda.controller.js
 * Orquesta el tab "Agenda" del panel admin: configuración de jornada,
 * navegación de día, grilla y popover de slot. Migrado desde
 * cargarAgendaAdmin, guardarConfiguracionJornada, cambiarDiaAdmin,
 * toggleDiaCompleto, abrirPopoverSlot, bloquearHora, liberarTurno,
 * cambiarEstadoTurno del index.html original.
 */
import { qs, refreshIcons } from '../../shared/utils/dom.utils.js';
import { store } from '../../shared/state/store.js';
import { hoyISO } from '../../shared/utils/date.utils.js';
import { ScheduleService } from '../schedule/schedule.service.js';
import { ReservationsService } from '../reservations/reservations.service.js';
import { abrirWhatsapp, mensajeConfirmacion, mensajeCancelacion } from '../../shared/utils/whatsapp.utils.js';
import {
  renderGrillaAdmin,
  renderPopover,
  posicionarPopover,
  actualizarBotonDia,
} from './components/Agenda/Agenda.js';

let elFechaAdmin, elGrilla, elPopover, elPopoverContenido, elBtnToggleDia, elBtnToggleDiaTexto;
let onCambioParaHistorial = () => {};

async function cargar() {
  const fecha = elFechaAdmin.value;
  elGrilla.innerHTML = Array.from({ length: 6 })
    .map(
      (_, i) => `<div class="flex items-center gap-3.5 px-5 py-3.5 border-b border-ink-line last:border-0 animate-pulse" style="animation-delay:${i * 60}ms">
        <div class="h-3 w-10 bg-ink-line rounded"></div>
        <div class="w-2 h-2 rounded-full bg-ink-line"></div>
        <div class="h-3 flex-1 max-w-[180px] bg-ink-line rounded"></div>
      </div>`
    )
    .join('');

  try {
    const { jornada, filas } = await ScheduleService.calcularAgendaAdmin(fecha);
    qs('admHoraApertura').value = jornada.apertura;
    qs('admHoraCierre').value = jornada.cierre;
    qs('admIntervalo').value = jornada.intervalo;

    actualizarBotonDia(elBtnToggleDia, elBtnToggleDiaTexto, store.diaBloqueado);
    renderGrillaAdmin(elGrilla, filas, abrirPopoverSlot);
  } catch (err) {
    console.error(err);
    elGrilla.innerHTML = `<p class="p-4 text-bloqueado text-xs font-mono">Error al cargar.</p>`;
  }
}

function abrirPopoverSlot(evt, hora, estado, turnoId) {
  const fecha = elFechaAdmin.value;
  const turno = turnoId ? store.turnosDia.find((x) => x.id == turnoId) : null;

  renderPopover(elPopover, elPopoverContenido, {
    hora,
    fecha,
    estado,
    turno,
    callbacks: {
      onConfirmar: () => cambiarEstado(turno, 'confirmado'),
      onCancelar: () => liberarTurno(turno),
      onBloquearHora: () => bloquearHora(hora),
    },
  });

  const rect = evt.currentTarget.getBoundingClientRect();
  posicionarPopover(elPopover, rect);
}

async function bloquearHora(hora) {
  const fecha = elFechaAdmin.value;
  await ScheduleService.bloquearHora(fecha, hora);
  elPopover.classList.add('hidden');
  await cargar();
}

async function liberarTurno(turno) {
  await ReservationsService.liberar(turno.id);
  elPopover.classList.add('hidden');
  await cargar();
  onCambioParaHistorial();
  if (confirm('¿Avisarle al cliente por WhatsApp que se canceló el turno?')) {
    abrirWhatsapp(turno.cliente_telefono, mensajeCancelacion(turno));
  }
}

async function cambiarEstado(turno, nuevoEstado) {
  await ReservationsService.cambiarEstado(turno.id, nuevoEstado);
  elPopover.classList.add('hidden');
  await cargar();
  onCambioParaHistorial();
  if (nuevoEstado === 'confirmado') {
    abrirWhatsapp(turno.cliente_telefono, mensajeConfirmacion(turno));
  }
}

async function guardarConfiguracionJornada() {
  const fecha = elFechaAdmin.value;
  const apertura = parseInt(qs('admHoraApertura').value);
  const cierre = parseInt(qs('admHoraCierre').value);
  const intervalo = parseInt(qs('admIntervalo').value);

  try {
    await ScheduleService.guardarConfigJornada({ fecha, apertura, cierre, intervalo });
    alert('¡Jornada actualizada!');
    await cargar();
  } catch (err) {
    alert(err.message || 'Error al guardar.');
  }
}

function cambiarDia(delta) {
  const fecha = new Date(elFechaAdmin.value + 'T00:00:00');
  fecha.setDate(fecha.getDate() + delta);
  elFechaAdmin.value = fecha.toISOString().split('T')[0];
  cargar();
}

async function toggleDiaCompleto() {
  const fecha = elFechaAdmin.value;
  try {
    await ScheduleService.toggleDiaCompleto(fecha);
    await cargar();
  } catch (err) { /* silencioso, igual que el original */ }
}

export const AgendaController = {
  init({ onCambio } = {}) {
    onCambioParaHistorial = onCambio || (() => {});

    elFechaAdmin = qs('inpFechaAdmin');
    elGrilla = qs('grillaAdmin');
    elPopover = qs('popoverSlot');
    elPopoverContenido = qs('popoverContenido');
    elBtnToggleDia = qs('btnToggleDia');
    elBtnToggleDiaTexto = qs('btnToggleDiaTexto');

    elFechaAdmin.value = hoyISO();
    elFechaAdmin.addEventListener('change', cargar);

    qs('guardarConfigJornadaBtn')?.addEventListener('click', guardarConfiguracionJornada);
    qs('btnDiaAnterior')?.addEventListener('click', () => cambiarDia(-1));
    qs('btnDiaSiguiente')?.addEventListener('click', () => cambiarDia(1));
    elBtnToggleDia.addEventListener('click', toggleDiaCompleto);

    document.addEventListener('click', (e) => {
      if (!elPopover.contains(e.target) && !e.target.closest('#grillaAdmin')) {
        elPopover.classList.add('hidden');
      }
    });
  },

  cargar,
};
