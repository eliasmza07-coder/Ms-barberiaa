/**
 * modules/auth/auth.controller.js
 * Login del PANEL ADMIN (el barbero). Migrado desde iniciarSesion(),
 * cerrarSesionAdmin(), abrirAdmin() del index.html original.
 *
 * Ahora valida el rol del perfil antes de abrir el panel: Supabase Auth se
 * comparte con las cuentas de cliente (ver customer-auth.controller.js), así
 * que cualquier sesión iniciada dispara este listener — pero solo se abre
 * el panel si el perfil tiene rol = 'barbero'. Un cliente que inicia sesión
 * para reservar nunca ve el panel admin.
 */
import { qs } from '../../shared/utils/dom.utils.js';
import { AuthService } from '../../shared/services/AuthService.js';

export const AuthController = {
  /**
   * @param {Function} onSesionIniciada - callback a ejecutar cuando hay sesión de BARBERO activa
   *  (el admin.controller.js lo usa para abrir el panel y cargar la agenda).
   */
  init(onSesionIniciada) {
    document.querySelector('[data-action="abrir-admin"]')?.addEventListener('click', () => this.abrirAdmin());
    qs('btnLogin')?.addEventListener('click', () => this.iniciarSesion());
    qs('btnLogout')?.addEventListener('click', () => this.cerrarSesion());

    // ÚNICO lugar que decide si se abre el panel o se rechaza el login.
    // Antes había un segundo chequeo dentro de iniciarSesion() que podía
    // llegar a un resultado distinto a este por una carrera entre ambas
    // consultas — eso causaba el falso "esta cuenta no tiene acceso"
    // incluso con una cuenta de barbero válida. Ahora hay un solo chequeo,
    // usando la sesión que ya entrega el propio evento (sin volver a
    // pedirla), así no puede haber inconsistencia entre dos lecturas.
    AuthService.onAuthStateChange(async (session) => {
      if (!session) {
        qs('panelAdmin').classList.add('hidden');
        return;
      }
      const perfil = await AuthService.getPerfilActual(session);
      if (perfil?.rol === 'barbero') {
        qs('msgLogin').textContent = '';
        qs('modalLogin').classList.add('hidden');
        qs('panelAdmin').classList.remove('hidden');
        onSesionIniciada?.();
      } else {
        // Sesión válida pero no es de barbero (ej. alguien probando con
        // una cuenta de cliente): se avisa y se cierra esa sesión.
        qs('msgLogin').textContent = 'Esta cuenta no tiene acceso al panel.';
        await AuthService.logout();
      }
    });
  },

  async abrirAdmin() {
    const perfil = await AuthService.getPerfilActual();
    if (perfil?.rol === 'barbero') {
      qs('panelAdmin').classList.remove('hidden');
    } else {
      qs('modalLogin').classList.remove('hidden');
    }
  },

  async iniciarSesion() {
    const email = qs('loginEmail').value.trim();
    const pass = qs('loginPass').value;
    qs('msgLogin').textContent = '';
    try {
      await AuthService.login(email, pass);
      // El resultado (abrir el panel o mostrar "sin acceso") lo decide el
      // listener de onAuthStateChange de arriba — no se vuelve a chequear
      // acá para no duplicar la consulta.
    } catch (e) {
      qs('msgLogin').textContent = 'Credenciales inválidas.';
    }
  },

  async cerrarSesion() {
    await AuthService.logout();
    qs('panelAdmin').classList.add('hidden');
  },
};
