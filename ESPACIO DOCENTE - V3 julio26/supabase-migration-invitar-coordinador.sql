-- =========================================================
-- Migración: invitar automáticamente al dar de alta un coordinador
-- (colapsa los dos pasos manuales -- Authentication → Users por un lado,
-- la tabla coordinadores por el otro, en dos pantallas distintas del
-- dashboard -- en uno solo: insertar la fila en coordinadores. Un trigger
-- dispara la invitación de Supabase Auth automáticamente -- mismo flujo que
-- el botón "Invite user" del dashboard: el coordinador recibe un mail y
-- elige su propia contraseña, vos no tenés que inventar ni compartir una a
-- mano. Esto es justo lo que pasó con prueba@prueba.com: quedó de alta en
-- un lado y no en el otro, y nadie se dio cuenta hasta que falló el login.)
--
-- El modelo de "una tabla con los emails autorizados + selector de grados/
-- materias" (coordinadores + coordinador_permiso_grados/materias) ya existe
-- desde supabase-migration-permisos-coordinador-v2.sql -- esta migración no
-- lo cambia, solo hace que insertar ahí alcance para dar de alta a alguien
-- de punta a punta.
--
-- Correr a mano en Supabase SQL Editor. Idempotente, EXCEPTO el paso 2
-- (guardar la service_role key en Vault): esa línea se corre UNA sola vez.
-- vault.create_secret no es upsert -- correrla dos veces deja dos secretos
-- con el mismo nombre y la función de abajo toma "uno cualquiera" (LIMIT 1).
-- =========================================================

-- 1. Extensión para poder llamar HTTP desde un trigger (Vault ya está
-- habilitada en este proyecto, no hace falta crearla de nuevo).
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 2. Guardar la service_role key en Vault.
-- CORRÉ ESTA LÍNEA VOS, A MANO, EN EL SQL EDITOR -- reemplazando el
-- placeholder por tu key real (Project Settings → API → service_role, "secret").
-- No la pegues en ningún chat, commit ni archivo del repo: es equivalente a
-- la contraseña de administrador de todo el proyecto.
--
--   select vault.create_secret('PEGÁ_ACÁ_TU_SERVICE_ROLE_KEY', 'service_role_key');
--
-- Si ya habías cargado una antes y necesitás reemplazarla:
--   select vault.update_secret(
--     (select id from vault.secrets where name = 'service_role_key'),
--     'TU_KEY_NUEVA'
--   );

-- 3. Función del trigger: lee la key desde Vault (nunca queda en texto
-- plano en el código de la función ni en los logs) y llama al endpoint de
-- invitación de Supabase Auth -- el mismo que usa "Invite user" del
-- dashboard y supabase.auth.admin.inviteUserByEmail() del lado servidor.
CREATE OR REPLACE FUNCTION public.invitar_coordinador()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  v_service_key text;
  v_project_url text := 'https://kretfnbddhbosacfgdup.supabase.co';
BEGIN
  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key'
  LIMIT 1;

  IF v_service_key IS NULL THEN
    RAISE WARNING 'invitar_coordinador: no hay service_role_key en Vault (ver paso 2 de esta migración) -- % quedó de alta en coordinadores pero no se le mandó invitación', NEW.email;
    RETURN NEW;
  END IF;

  -- Fire-and-forget: pg_net encola la request y la resuelve en background,
  -- así que esto no frena ni puede hacer fallar el INSERT en coordinadores.
  PERFORM net.http_post(
    url := v_project_url || '/auth/v1/invite',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_service_key,
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object('email', NEW.email)
  );

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.invitar_coordinador() FROM PUBLIC;

-- 4. Trigger: solo al INSERT (no en UPDATE, para no reinvitar cada vez que
-- se edita el nombre de alguien que ya aceptó la invitación).
DROP TRIGGER IF EXISTS trg_invitar_coordinador ON public.coordinadores;
CREATE TRIGGER trg_invitar_coordinador
  AFTER INSERT ON public.coordinadores
  FOR EACH ROW EXECUTE FUNCTION public.invitar_coordinador();

-- Notas:
-- * coordinadores no tiene policies de INSERT a propósito (ver
--   supabase-migration-login-coordinadores.sql): la única forma de insertar
--   ahí sigue siendo el Table Editor con tu sesión de dashboard. El trigger
--   entonces solo se dispara cuando vos das de alta a alguien a mano, nunca
--   desde el sitio público.
-- * Si el email ya tenía cuenta en Authentication → Users (por lo que sea),
--   /auth/v1/invite devuelve "User already registered": no rompe nada, la
--   fila en coordinadores se guarda igual, esa persona ya puede loguearse
--   con la contraseña que ya tenía.
-- * Para revisar si una invitación efectivamente salió (o si falló por lo
--   que sea, p. ej. límite de mails de Supabase), Logs → Postgres Logs
--   filtrado por "invitar_coordinador", o net._http_response para ver el
--   código de respuesta de la request.
-- * El paso que sigue quedando manual, y así debe ser: cargar los permisos
--   de grado/materia en coordinador_permiso_grados/materias si el
--   coordinador no debe ver todo. Eso es una decisión de alcance, no un
--   detalle técnico para automatizar.
