# Prompts para Claude en VS Code

Antes de pegar el prompt 2, creá una carpeta `_nuevos/` en la raíz del proyecto y poné ahí `rubrica.html` y `generar-rubrica.ts`.

Pegá los prompts de a uno: primero el 1, probalo, y recién después el 2.

---

## Prompt 1 · Nuevo layout con pestañas + contexto del PUD compartido

```
Quiero rediseñar el layout del PUD Workspace. Hoy el PUD ocupa media pantalla y las herramientas la otra mitad. Antes de tocar nada, leé el código, identificá cómo están armados el layout, el PUD, las herramientas actuales (Secuencias, Tareas y las que haya) y cómo se persisten los datos en Supabase. Mostrame un plan corto con los cambios y los archivos o secciones que vas a tocar, y esperá mi OK.

Objetivo del layout:

1. Toolbar superior con pestañas, una por herramienta: Secuencias, Tareas, Rúbrica, Adaptaciones (deshabilitada, con una etiqueta "Pronto") y un menú "más" para herramientas futuras. Armá un registro de herramientas (array de objetos con id, nombre, estado habilitado, función de montaje) para que sumar una herramienta nueva sea agregar una entrada, sin tocar el layout.
2. Con PUD abierto: el PUD queda en una columna a la izquierda (30% del ancho por defecto) y la herramienta activa ocupa el resto a la derecha.
   - Entre ambos va un divisor arrastrable (mín. 280 px para el PUD, máx. 50%). Doble clic en el divisor alterna entre 30/70 y 50/50.
   - Guardá el ancho elegido en localStorage (envuelto en try/catch).
   - Clic en la pestaña activa, o Esc, colapsa el panel de herramientas y deja el PUD a pantalla completa. Clic en cualquier pestaña lo vuelve a abrir.
3. Sin PUD: la herramienta activa ocupa todo el ancho, con las mismas pestañas arriba.
4. Estado por pestaña: al cambiar de pestaña no destruyas la herramienta anterior; ocultala, así conserva lo que se estaba editando. Montá cada herramienta la primera vez que se abre.
5. Cada herramienta puede avisar que tiene cambios sin guardar; en ese caso la pestaña muestra un punto naranja (#F18636).
6. Estilo: mantené la paleta actual (naranja #F18636, verde lima #A9CF44, azul petróleo #395968). La pestaña activa se funde con el fondo del panel y tiene una línea naranja arriba. Botones reales (<button>), con aria-current en la pestaña activa y foco visible.

Contexto compartido (las herramientas tienen que tomar el contexto del PUD solas):

7. Creá una función getPudContext() que devuelva, a partir del estado actual del PUD:
   { pudId, titulo, grado, materia,
     metas: [{ id, texto }],
     desempenos: [{ id, tipo, texto }] }   // tipo: exploración, investigación guiada, síntesis, etc.
   Los id tienen que ser estables entre ediciones (si hoy las metas o desempeños no tienen id, agregáselo sin romper los PUD ya guardados en pud_history; los viejos se migran al cargarlos). Si no hay PUD abierto, devuelve null.
8. Cuando el PUD cambia (edición, carga de otro PUD, cierre), disparás un evento "pud:changed" con el contexto nuevo, con debounce de ~400 ms.
9. Las herramientas existentes (Secuencias, Tareas) usan ese contexto: en su cabecera muestran un bloque colapsable "Del PUD" con las metas y el desempeño relevante, y se actualizan con "pud:changed". No cambies la lógica interna de esas herramientas más allá de eso.

Restricciones:
- Mantené la arquitectura actual (archivo HTML único, sin build) y no cambies el esquema de Supabase en este paso.
- No rompas atajos, guardado ni login existentes.
- Al terminar, contame qué cambiaste, qué probaste y qué quedó pendiente.
```

---

## Prompt 2 · Integrar el módulo Rúbrica

```
Vamos a sumar la herramienta Rúbrica al PUD Workspace, en la pestaña "Rúbrica" del nuevo layout. En la carpeta _nuevos/ hay dos archivos:

- _nuevos/rubrica.html: el módulo completo, probado. Leelo entero antes de empezar. Lo que hay que incorporar al workspace es lo que está entre los marcadores RUBRICA:CSS START/END y RUBRICA:JS START/END. Todo lo que está fuera (barra de demo, datos de ejemplo, generador simulado) NO va al workspace. Copiá el CSS y el JS sin reescribirlos; si necesitás cambiar algo del módulo, avisame qué y por qué antes.
- _nuevos/generar-rubrica.ts: la Edge Function de Supabase que llama a Claude.

API del módulo (window.RubricaModule):
  const api = RubricaModule.mount(contenedor, {
    context,            // lo que devuelve getPudContext(), o null si no hay PUD
    rubric,             // rúbrica guardada para este PUD, o null
    generate: async (payload) => respuesta,   // ver punto 3
    onSave:   async (rubrica) => ({ id }),    // ver punto 4
    onChange: (rubrica, dirty) => {}          // para el punto naranja de la pestaña
  });
  api.setContext(ctx); api.setRubric(r); api.getRubric(); api.isDirty(); api.destroy();

Pasos (mostrame el plan y esperá mi OK antes de migraciones o deploys):

1. Registrá la herramienta "Rubrica" en el registro de herramientas del layout y montala con RubricaModule.mount la primera vez que se abre la pestaña. Suscribila a "pud:changed" → api.setContext(ctx). Cuando se abre otro PUD, cargá su rúbrica (o null) con api.setRubric.
2. Base de datos: creá una migración con una tabla public.rubricas:
     id uuid pk default gen_random_uuid(),
     user_id uuid not null default auth.uid() references auth.users on delete cascade,
     pud_id  (mismo tipo que usa pud_history para identificar un PUD; revisalo, no lo asumas),
     desempeno_id text, meta_ids text[] not null default '{}',
     escala text not null default 'epc', idioma text not null default 'es-en',
     titulo text, criterios jsonb not null default '[]',
     created_at timestamptz not null default now(), updated_at timestamptz not null default now()
   Con RLS activada y políticas select/insert/update/delete que sigan el mismo criterio que las de pud_history (como mínimo, user_id = auth.uid()). Índice por (user_id, pud_id). Trigger para updated_at.
   Por ahora, una rúbrica por PUD y desempeño: si ya existe para ese pud_id + desempeno_id, se actualiza.
3. Edge Function: copiá _nuevos/generar-rubrica.ts a supabase/functions/generar-rubrica/index.ts. En el front, generate llama:
     const { data, error } = await supabase.functions.invoke('generar-rubrica', { body: payload });
     if (error) throw new Error(<mensaje legible, incluyendo data?.error si viene>);
     return data;
   La API key de Anthropic NO va en el código: decime el comando para cargarla como secreto (supabase secrets set ANTHROPIC_API_KEY=...) y cómo deployar la función.
4. onSave: upsert en public.rubricas con los campos que devuelve api.getRubric() (id, pud_id, desempeno_id, meta_ids, escala, idioma, titulo, criterios) y devolvé { id }.
5. onChange: marcá la pestaña Rúbrica con el punto de cambios sin guardar mientras dirty sea true. Si el docente cierra el PUD o la página con cambios sin guardar, pedí confirmación.
6. Opcional si queda simple: en el panel del PUD, resaltá (fondo #FDF1E7, borde #F6C9A3) el desempeño que está evaluando la rúbrica abierta.

Al terminar: listá los cambios, los comandos que tengo que correr yo (secreto, deploy, migración) y cómo probarlo de punta a punta.
```
