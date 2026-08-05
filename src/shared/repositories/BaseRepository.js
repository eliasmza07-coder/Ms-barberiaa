/**
 * shared/repositories/BaseRepository.js
 *
 * CRUD genérico reutilizado por todos los repositories del proyecto.
 * Es la ÚNICA capa (junto con AuthService/RealtimeService) que toca
 * `supabaseClient.from(...)`. Ningún controller, service de negocio o
 * componente de UI debe importar supabaseClient directamente.
 */
import { supabaseClient } from '../../config/supabaseClient.js';

export class BaseRepository {
  constructor(table) {
    this.table = table;
    this.client = supabaseClient;
  }

  async findAll(orderBy) {
    let q = this.client.from(this.table).select('*');
    if (orderBy) q = q.order(orderBy.column, { ascending: orderBy.ascending ?? true });
    return q;
  }

  async findById(id) {
    return this.client.from(this.table).select('*').eq('id', id).maybeSingle();
  }

  async findWhere(filters = {}) {
    let q = this.client.from(this.table).select('*');
    for (const [key, value] of Object.entries(filters)) {
      q = q.eq(key, value);
    }
    return q;
  }

  async create(payload) {
    return this.client.from(this.table).insert(payload);
  }

  async update(id, payload) {
    return this.client.from(this.table).update(payload).eq('id', id);
  }

  async upsert(payload, opts) {
    return this.client.from(this.table).upsert(payload, opts);
  }

  async remove(id) {
    return this.client.from(this.table).delete().eq('id', id);
  }
}
