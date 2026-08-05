Reservado para una futura extracción de esta sección a componente propio.

Hoy esta parte de la UI vive como markup estático en `index.html` (igual que en el proyecto original) porque no tiene lógica dinámica propia: no hace falta separarla en un archivo JS todavía. Cuando se conecte al CMS (ver `docs/ARCHITECTURE.md`, sección 5) o gane interactividad propia, su JS y CSS van acá, siguiendo el mismo patrón que `modules/reservations/components/ReservationForm/`.
