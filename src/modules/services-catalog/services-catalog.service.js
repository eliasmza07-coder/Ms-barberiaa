/**
 * modules/services-catalog/services-catalog.service.js
 *
 * Reemplaza al archivo del mismo nombre. Dos cambios respecto del actual:
 *
 * 1) BUG CORREGIDO — creación de servicios.
 *    El código actual hace:
 *        if (!id) payload.id = 'serv_' + Date.now();
 *    En tu base real `servicios.id` es int8 (bigint), no text. Mandar un id
 *    de texto contra una columna bigint devuelve 400 (`invalid input syntax
 *    for type bigint`), así que **crear un servicio nuevo desde el panel
 *    falla siempre**, mientras que editar uno existente funciona (ahí ya
 *    viaja el id numérico que vino de la base).
 *    Ahora, al crear, simplemente NO se manda el id: lo genera la base.
 *    (La migración 006 le asigna una secuencia a la columna si no la tenía.)
 *
 * 2) Soporte para activar/desactivar en vez de borrar. Eliminar un servicio
 *    que tiene turnos futuros es destructivo; desactivarlo lo saca de la
 *    página pública y lo deja fuera de nuevas reservas, sin tocar el
 *    historial.
 */
import { servicesCatalogRepository } from './services-catalog.repository.js';
import { store } from '../../shared/state/store.js';
import { SERVICIOS_FALLBACK } from '../../config/constants.js';

export const ServicesCatalogService = {
  /** Catálogo público: solo servicios activos. */
  async cargar({ incluirInactivos = false } = {}) {
    try {
      const { data, error } = await servicesCatalogRepository.listarOrdenados();
      const lista = !error && data ? data : [];
      const visibles = incluirInactivos ? lista : lista.filter((s) => s.activo !== false);
      store.servicios = visibles.length > 0 ? visibles : SERVICIOS_FALLBACK;
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
    return store.servicios.find((s) => String(s.id) === String(id));
  },

  /** Varios servicios a la vez, para el flujo multi-servicio del wizard. */
  obtenerVarios(ids = []) {
    return ids.map((id) => this.obtenerPorId(id)).filter(Boolean);
  },

  /**
   * Crea o edita un servicio.
   * Al crear NO se envía `id`: lo genera la base de datos. Ese era el bug.
   */
  async guardar({ id, nombre, precio, duracion, desc, activo = true, orden = 0, margenDespuesMin = null }) {
    if (!nombre || !String(nombre).trim()) throw new Error('El servicio necesita un nombre.');
    if (!(Number(duracion) > 0)) throw new Error('La duración tiene que ser mayor a cero.');

    const payload = {
      nombre: String(nombre).trim(),
      precio: Number(precio) || 0,
      duracion: Number(duracion),
      desc: desc ?? null,
      orden: Number(orden) || 0,
      activo,
    };
    if (margenDespuesMin !== null) payload.margen_despues_min = Number(margenDespuesMin);

    // Solo al EDITAR se manda el id. Al crear, lo pone la base.
    if (id !== undefined && id !== null && id !== '') payload.id = id;

    const { error } = await servicesCatalogRepository.guardar(payload);
    if (error) throw error;
  },

  /** Preferida sobre eliminar: no rompe el historial ni los turnos futuros. */
  async desactivar(id) {
    const { error } = await servicesCatalogRepository.guardar({ id, activo: false });
    if (error) throw error;
  },

  async activar(id) {
    const { error } = await servicesCatalogRepository.guardar({ id, activo: true });
    if (error) throw error;
  },

  /**
   * Borrado real. Avisa si hay turnos futuros que lo usan: en ese caso lo
   * correcto casi siempre es desactivar, no eliminar.
   */
  async eliminar(id, { forzar = false } = {}) {
    if (!forzar) {
      const enUso = await servicesCatalogRepository.turnosFuturosConServicio(id);
      if (enUso > 0) {
        throw new Error(
          `Ese servicio está en ${enUso} turno(s) futuro(s). Desactivalo en vez de borrarlo, así no se rompe la agenda.`
        );
      }
    }
    return servicesCatalogRepository.eliminar(id);
  },
};
