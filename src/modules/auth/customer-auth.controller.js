/**
 * modules/auth/customer-auth.controller.js
 *
 * Identificación OPCIONAL del cliente dentro del wizard de reservas:
 * "Iniciar sesión", "Crear cuenta" o seguir como invitado (comportamiento
 * de siempre, sin tocar). Si el cliente se loguea, sus datos (nombre,
 * teléfono) se completan solos en el paso 4 — no tiene que volver a
 * tipearlos la próxima vez que reserve.
 *
 * Usa el mismo Supabase Auth que el panel admin, pero nunca abre el panel:
 * auth.controller.js es quien decide eso, según el rol del perfil.
 */
import { qs } from '../../shared/utils/dom.utils.js';
import { AuthService } from '../../shared/services/AuthService.js';

function mostrarSoloUno(idAMostrar) {
  ['cuentaInvitado', 'cuentaFormLogin', 'cuentaFormRegistro', 'cuentaLogueado'].forEach((id) => {
    qs(id).classList.toggle('hidden', id !== idAMostrar);
  });
}

function aplicarPerfilAlFormulario(perfil) {
  qs('cuentaNombreMostrado').textContent = perfil.nombre || 'Mi cuenta';
  if (perfil.nombre) qs('inpNombre').value = perfil.nombre;
  if (perfil.telefono) qs('inpTelefono').value = perfil.telefono;
  mostrarSoloUno('cuentaLogueado');
  // Dispara el evento 'input' para que reservations.controller.js recalcule
  // si el botón de confirmar ya puede habilitarse.
  qs('inpNombre').dispatchEvent(new Event('input'));
}

async function handleLogin() {
  const email = qs('caLoginEmail').value.trim();
  const pass = qs('caLoginPass').value;
  const msg = qs('msgCuentaLogin');
  try {
    await AuthService.login(email, pass);
    msg.textContent = '';
  } catch (err) {
    msg.textContent = 'Correo o contraseña incorrectos.';
    msg.className = 'text-xs text-center font-mono text-bloqueado';
  }
}

async function handleRegistro() {
  const nombre = qs('caRegNombre').value.trim();
  const telefono = qs('caRegTelefono').value.trim();
  const email = qs('caRegEmail').value.trim();
  const pass = qs('caRegPass').value;
  const msg = qs('msgCuentaRegistro');

  if (!nombre || !telefono || !email || pass.length < 6) {
    msg.textContent = 'Completá todos los campos (contraseña mínimo 6 caracteres).';
    msg.className = 'text-xs text-center font-mono text-bloqueado';
    return;
  }

  try {
    await AuthService.registrarCliente({ email, password: pass, nombre, telefono });
    const session = await AuthService.getSession();
    if (!session) {
      // El proyecto tiene confirmación de correo activada: no hay sesión todavía.
      msg.textContent = '¡Cuenta creada! Revisá tu correo para confirmarla y después iniciá sesión.';
      msg.className = 'text-xs text-center font-mono text-libre';
    }
  } catch (err) {
    msg.textContent = err.message || 'Error al crear la cuenta.';
    msg.className = 'text-xs text-center font-mono text-bloqueado';
  }
}

async function handleCerrarSesion() {
  await AuthService.logout();
  qs('inpNombre').value = '';
  qs('inpTelefono').value = '';
  mostrarSoloUno('cuentaInvitado');
  qs('inpNombre').dispatchEvent(new Event('input'));
}

export const CustomerAuthController = {
  init() {
    qs('btnMostrarLogin').addEventListener('click', () => mostrarSoloUno('cuentaFormLogin'));
    qs('btnMostrarRegistro').addEventListener('click', () => mostrarSoloUno('cuentaFormRegistro'));
    qs('btnCancelarCuentaLogin').addEventListener('click', () => mostrarSoloUno('cuentaInvitado'));
    qs('btnCancelarCuentaRegistro').addEventListener('click', () => mostrarSoloUno('cuentaInvitado'));
    qs('btnCaLogin').addEventListener('click', handleLogin);
    qs('btnCaRegistro').addEventListener('click', handleRegistro);
    qs('btnCuentaCerrarSesion').addEventListener('click', handleCerrarSesion);

    AuthService.onAuthStateChange(async (session) => {
      if (!session) return; // el logout ya lo maneja handleCerrarSesion directamente
      const perfil = await AuthService.getPerfilActual(session);
      if (perfil && perfil.rol !== 'barbero') {
        aplicarPerfilAlFormulario(perfil);
      }
    });
  },
};
