/**
 * modules/admin/admin.controller.js
 *
 * Orquesta el panel admin completo: navegación entre secciones (barra
 * lateral) y montaje de los sub-controllers. Migrado desde
 * cambiarTabAdmin() del index.html original, pero reemplazando el
 * if/else por un registro de secciones — este es el punto de extensión
 * que permite agregar un módulo nuevo al admin sin tocar ninguno de los
 * existentes: solo se agrega una entrada a TABS.
 */
import { qs } from '../../shared/utils/dom.utils.js';
import { DashboardController } from './dashboard.controller.js';
import { AgendaController } from './agenda.controller.js';
import { ServiciosAdminController } from './servicios.controller.js';
import { HistorialController } from './historial.controller.js';
import { ContentAdminController } from './content-admin.controller.js';

// Registro de secciones: agregar un módulo nuevo al admin es agregar una fila acá.
const TABS = [
  { key: 'dashboard', contentId: 'tabContentDashboard', btnId: 'tabBtnDashboard', onShow: () => DashboardController.cargar() },
  { key: 'agenda', contentId: 'tabContentAgenda', btnId: 'tabBtnAgenda', onShow: () => AgendaController.cargar() },
  { key: 'servicios', contentId: 'tabContentServicios', btnId: 'tabBtnServicios', onShow: () => ServiciosAdminController.render() },
  { key: 'historial', contentId: 'tabContentHistorial', btnId: 'tabBtnHistorial', onShow: () => HistorialController.cargar() },
  { key: 'contenido', contentId: 'tabContentContenido', btnId: 'tabBtnContenido', onShow: () => ContentAdminController.cargarTodo() },
  { key: 'apariencia', contentId: 'tabContentApariencia', btnId: 'tabBtnApariencia', onShow: () => {} },
];

function cambiarTab(tabKey) {
  TABS.forEach((tab) => {
    qs(tab.contentId).classList.add('hidden');
    qs(tab.btnId).className = 'sidebar-link';
  });

  const activo = TABS.find((t) => t.key === tabKey);
  if (!activo) return;

  qs(activo.contentId).classList.remove('hidden');
  qs(activo.btnId).className = 'sidebar-link-activo';
  activo.onShow();
}

export const AdminController = {
  init() {
    TABS.forEach((tab) => {
      qs(tab.btnId).addEventListener('click', () => cambiarTab(tab.key));
    });

    DashboardController.init((tabKey) => cambiarTab(tabKey));
    AgendaController.init({ onCambio: () => {
      if (!qs('tabContentHistorial').classList.contains('hidden')) HistorialController.cargar();
    }});
    ServiciosAdminController.init();
    HistorialController.init();
    ContentAdminController.init();

    document.querySelectorAll('[data-close-modal]').forEach((btn) => {
      btn.addEventListener('click', () => qs(btn.dataset.closeModal).classList.add('hidden'));
    });
  },

  /** Se llama cuando el panel se abre (tras login o con sesión ya activa). */
  onPanelAbierto() {
    cambiarTab('dashboard');
  },

  /** Permite a otros controllers (ej. realtime) saber si el panel está visible. */
  estaVisible() {
    return !qs('panelAdmin').classList.contains('hidden');
  },

  refrescarSiVisible() {
    if (!this.estaVisible()) return;
    AgendaController.cargar();
    HistorialController.cargar();
  },
};
