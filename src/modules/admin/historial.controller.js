/**
 * modules/admin/historial.controller.js
 * Orquesta el tab "Historial" del panel admin.
 * Migrado desde cargarHistorialGeneral() del index.html original.
 */
import { qs } from '../../shared/utils/dom.utils.js';
import { ReservationsService } from '../reservations/reservations.service.js';
import { renderHistorial, mostrarCargandoHistorial, mostrarErrorHistorial } from './components/Historial/Historial.js';

async function cargar() {
  const tbody = qs('tbodyHistorial');
  mostrarCargandoHistorial(tbody);

  try {
    const turnos = await ReservationsService.listarHistorial();
    renderHistorial(tbody, turnos, { onBorrar: borrar });
  } catch (err) {
    mostrarErrorHistorial(tbody);
  }
}

async function borrar(id) {
  await ReservationsService.liberar(id);
  await cargar();
}

export const HistorialController = {
  init() {
    qs('btnActualizarHistorial')?.addEventListener('click', cargar);
  },
  cargar,
};
