// =========================================================
// Nivel Inicial (Jardín: Sala de 3, 4 y 5 años)
// Datos y reglas compartidas por el PUD (index.html) y los generadores
// de secuencias (secuencias-epc.html) y tareas (generador-tareas.html),
// para que las tres herramientas traten a las salas igual.
//
// En las salas el nivel de cada idioma queda FIJO por la edad y no usa
// CEFR: esa escala describe a quien aprende una lengua extranjera leyendo
// y escribiendo; a los 3-5 años el inglés se adquiere por exposición,
// juego y rutina. Las variables de ejecución también son cerradas: la IA
// no las decide, para que no "escolarice" la propuesta.
// =========================================================

// Nombres tal como se guardan en pud_history.year y en la tabla grados.
const SALAS_INICIAL = ['Sala de 3 años', 'Sala de 4 años', 'Sala de 5 años'];

function esSalaInicial(year) {
    return SALAS_INICIAL.includes((year || '').trim());
}

const NIVELES_INICIAL = {
    'Sala de 3 años': {
        es: { vocabulario: 'Palabras del entorno inmediato del niño (su cuerpo, su familia, la sala, los juguetes, los animales, la comida). Nada abstracto ni técnico.', gramatica: 'Frases de 2 a 4 palabras, en presente, una sola acción por consigna, con gesto que acompañe. Mucha repetición.' },
        en: { vocabulario: 'Exposición, no enseñanza formal: 6 a 8 palabras o chunks por unidad (hello, colors, animals, body parts), siempre con objeto, imagen o gesto.', gramatica: 'Chunks fijos de rutina y canción ("Let\'s sing!", "Where is...?", "Clap, clap!"). Se espera comprensión con el cuerpo (TPR), no producción: basta con que señalen, imiten o repitan una palabra.' }
    },
    'Sala de 4 años': {
        es: { vocabulario: 'Entorno cercano y experiencias vividas; se pueden sumar palabras nuevas del tema si se muestran con objetos reales o imágenes.', gramatica: 'Frases de 4 a 6 palabras, consignas de hasta 2 pasos, preguntas simples (¿qué?, ¿dónde?, ¿quién?). Rimas y repeticiones.' },
        en: { vocabulario: '8 a 12 palabras o chunks por unidad, del mundo concreto del niño, presentadas con canciones, títeres y juego.', gramatica: 'Chunks de rutina y juego ("I like...", "It\'s a...", "Can I have...?"). Producción de palabras sueltas o frases memorizadas; comprensión de consignas cortas con apoyo gestual.' }
    },
    'Sala de 5 años': {
        es: { vocabulario: 'Entorno y experiencias del niño, con palabras nuevas del tema explicadas con ejemplos que puedan tocar, ver o hacer. Primer contacto lúdico con letras y números, sin ejercitación formal.', gramatica: 'Frases de 5 a 8 palabras, consignas de hasta 3 pasos, primeras explicaciones del tipo "porque". Juegos de palabras, rimas, adivinanzas.' },
        en: { vocabulario: '10 a 15 palabras o chunks por unidad, siempre con apoyo visual o manipulable. Sin lectoescritura en inglés.', gramatica: 'Frases cortas memorizadas y modelos de juego ("I can see a...", "This is my...", "What\'s this? It\'s a..."). Producción oral breve dentro de juegos, canciones y dramatizaciones.' }
    }
};

const EJECUCION_INICIAL = {
    'Sala de 3 años': {
        edad: '3 años',
        minutos: '5 a 10',
        consigna: 'una sola acción por vez',
        agrupamiento: 'grupo total con la docente o juego individual en paralelo (todavía no se espera trabajo cooperativo)',
        materiales: 'grandes y seguros, SIN piezas pequeñas (riesgo de atragantamiento)',
        cuerpo: 'motricidad gruesa (trasladar, apilar, rasgar, amasar, gatear, saltar)',
        letras: 'Sin letras ni números como contenido: aparecen solo si surgen en el juego.'
    },
    'Sala de 4 años': {
        edad: '4 años',
        minutos: '10 a 15',
        consigna: 'de hasta 2 pasos',
        agrupamiento: 'parejas o grupos de 3 a 4 con mediación de la docente',
        materiales: 'variados y seguros, que se puedan explorar con los sentidos',
        cuerpo: 'coordinación y primeras destrezas finas (enhebrar, recortar con tijera de punta roma, pintar)',
        letras: 'Letras y números solo en contexto de juego (el propio nombre, carteles de la sala), sin ejercitación.'
    },
    'Sala de 5 años': {
        edad: '5 años',
        minutos: '15 a 20',
        consigna: 'de hasta 3 pasos',
        agrupamiento: 'pequeños grupos con roles simples y turnos',
        materiales: 'variados, incluyendo materiales de construcción, descarte y naturaleza',
        cuerpo: 'motricidad fina y gruesa integradas en juegos con reglas simples',
        letras: 'Contacto lúdico con letras y números (juegos con el nombre, contar objetos reales, carteles), sin copia, planas ni ejercitación formal.'
    }
};

// Selector de nivel de los generadores: las salas van en un grupo propio,
// iguales en castellano y en inglés (nivel fijo por edad), y el resto de
// los niveles (grados o CEFR) en otro grupo debajo.
function llenarSelectorNivel(select, niveles, etiquetaResto) {
    select.innerHTML = '<option value="">Sin especificar</option>';
    const grupos = [
        ['Jardín (nivel fijo por edad)', SALAS_INICIAL.map(s => [s, s])],
        [etiquetaResto, Object.entries(niveles).map(([valor, info]) => [valor, info.label])]
    ];
    grupos.forEach(([etiqueta, opciones]) => {
        const optgroup = document.createElement('optgroup');
        optgroup.label = etiqueta;
        opciones.forEach(([valor, texto]) => {
            const opt = document.createElement('option');
            opt.value = valor;
            opt.textContent = texto;
            optgroup.appendChild(opt);
        });
        select.appendChild(optgroup);
    });
}

// Frase de inicio de una meta de comprensión en Jardín.
function metaInicial(esIngles) {
    return esIngles ? 'Children will discover...' : 'Los niños y las niñas descubrirán...';
}

// Calibración de vocabulario y sintaxis fija por edad (sin CEFR).
function bloqueCalibracionInicial(year, esIngles) {
    const nivel = NIVELES_INICIAL[year][esIngles ? 'en' : 'es'];
    return `CALIBRACIÓN FIJA POR EDAD (${year}, ${esIngles ? 'inglés' : 'castellano'}; NO usar escalas CEFR/MCER):
- VOCABULARIO: ${nivel.vocabulario}
- GRAMÁTICA/SINTAXIS: ${nivel.gramatica}`;
}

// Reglas generales de Jardín: variables de ejecución, ideas y lenguaje.
// Cada herramienta suma después sus reglas propias de formato.
function bloqueReglasInicial(year, esIngles) {
    const v = EJECUCION_INICIAL[year];
    return `NIVEL INICIAL — ${year.toUpperCase()} (niños y niñas de ${v.edad}).
Estas reglas tienen prioridad sobre cualquier otra instrucción de este prompt.

VARIABLES DE EJECUCIÓN (obligatorias, no las cambies):
- Duración: ${v.minutos} minutos por experiencia, alternando momentos activos y de calma.
- Consignas: orales, ${v.consigna}, siempre acompañadas de gesto, objeto o imagen. Nunca consignas escritas para los niños.
- Agrupamiento: ${v.agrupamiento}.
- Materiales: concretos, manipulables, ${v.materiales}, de los que hay en una sala de jardín.
- Cuerpo y movimiento: ${v.cuerpo}.
- Espacios: sala, rincones o sectores de juego, patio, huerta.
- Cada experiencia tiene inicio (ronda, canción, títere u objeto sorpresa que invita), desarrollo (el juego) y cierre (ronda breve de "¿qué descubrimos?").

IDEAS Y CONTENIDO:
- Todo parte de lo concreto y cercano: el cuerpo, la familia, la sala, los animales, las plantas del patio, el agua, los juegos. Nada de conceptos abstractos, datos, definiciones ni clasificaciones.
- Formatos a usar: juego simbólico y dramático, juego-trabajo en rincones, exploración sensorial, cuentos narrados y títeres, canciones, rimas y adivinanzas, arte y construcción, expresión corporal, juegos con reglas simples, cuidado de la huerta y del ambiente.
- PROHIBIDO: fichas, hojas de trabajo, copiado, dictado, cuestionarios, lectura o escritura obligatoria, exposiciones orales frente al grupo, "investigaciones", tareas para la casa, pantallas como actividad central y juegos con ganadores y perdedores.
- ${v.letras}

LENGUAJE:
- Redactá como lo contaría una maestra jardinera, no como un documento académico. Nada de "analizarán", "investigarán", "argumentarán", "sintetizarán": usá verbos de juego (exploran, juegan, descubren, arman, cantan, prueban, imitan, cuentan, cuidan).
- Hablá de ${esIngles ? '"children"' : '"los niños y las niñas"'}, nunca de ${esIngles ? '"students" o "learners"' : '"estudiantes" o "alumnos"'}.
- Las preguntas dirigidas a los niños son las que un chico de ${v.edad} podría hacerse ("¿Por qué...?", "¿Qué pasa si...?", "¿Cómo...?"), de 10 palabras como máximo.${esIngles ? `
- El inglés se vive, no se enseña: rutinas, canciones, TPR (responder con el cuerpo), juegos y cuentos con imágenes. Nada de traducción, listas para memorizar, lectura ni escritura en inglés.` : ''}`;
}
