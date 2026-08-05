/**
 * modules/reviews/reviews.repository.js
 * Acceso a la tabla `resenas` (ver db/migrations/003_resenas_y_fixes.sql).
 */
import { BaseRepository } from '../../shared/repositories/BaseRepository.js';

class ReviewsRepository extends BaseRepository {
  constructor() { super('resenas'); }

  async listarAprobadas() {
    return this.client
      .from(this.table)
      .select('*')
      .eq('aprobada', true)
      .order('orden', { ascending: true })
      .order('created_at', { ascending: false });
  }

  async listarTodas() {
    return this.client.from(this.table).select('*').order('created_at', { ascending: false });
  }

  async enviarPublica({ cliente_nombre, calificacion, comentario }) {
    // Se inserta siempre con aprobada:false — la política RLS pública solo
    // permite insertar así; el barbero la aprueba después desde el admin.
    return this.client.from(this.table).insert({ cliente_nombre, calificacion, comentario, aprobada: false });
  }

  async aprobar(id) {
    return this.update(id, { aprobada: true });
  }

  async rechazar(id) {
    return this.remove(id);
  }
}

export const reviewsRepository = new ReviewsRepository();
