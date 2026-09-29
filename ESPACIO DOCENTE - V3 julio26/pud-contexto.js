// =========================================================================
// CONTRATO PUD WORKSPACE <-> HERRAMIENTAS (iframes)
//
// Cada herramienta (Secuencias, Tareas y las que se sumen, como la Rúbrica)
// es una página aparte que index.html carga en un iframe del mismo sitio.
// Se comunican solo por postMessage, con estos mensajes:
//
//   Padre -> herramienta   { type: 'pud:context', ctx }
//       Se manda al cargar el iframe y cada vez que cambia el PUD (edición,
//       carga de otro PUD, cierre), con un debounce de ~400 ms.
//       ctx es null si no hay PUD abierto. Si hay, tiene esta forma:
//       {
//         pudId:   string,   // estable entre ediciones y versiones guardadas
//         titulo:  string,
//         grado:   string,   // ej. "3° Grado Primaria", "Sala de 4 años"
//         materia: string,
//         metas:      [{ id: 'm1', texto }],
//         desempenos: [{ id: 'd1' | 'pf', tipo, codigo, texto }]
//       }
//       tipo: 'exploracion' | 'investigacion_guiada' | 'sintesis' | 'sin_clasificar'
//       codigo: lo que figura en la columna UPT del PUD (E, I, PF, GI, ...).
//       El proyecto final del PUD viene como desempeño id 'pf', tipo 'sintesis'.
//
//   Herramienta -> padre   { type: 'tool:dirty', dirty: boolean }
//       La herramienta avisa si tiene cambios sin guardar; el padre muestra
//       un punto naranja en su pestaña.
//
// Ambos lados validan el origen: solo se aceptan mensajes del mismo sitio
// (y, del lado de la herramienta, solo de su ventana padre). Abierto como
// archivo local (file://) el origen es "null" y se acepta ese caso.
//
// Uso típico en una herramienta:
//   PudContexto.alRecibir(ctx => { ...actualizar la UI... });
//   PudContexto.avisarCambios(true);
//   PudContexto.renderBloque(contenedor, ctx, { filtro, conSelector, onFiltro });
// =========================================================================

const PudContexto = (() => {
    const esArchivoLocal = window.location.protocol === 'file:';

    function origenValido(origin) {
        if (origin === window.location.origin) return true;
        return esArchivoLocal && (origin === 'null' || origin === 'file://');
    }

    function destino() {
        return esArchivoLocal ? '*' : window.location.origin;
    }

    function alRecibir(callback) {
        window.addEventListener('message', (event) => {
            if (event.source !== window.parent || !origenValido(event.origin)) return;
            if (!event.data || event.data.type !== 'pud:context') return;
            callback(event.data.ctx || null);
        });
    }

    let ultimoDirty = null;
    function avisarCambios(dirty) {
        const valor = !!dirty;
        if (window.parent === window || valor === ultimoDirty) return;
        ultimoDirty = valor;
        window.parent.postMessage({ type: 'tool:dirty', dirty: valor }, destino());
    }

    const TIPOS = {
        exploracion: 'Exploración',
        investigacion_guiada: 'Investigación guiada',
        sintesis: 'Proyecto final de síntesis',
        sin_clasificar: 'Sin clasificar'
    };

    function desempenosFiltrados(ctx, filtro) {
        const lista = ctx?.desempenos || [];
        return !filtro || filtro === 'todos' ? lista : lista.filter(d => d.tipo === filtro);
    }

    function esc(v) {
        return String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    }

    // Estilos del bloque "Del PUD": se inyectan una sola vez, así cada
    // herramienta no necesita CSS propio para este bloque.
    function inyectarEstilos() {
        if (document.getElementById('del-pud-estilos')) return;
        const style = document.createElement('style');
        style.id = 'del-pud-estilos';
        style.textContent = `
            .del-pud { border: 1px solid #DFE5E5; border-left: 4px solid #F18636; border-radius: 12px; background: #FAFBFA; margin-bottom: 18px; font-size: 0.86rem; color: #26343E; }
            .del-pud > summary { cursor: pointer; padding: 10px 14px; font-weight: 700; list-style: none; display: flex; gap: 8px; align-items: baseline; flex-wrap: wrap; }
            .del-pud > summary::-webkit-details-marker { display: none; }
            .del-pud > summary::before { content: '▸'; color: #F18636; }
            .del-pud[open] > summary::before { content: '▾'; }
            .del-pud > summary:focus-visible { outline: 2px solid #35505E; outline-offset: 2px; border-radius: 10px; }
            .del-pud .del-pud-sub { font-weight: 500; color: #5A6B75; }
            .del-pud .del-pud-cuerpo { padding: 0 14px 12px 30px; }
            .del-pud h4 { margin: 10px 0 4px; font-size: 0.78rem; text-transform: uppercase; letter-spacing: .05em; color: #35505E; }
            .del-pud ul { margin: 0; padding-left: 18px; }
            .del-pud li { margin: 3px 0; line-height: 1.4; }
            .del-pud .del-pud-tipo { display: inline-block; font-size: 0.7rem; font-weight: 700; padding: 1px 7px; border-radius: 999px; background: #EDF1F0; color: #35505E; margin-right: 6px; }
            .del-pud .del-pud-tipo.sin_clasificar { background: #FEF1E6; color: #B45E12; }
            .del-pud select { margin-left: 8px; font: inherit; font-size: 0.8rem; padding: 3px 6px; border: 1px solid #DFE5E5; border-radius: 8px; }
            .del-pud .del-pud-vacio { color: #93A1A9; font-style: italic; }
        `;
        document.head.appendChild(style);
    }

    // Bloque colapsable "Del PUD" con las metas (siempre) y los desempeños
    // según el filtro. conSelector muestra un <select> para cambiar el filtro;
    // onFiltro(nuevoFiltro) se llama cuando el docente lo cambia.
    function renderBloque(contenedor, ctxRecibido, opciones = {}) {
        if (!contenedor) return;
        const ctx = ctxRecibido && { ...ctxRecibido, metas: ctxRecibido.metas || [], desempenos: ctxRecibido.desempenos || [] };
        inyectarEstilos();
        if (!ctx) {
            contenedor.innerHTML = '';
            contenedor.hidden = true;
            return;
        }
        const filtro = opciones.filtro || 'todos';
        const abierto = contenedor.querySelector('details.del-pud')?.open ?? true;
        const desempenos = desempenosFiltrados(ctx, filtro);

        const metasHtml = ctx.metas.length
            ? `<ul>${ctx.metas.map(m => `<li>${esc(m.texto)}</li>`).join('')}</ul>`
            : '<p class="del-pud-vacio">El PUD no tiene metas cargadas.</p>';
        const desempenosHtml = desempenos.length
            ? `<ul>${desempenos.map(d => `<li><span class="del-pud-tipo ${esc(d.tipo)}">${esc(TIPOS[d.tipo] || d.tipo)}</span>${esc(d.texto)}</li>`).join('')}</ul>`
            : '<p class="del-pud-vacio">No hay desempeños de este tipo en el PUD.</p>';
        const selector = opciones.conSelector ? `
            <select aria-label="Qué desempeños mostrar">
                ${[['todos', 'Todos'], ...Object.entries(TIPOS)].map(([valor, texto]) =>
                    `<option value="${valor}"${valor === filtro ? ' selected' : ''}>${texto}</option>`).join('')}
            </select>` : '';

        contenedor.hidden = false;
        contenedor.innerHTML = `
            <details class="del-pud"${abierto ? ' open' : ''}>
                <summary>Del PUD <span class="del-pud-sub">${esc(ctx.titulo)}${ctx.grado ? ' · ' + esc(ctx.grado) : ''}${ctx.materia ? ' · ' + esc(ctx.materia) : ''}</span></summary>
                <div class="del-pud-cuerpo">
                    <h4>Metas de comprensión</h4>
                    ${metasHtml}
                    <h4>Desempeños${selector}</h4>
                    ${desempenosHtml}
                </div>
            </details>`;

        const select = contenedor.querySelector('select');
        if (select && opciones.onFiltro) {
            select.addEventListener('change', () => opciones.onFiltro(select.value));
        }
    }

    return { alRecibir, avisarCambios, renderBloque, desempenosFiltrados, TIPOS, origenValido };
})();
