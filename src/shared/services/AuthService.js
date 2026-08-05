/**
 * shared/services/AuthService.js
 * Envuelve Supabase Auth. Migrado desde iniciarSesion/cerrarSesionAdmin/abrirAdmin
 * del index.html original. Es el único lugar (junto a BaseRepository y
 * RealtimeService) que toca supabaseClient directamente.
 */
import { supabaseClient } from '../../config/supabaseClient.js';

export const AuthService = {
  async login(email, password) {
    const { error } = await supabaseClient.auth.signInWithPassword({ email, password });
    if (error) throw error;
  },

  /** Registro de cliente (cuenta opcional en el flujo de reservas). El trigger
   * de la base crea el perfil automáticamente con rol 'cliente'. */
  async registrarCliente({ email, password, nombre, telefono }) {
    const { error } = await supabaseClient.auth.signUp({
      email,
      password,
      options: { data: { nombre, telefono } },
    });
    if (error) throw error;
  },

  async logout() {
    await supabaseClient.auth.signOut();
  },

  async getSession() {
    const { data } = await supabaseClient.auth.getSession();
    return data.session;
  },

  /** Trae el perfil (nombre, teléfono, rol) del usuario con sesión activa, o null si no hay sesión.
   * Si ya se tiene la sesión a mano (ej. la que entrega onAuthStateChange), se puede pasar
   * directamente para evitar una consulta getSession() extra e innecesaria. */
  async getPerfilActual(sessionConocida) {
    const session = sessionConocida ?? (await this.getSession());
    if (!session) return null;
    const { data } = await supabaseClient.from('perfiles').select('*').eq('id', session.user.id).maybeSingle();
    return data || null;
  },

  onAuthStateChange(callback) {
    return supabaseClient.auth.onAuthStateChange((_event, session) => callback(session));
  },
};
