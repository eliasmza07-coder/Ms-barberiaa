/**
 * shared/services/ScrollRevealService.js
 * Anima secciones de la landing a medida que entran en pantalla al hacer
 * scroll (antes solo el Hero tenía animación de entrada). Cualquier
 * elemento con el atributo data-reveal se activa solo, sin que cada
 * módulo tenga que manejarlo por separado.
 */
export function iniciarScrollReveal() {
  const elementos = document.querySelectorAll('[data-reveal]');
  if (!('IntersectionObserver' in window) || elementos.length === 0) {
    // Sin soporte (muy raro hoy) o nada que animar: los deja visibles tal cual.
    elementos.forEach((el) => el.classList.remove('opacity-0'));
    return;
  }

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.remove('opacity-0');
          entry.target.classList.add('animate-fade-in-up');
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.12, rootMargin: '0px 0px -60px 0px' }
  );

  elementos.forEach((el) => observer.observe(el));
}

/** Compacta el header a medida que se hace scroll hacia abajo. */
export function iniciarNavbarCompacto() {
  const header = document.querySelector('header');
  if (!header) return;
  let compacto = false;

  window.addEventListener(
    'scroll',
    () => {
      const debeSerCompacto = window.scrollY > 40;
      if (debeSerCompacto !== compacto) {
        compacto = debeSerCompacto;
        header.classList.toggle('header-compacto', compacto);
      }
    },
    { passive: true }
  );
}
