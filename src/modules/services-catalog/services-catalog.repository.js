/**
 * modules/services-catalog/services-catalog.repository.js
 *
 * Reemplaza al archivo del mismo nombre. Cambios:
 *   • ordena por `orden` y después por nombre (antes ordenaba por id, así
 *     que el orden de la carta dependía de cuándo se creó cada servicio);
 *   • agrega `turnosFuturosConServicio()` para poder avisar antes de borrar.
 */
import { BaseRepository } from '../../shared/repositories/BaseRepository.js';

class ServicesCatalogRepository extends BaseRepository {
  constructor() {
    super('servicios');
  }

  async listarOrdenados() {
    return this.client
      .from(this.table)
      .select('*')
      .order('orden', { ascending: true })
      .order('nombre', { ascending: true });
  }

  async guardar(payload) {
    // Sin id → insert (la base genera el id). Con id → update parcial.
    if (payload.id === undefined || payload.id === null || payload.id === '') {
      const { id, ...sinId } = payload;
      return this.client.from(this.table).insert(sinId);
    }
    const { id, ...campos } = payload;
    return this.client.from(this.table).update(campos).eq('id', id);
  }

  /** Cuántos turnos futuros usan este servicio (para no borrar a ciegas). */
  async turnosFuturosConServicio(servicioId) {
    const hoy = new Date().toISOString().slice(0, 10);
    const { count } = await this.client
      .from('turno_servicios')
      .select('turno_id, turnos!inner(fecha, estado)', { count: 'exact', head: true })
      .eq('servicio_id', servicioId)
      .gte('turnos.fecha', hoy)
      .in('turnos.estado', ['pendiente', 'confirmado']);
    return count || 0;
  }

  async eliminar(id) {
    return this.remove(id);
  }
}

export const servicesCatalogRepository = new ServicesCatalogRepository();
