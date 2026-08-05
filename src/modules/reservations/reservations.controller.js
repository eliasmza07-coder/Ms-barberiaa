/**
 * modules/reservations/reservations.controller.js
 *
 * Orquesta el flujo de reserva como un wizard real: un paso a la vez
 * (Servicio → Fecha → Hora → Datos), con Atrás/Siguiente/Cancelar, y vive
 * en un modal de pantalla completa separado de la página informativa —
 * se abre al tocar "Reservar Ahora" y no interfiere con el resto del sitio.
 *
 * Después de enviar, el modal muestra una tarjeta de seguimiento que se
 * actualiza SOLA cuando el barbero confirma el turno (vía RealtimeService),
 * sin que el cliente tenga que recargar la página.
 */
import { qs, refreshIcons } from '../../shared/utils/dom.utils.js';
import { NotificationService } from '../../shared/services/NotificationService.js';
import { store } from '../../shared/state/store.js';
import { hoyISO } from '../../shared/utils/date.utils.js';
import { turnoStorage } from '../../shared/utils/local-storage.utils.js';
import { AuthService } from '../../shared/services/AuthService.js';
import { ServicesCatalogService } from '../services-catalog/services-catalog.service.js';
import { ScheduleService } from '../schedule/schedule.service.js';
import { ReservationsService } from './reservations.service.js';
import {
  renderListaServicios,
  poblarSelectServicios,
  renderTarjetasServicio,
  renderGridHorarios,
  marcarHoraSeleccionada,
  mostrarCargando,
  mostrarFechaPasada,
  mostrarErrorHorarios,
  renderProgreso,
  mostrarPasoPanel,
  actualizarNavegacion,
  mostrarFormulario,
  mostrarSeguimiento,
  actualizarEstadoSeguimiento,
  mostrarBadgeSeguimiento,
  ocultarBadgeSeguimiento,
} from './components/ReservationForm/ReservationForm.js';

const TOTAL_PASOS = 4;
let elGrid, elFecha, elSelect, elLblHorario;
let pasoActual = 1;
let turnoEnSeguimiento = null; // { id, fecha, hora, servicio_nombre, precio, estado }

// ---------- Navegación del wizard ----------
function pasosCompletados() {
  const completados = [];
  if (store.servicioSeleccionado) completados.push(1);
  if (elFecha.value) completados.push(2);
  if (store.horaSeleccionada) completados.push(3);
  return completados;
}

function refrescarIndicador() {
  renderProgreso(pasoActual, pasosCompletados(), irAPaso);
}

function irAPaso(n) {
  pasoActual = n;
  mostrarPasoPanel(n);
  actualizarNavegacion(n, TOTAL_PASOS);
  refrescarIndicador();
  qs('msgReserva').textContent = '';
  if (n === 3 && elFecha.value) refrescarHorarios();
  actualizarBotonConfirmar();
}

function avanzarPaso() {
  if (pasoActual === 2) {
    const hoyStr = hoyISO();
    if (!elFecha.value || elFecha.value < hoyStr) {
      NotificationService.error('msgReserva', 'Elegí una fecha válida.');
      return;
    }
  }
  if (pasoActual === 3 && !store.horaSeleccionada) {
    NotificationService.error('msgReserva', 'Elegí un horario disponible.');
    return;
  }
  if (pasoActual < TOTAL_PASOS) irAPaso(pasoActual + 1);
}

function retrocederPaso() {
  if (pasoActual > 1) irAPaso(pasoActual - 1);
}

function actualizarBotonConfirmar() {
  const nombre = qs('inpNombre').value.trim();
  const telefono = qs('inpTelefono').value.trim();
  qs('btnConfirmar').disabled = !(store.horaSeleccionada && nombre && telefono);
}

/** El aviso flotante solo se muestra fuera del modal (adentro ya está la tarjeta de seguimiento). */
function actualizarBadgeSeguimiento() {
  const modalAbierto = !qs('modalReserva').classList.contains('hidden');
  if (turnoEnSeguimiento && !modalAbierto) {
    mostrarBadgeSeguimiento(turnoEnSeguimiento.estado);
  } else {
    ocultarBadgeSeguimiento();
  }
}

// ---------- Abrir / cerrar el modal ----------
function abrirModalReserva() {
  qs('modalMisTurnos').classList.add('hidden');
  qs('modalReserva').classList.remove('hidden');
  document.body.style.overflow = 'hidden';
  refreshIcons();
  if (turnoEnSeguimiento) {
    mostrarSeguimiento(turnoEnSeguimiento);
  } else {
    mostrarFormulario();
    irAPaso(1);
  }
  actualizarBadgeSeguimiento();
}

function cerrarModalReserva() {
  qs('modalReserva').classList.add('hidden');
  document.body.style.overflow = '';
  actualizarBadgeSeguimiento();
}

// ---------- Catálogo y horarios ----------
async function refrescarCatalogo() {
  const idPrevio = store.servicioSeleccionado?.id ?? null;
  await ServicesCatalogService.cargar();
  renderListaServicios(qs('listaServicios'), ServicesCatalogService.obtenerTodos());
  poblarSelectServicios(elSelect, ServicesCatalogService.obtenerTodos());

  // Si el cliente ya había elegido un servicio y sigue existiendo en el
  // catálogo actualizado, lo mantenemos — evita "perder" la selección a
  // mitad de la reserva por un cambio de datos que no tiene nada que ver.
  const sigueExistiendo = idPrevio && ServicesCatalogService.obtenerPorId(idPrevio);
  store.servicioSeleccionado = sigueExistiendo || ServicesCatalogService.obtenerTodos()[0] || null;
  if (sigueExistiendo) elSelect.value = idPrevio;

  pintarTarjetasServicio();
  refrescarIndicador();
  if (elFecha.value) await refrescarHorarios();
}

function pintarTarjetasServicio() {
  renderTarjetasServicio(
    qs('tarjetasServicio'),
    ServicesCatalogService.obtenerTodos(),
    store.servicioSeleccionado?.id,
    (id) => {
      store.servicioSeleccionado = ServicesCatalogService.obtenerPorId(id);
      elSelect.value = id;
      pintarTarjetasServicio();
      refrescarHorarios();
      refrescarIndicador();
    }
  );
}

async function refrescarHorarios() {
  const fecha = elFecha.value;
  if (!fecha) return;

  const hoyStr = hoyISO();
  if (fecha < hoyStr) {
    mostrarFechaPasada(elGrid);
    return;
  }

  mostrarCargando(elGrid);
  store.horaSeleccionada = null;
  refrescarIndicador();
  actualizarBotonConfirmar();

  try {
    const duracion = store.servicioSeleccionado ? store.servicioSeleccionado.duracion : 30;
    const { jornada, bloques } = await ScheduleService.calcularDisponibilidadCliente(fecha, duracion);
    elLblHorario.textContent = `${String(jornada.apertura).padStart(2, '0')}:00 – ${String(jornada.cierre).padStart(2, '0')}:00`;
    renderGridHorarios(elGrid, bloques);
  } catch (err) {
    console.error(err);
    mostrarErrorHorarios(elGrid);
  }
}

// ---------- Envío y seguimiento ----------
async function handleEnviarReserva() {
  const btn = qs('btnConfirmar');
  const fecha = elFecha.value;
  const hora = store.horaSeleccionada;
  const nombre = qs('inpNombre').value.trim();
  const telefono = qs('inpTelefono').value.trim();
  const servicio = store.servicioSeleccionado;

  btn.disabled = true;
  btn.textContent = 'Enviando...';

  try {
    await ReservationsService.crearSolicitud({ fecha, hora, nombre, telefono, servicio });

    // La Edge Function no devuelve el id del turno creado, así que lo
    // buscamos por la combinación fecha+hora+teléfono para poder seguirlo.
    const creado = await ReservationsService.buscarRecienCreado({ fecha, hora, telefono });

    // Si el cliente estaba logueado, este turno queda guardado en su
    // cuenta — así aparece después en "Mis Turnos" sin que tenga que
    // volver a escribir nada.
    const sesion = await AuthService.getSession();
    if (sesion && creado?.id) {
      await ReservationsService.vincularCliente(creado.id, sesion.user.id);
    }

    turnoEnSeguimiento = {
      id: creado?.id ?? null,
      fecha,
      hora,
      servicio_nombre: servicio.nombre,
      precio: servicio.precio,
      estado: creado?.estado || 'pendiente',
    };
    turnoStorage.guardar(turnoEnSeguimiento);
    mostrarSeguimiento(turnoEnSeguimiento);
    actualizarBadgeSeguimiento();

    qs('inpNombre').value = '';
    qs('inpTelefono').value = '';
    store.horaSeleccionada = null;
  } catch (err) {
    NotificationService.error('msgReserva', err.message || 'Hubo un error al enviar.');
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i data-lucide="check-circle" class="w-4 h-4"></i> Confirmar Solicitud';
    refreshIcons();
  }
}

/** Se llama en cada evento de RealtimeService: si hay un turno en seguimiento, revisa si cambió de estado. */
async function revisarEstadoSeguimiento() {
  if (!turnoEnSeguimiento || !turnoEnSeguimiento.id) return;
  const actual = await ReservationsService.obtenerPorId(turnoEnSeguimiento.id);
  // Si ya no existe la fila, es porque el barbero canceló el turno
  // (esa acción borra la fila en vez de solo cambiar el estado).
  const estadoReal = actual ? actual.estado : 'cancelado';
  if (estadoReal !== turnoEnSeguimiento.estado) {
    turnoEnSeguimiento.estado = estadoReal;
    turnoStorage.guardar(turnoEnSeguimiento);
    actualizarEstadoSeguimiento(estadoReal);
    actualizarBadgeSeguimiento();
  }
}

function volverAFormulario() {
  turnoEnSeguimiento = null;
  turnoStorage.borrar();
  mostrarFormulario();
  irAPaso(1);
  actualizarBadgeSeguimiento();
}

async function restaurarSeguimientoGuardado() {
  const guardado = turnoStorage.leer();
  if (!guardado) return;

  if (guardado.id) {
    const actual = await ReservationsService.obtenerPorId(guardado.id);
    guardado.estado = actual ? actual.estado : 'cancelado';
  }
  // Solo se guarda en memoria acá — se muestra recién cuando el cliente
  // abre el modal (abrirModalReserva), no fuerza la apertura solo.
  turnoEnSeguimiento = guardado;
  actualizarBadgeSeguimiento();
}

export const ReservationsController = {
  async init() {
    elGrid = qs('gridHorarios');
    elFecha = qs('inpFecha');
    elSelect = qs('selServicio');
    elLblHorario = qs('lblHorarioFicha');

    const hoy = hoyISO();
    elFecha.value = hoy;
    elFecha.min = hoy;

    document.querySelectorAll('[data-action="abrir-reserva"]').forEach((el) => {
      el.addEventListener('click', (e) => { e.preventDefault(); abrirModalReserva(); });
    });
    qs('btnCerrarModalReserva').addEventListener('click', cerrarModalReserva);
    qs('btnPasoCancelar').addEventListener('click', cerrarModalReserva);
    qs('btnPasoAtras').addEventListener('click', retrocederPaso);
    qs('btnPasoSiguiente').addEventListener('click', avanzarPaso);
    qs('btnAbrirDesdeBadge').addEventListener('click', abrirModalReserva);
    qs('btnCerrarBadge').addEventListener('click', (e) => {
      e.stopPropagation();
      ocultarBadgeSeguimiento();
    });

    elFecha.addEventListener('change', () => { refrescarHorarios(); refrescarIndicador(); });
    elGrid.addEventListener('click', (e) => {
      const btn = e.target.closest('.slot-btn');
      if (!btn || btn.disabled) return;
      store.horaSeleccionada = btn.dataset.hora;
      marcarHoraSeleccionada(elGrid, btn);
      refrescarIndicador();
    });
    ['inpNombre', 'inpTelefono'].forEach((id) => {
      qs(id).addEventListener('input', actualizarBotonConfirmar);
    });
    qs('btnConfirmar').addEventListener('click', handleEnviarReserva);
    qs('btnNuevaReserva').addEventListener('click', volverAFormulario);

    await refrescarCatalogo();
    await restaurarSeguimientoGuardado();
  },

  // Expuesto para que RealtimeService y el módulo admin puedan pedir un refresh.
  refrescarCatalogo,
  refrescarHorarios,
  revisarEstadoSeguimiento,
};
