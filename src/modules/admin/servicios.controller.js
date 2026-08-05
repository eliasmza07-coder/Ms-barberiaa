/**
 * modules/admin/servicios.controller.js
 * Orquesta el tab "Servicios" del panel admin (CRUD sobre el catálogo).
 * Migrado desde abrirModalServicio, guardarServicioDB, eliminarServicio
 * del index.html original.
 */
import { qs } from '../../shared/utils/dom.utils.js';
import { ServicesCatalogService } from '../services-catalog/services-catalog.service.js';
import { renderServiciosAdmin } from './components/ServiciosAdmin/ServiciosAdmin.js';

function render() {
  renderServiciosAdmin(qs('tablaAdminServicios'), ServicesCatalogService.obtenerTodos(), {
    onEditar: abrirModal,
    onEliminar: eliminar,
  });
}

function abrirModal(id = null) {
  const modal = qs('modalServicio');
  const titulo = qs('modalServicioTitulo');

  if (id) {
    const s = ServicesCatalogService.obtenerPorId(id);
    titulo.textContent = 'Editar Servicio';
    qs('servIdEdit').value = s.id;
    qs('servNombre').value = s.nombre;
    qs('servPrecio').value = s.precio;
    qs('servDuracion').value = s.duracion;
    qs('servDesc').value = s.desc || '';
  } else {
    titulo.textContent = 'Nuevo Servicio';
    qs('servIdEdit').value = '';
    qs('servNombre').value = '';
    qs('servPrecio').value = '';
    qs('servDuracion').value = '30';
    qs('servDesc').value = '';
  }
  modal.classList.remove('hidden');
}

async function guardar() {
  const id = qs('servIdEdit').value || null;
  const nombre = qs('servNombre').value.trim();
  const precio = parseFloat(qs('servPrecio').value);
  const duracion = parseInt(qs('servDuracion').value);
  const desc = qs('servDesc').value.trim();

  if (!nombre || isNaN(precio)) {
    alert('Completá nombre y precio.');
    return;
  }

  try {
    await ServicesCatalogService.guardar({ id, nombre, precio, duracion, desc });
    qs('modalServicio').classList.add('hidden');
    await ServicesCatalogService.cargar();
    render();
  } catch (err) {
    alert('Error al guardar: ' + (err.message || 'error desconocido'));
  }
}

async function eliminar(id) {
  if (!confirm('¿Eliminar este servicio?')) return;
  try {
    await ServicesCatalogService.eliminar(id);
    await ServicesCatalogService.cargar();
    render();
  } catch (err) {
    alert('Error al eliminar: ' + (err.message || 'error desconocido'));
  }
}

export const ServiciosAdminController = {
  init() {
    qs('btnNuevoServicio')?.addEventListener('click', () => abrirModal());
    qs('btnGuardarServicio')?.addEventListener('click', guardar);
  },
  render,
};
