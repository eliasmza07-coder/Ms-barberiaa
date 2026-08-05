/**
 * modules/services-catalog/services-catalog.service.js
 * Reglas de negocio del catálogo de servicios. Migrado desde
 * cargarServiciosDB(), guardarServicioDB(), eliminarServicio() del
 * index.html original.
 */
import { servicesCatalogRepository } from './services-catalog.repository.js';
import { store } from '../../shared/state/store.js';
import { SERVICIOS_FALLBACK } from '../../config/constants.js';

export const ServicesCatalogService = {
  /** Carga los servicios desde la base; si falla o está vacía, usa el fallback. */
  async cargar() {
    try {
      const { data, error } = await servicesCatalogRepository.listarOrdenados();
      store.servicios = !error && data && data.length > 0 ? data : SERVICIOS_FALLBACK;
    } catch (e) {
      console.error('[ServicesCatalogService] error al cargar servicios', e);
      store.servicios = SERVICIOS_FALLBACK;
    }
    return store.servicios;
  },

  obtenerTodos() {
    return store.servicios;
  },

  obtenerPorId(id) {
    return store.servicios.find((s) => s.id == id);
  },

  /** Guarda (crea o edita) un servicio. Si no tiene id, genera uno como en el original. */
  async guardar({ id, nombre, precio, duracion, desc }) {
    // orden: 0 es defensivo — tu tabla real tiene esa columna aunque el
    // código no la use para ordenar (ordena por id); sin este valor,
    // guardar podía fallar con error 400 si esa columna no tiene default.
    const payload = { nombre, precio, duracion, desc, orden: 0 };
    if (!id) payload.id = 'serv_' + Date.now();
    else payload.id = id;

    const { error } = await servicesCatalogRepository.guardar(payload);
    if (error) throw error;
  },

  async eliminar(id) {
    return servicesCatalogRepository.eliminar(id);
  },
};
