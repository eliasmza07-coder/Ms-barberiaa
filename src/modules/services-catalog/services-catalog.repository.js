/**
 * modules/services-catalog/services-catalog.repository.js
 * Único punto de acceso a la tabla `servicios` (misma tabla que ya existe
 * en el proyecto actual — no se renombra para no romper la base en vivo).
 */
import { BaseRepository } from '../../shared/repositories/BaseRepository.js';

class ServicesCatalogRepository extends BaseRepository {
  constructor() {
    super('servicios');
  }

  async listarOrdenados() {
    return this.findAll({ column: 'id', ascending: true });
  }

  async guardar(payload) {
    return this.upsert(payload);
  }

  async eliminar(id) {
    return this.remove(id);
  }
}

export const servicesCatalogRepository = new ServicesCatalogRepository();
