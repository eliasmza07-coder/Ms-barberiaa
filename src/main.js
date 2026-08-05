/**
 * src/main.js
 * Punto de entrada de la aplicación. Reemplaza al bloque
 * document.addEventListener('DOMContentLoaded', ...) del index.html
 * original, pero delegando cada responsabilidad a su controller de módulo
 * en vez de tener toda la lógica en un único callback gigante.
 */
import './styles/main.css';

import { refreshIcons } from './shared/utils/dom.utils.js';
import { RealtimeService } from './shared/services/RealtimeService.js';

import { LandingController } from './modules/landing/landing.controller.js';
import { ReservationsController } from './modules/reservations/reservations.controller.js';
import { MisTurnosController } from './modules/reservations/mis-turnos.controller.js';
import { AuthController } from './modules/auth/auth.controller.js';
import { CustomerAuthController } from './modules/auth/customer-auth.controller.js';
import { AdminController } from './modules/admin/admin.controller.js';

/** Ejecuta un paso de arranque; si falla, lo loguea con su nombre y no frena los demás pasos. */
async function paso(nombre, fn) {
  try {
    await fn();
  } catch (err) {
    console.error(`[main.js] Falló la inicialización de "${nombre}":`, err);
  }
}

async function bootstrap() {
  refreshIcons();

  // Cada módulo arranca de forma independiente: si el contenido del CMS
  // falla (ej. todavía no corriste la migración 002), igual se inicializan
  // las reservas y el panel admin — antes, un error en cualquiera de estos
  // pasos frenaba en seco TODO lo que venía después.
  await paso('landing (contenido)', () => LandingController.init());
  await paso('reservas', () => ReservationsController.init());
  await paso('mis turnos', () => MisTurnosController.init());
  await paso('cuentas de cliente', () => CustomerAuthController.init());
  await paso('panel admin', () => AdminController.init());
  await paso('autenticación', () => AuthController.init(() => AdminController.onPanelAbierto()));

  await paso('tiempo real', async () => {
    // Igual que suscribirseRealtime() en el original: cualquier cambio en
    // cualquier tabla refresca el catálogo/horarios públicos y, si el panel
    // admin está abierto, también su agenda e historial. Ahora también
    // refresca el contenido editable (hero, footer, galería, faq, etc.)
    RealtimeService.onChange(() => {
      ReservationsController.refrescarCatalogo();
      ReservationsController.revisarEstadoSeguimiento();
      LandingController.refrescarTodo();
      AdminController.refrescarSiVisible();
    });
    RealtimeService.start();
  });
}

document.addEventListener('DOMContentLoaded', bootstrap);
