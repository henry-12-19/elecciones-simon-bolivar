# Sistema Electoral Online — Unidad Educativa Particular Simón Bolívar

Este proyecto conserva el diseño institucional de la versión offline, pero **los votos y el padrón se guardan en Supabase**, y GitHub Pages solo publica la interfaz. Funciona desde múltiples dispositivos conectados a internet.

## Archivos

- `index.html`: interfaz de votación y administración (mantiene la selección resaltada)
- `app.js`: funcionamiento de la aplicación, importación Excel/CSV y acta imprimible
- `config.js`: URL de Supabase y clave **publishable / anon**
- `database.sql`: tablas, permisos, bloqueo de votos duplicados y funciones RPC
- `assets/logo.png`: logotipo institucional original
- `vendor/jszip.min.js`: lector local de `.xlsx`; no requiere servicios terceros para leer archivos de estudiantes

## Instalación detallada

### 1. Crear base de datos Supabase

1. Crear cuenta en https://supabase.com y elegir **New project**.
2. En **SQL Editor**, crear una consulta nueva. Pegar el contenido COMPLETO de `database.sql` y ejecutar con **Run**. Este script está diseñado para un proyecto nuevo.
3. En **Authentication → Users** crear el usuario administrador (correo propio y contraseña larga). No es el PIN `1234` usado en la demostración.
4. En **SQL Editor**, ejecutar (modifica el correo por el correo REAL del usuario creado):

   ```sql
   insert into public.sb_admins(user_id)
   select id from auth.users
   where email = 'administrador@ejemplo.com'
   on conflict do nothing;
   ```

5. En **Authentication → Settings / General configuration**, desactivar **Allow new users to sign up**. Solo el usuario creado debe ser administrador.
6. En **Project Settings / Connect / API Keys**, copiar el `Project URL` y una clave **publishable** (o `anon` si el panel aún la muestra). Editar `config.js` y sustituir ambos marcadores.

**No colocar jamás `service_role`, una clave `secret`, contraseña de base de datos ni credenciales del administrador en `config.js` o en el repositorio.** La clave `publishable` es apta para el navegador precisamente porque las tablas y funciones están protegidas por permisos.

### 2. Publicar la página

1. Crear en https://github.com un repositorio nuevo, por ejemplo `elecciones-simon-bolivar`.
2. Subir todo el contenido de esta carpeta a la **raíz del repositorio**, respetando `assets/` y `vendor/`.
3. Ir a **Settings → Pages → Build and deployment → Deploy from a branch → main / (root) → Save**.
4. La URL resultante suele tener la forma `https://USUARIO.github.io/elecciones-simon-bolivar/`.
5. Abrir esa dirección en Chrome o Edge. El navegador necesita acceso a internet para Supabase y para la biblioteca JavaScript de Supabase.

> **Privacidad:** GitHub Pages normalmente publica contenido de repositorios públicos; solo debes subir CÓDIGO y archivos de interfaz. Nunca subas Excel de alumnos, copias de respaldo, listas de cédulas, contraseñas, PIN ni resultados privados al repositorio.

### 3. Preparar las elecciones

1. Abre la página y entra a **Administración** con el correo y contraseña del usuario Supabase.
2. En **Importar Excel**, descarga la plantilla CSV. Columnas obligatorias: `cedula`, `nombre`, `curso`, `pin`.
3. Reemplaza los datos ficticios por estudiantes reales y PIN individuales de al menos 6 caracteres. **Evita PIN fáciles de predecir, como el número de lista o los últimos dígitos de la cédula.**
4. Al importar desde Excel, conserva `cedula` y `pin` en formato **Texto** para que no desaparezcan ceros iniciales. El sistema admite `.xlsx` y `.csv`.
5. En **Listas**, sube fotografías/logos de las candidaturas y guarda. Cada imagen debe pesar menos de 110 KB.
6. En **Padrón por cursos**, verifica que el total y la clasificación sean correctos.
7. En **Control y acta**, pulsa **Abrir elección**.

### 4. Votación y resultados

- Cada estudiante ingresa identificación y PIN. La base de datos comprueba que esté registrado y habilitado.
- Selecciona A, B, blanco o nulo; la opción se resalta antes de confirmar.
- Al confirmar, la operación **bloquea el registro del estudiante** y evita que dos dispositivos registren votos con la misma identificación.
- El voto se inserta en una tabla **sin campo de cédula ni nombre**; el padrón guarda únicamente si participó.
- Durante la elección, el administrador puede ver **participación por curso** y quién está pendiente, pero **no los totales por lista**.
- Al cerrar, se muestran resultados, ganador o empate, exportación CSV y acta para imprimir o guardar como PDF.
- Para **Reiniciar votos**, se debe cerrar la elección, volver a ingresar la contraseña del administrador y escribir `REINICIAR VOTOS`.

### 5. Recomendaciones antes del uso real

- Realizar una prueba con cuentas y PIN ficticios desde **dos o más computadoras**. Comprobar que un doble intento de votar con la misma identificación solo crea un voto.
- Hacer respaldos mediante herramientas administrativas de Supabase, no desde un dispositivo estudiantil.
- Considerar la normativa ecuatoriana de protección de datos personales, especialmente porque el padrón puede incluir datos de menores.
- Compartir PIN individualmente; para evitar suplantaciones, supervisar la identidad de quien ingresa el PIN.
- Restringir acceso a Supabase y a la cuenta de GitHub; activar autenticación de dos factores de administradores y responsables del proyecto.
- Evitar subir fotografías de menores sin autorización institucional adecuada.
- El sistema proporciona **control básico de integridad**, no equivale por sí mismo a una plataforma electoral certificada. Antes de una elección oficial debe realizarse una revisión de seguridad y de los procedimientos de escrutinio y respaldo.

## Problemas habituales

- **“Pendiente de configuración”**: editar `config.js` y subir la versión editada al repositorio.
- **“Acceso no autorizado” en administración**: crear usuario en Auth y agregarlo a `sb_admins` con la consulta SQL indicada.
- **No se puede importar**: elección debe estar cerrada y con cero votos; todos deben tener PIN.
- **No se muestran resultados**: deben cerrarse las elecciones desde Administración.
- **La página no carga la base de datos**: revisar conexión a internet, URL y clave publicable, SQL instalado y que la API de Supabase esté habilitada.
- **No se genera PDF**: permitir ventanas emergentes; en la nueva ventana elegir “Imprimir → Guardar como PDF”.

## Nota técnica de seguridad

Todas las tablas tienen RLS habilitado y permisos de lectura/escritura revocados a `anon` y `authenticated`. Las funciones privilegiadas `security definer` comprueban permisos de administrador cuando es necesario. La función de votación se ejecuta en una única transacción de PostgreSQL con bloqueo de fila. Se limitan los PIN incorrectos a 5 intentos por identificación en una ventana de 15 minutos. El envío de información utiliza HTTPS. Los votos no tienen referencia directa a identificaciones.

**Limitaciones:** sin auditoría criptográfica extremo a extremo; el administrador del proyecto Supabase mantiene privilegios técnicos sobre los datos; las estadísticas de participación y las fotografías del padrón requieren las medidas de privacidad correspondientes. Asegura revisión independiente antes de elecciones vinculantes.

## Edición con tres portales y permisos separados

El paquete se entrega con **tres direcciones** del mismo proyecto de GitHub Pages:

- `index.html` — Portal de estudiantes. Solo verificación y emisión del voto.
- `admin.html` — Portal privado del propietario. Inicio de sesión con Supabase Auth y permiso en `sb_admins`. Permite importar padrón, editar listas, gestionar apertura/cierre, consultar estadísticas y reiniciar.
- `observador.html` — Portal privado de observación para otro docente. Inicio de sesión con Supabase Auth y permiso en `sb_observers`. **Solo lectura**: resultados preliminares mientras la elección está abierta, resultados finales después del cierre y estado de participación por curso, con filtros de votaron/pendientes.

La protección de la información **no depende de ocultar una dirección**: aunque alguien conozca `admin.html` u `observador.html`, el servidor limita las funciones por cuenta autorizada. El panel del docente **no tiene botones de configuración y no puede llamar exitosamente a las funciones de administración**. Los tres portales comparten la misma base de datos.

### Autorizar al docente observador

1. En Supabase, crea la cuenta del docente en **Authentication → Users** usando su correo individual y una contraseña privada. No compartas la contraseña de administrador.
2. Si ya ejecutaste el SQL de la versión anterior, ejecuta únicamente `observer-role.sql` en SQL Editor. Si instalas el proyecto desde cero, `database.sql` ya incluye el módulo de observación y NO hace falta ejecutarlo dos veces.
3. Ejecuta la siguiente instrucción reemplazando el correo por el del docente real:

```sql
insert into public.sb_observers(user_id)
select id from auth.users
where lower(email)=lower('docente@institucion.edu.ec')
on conflict do nothing;
```

4. Confirma que ese docente **no aparece** en `sb_admins`; nunca le concedas ambos permisos salvo que deba administrar.
5. Entrega solamente el enlace a `observador.html` y sus credenciales personales.

Para revocar acceso:

```sql
delete from public.sb_observers
where user_id in (select id from auth.users where lower(email)=lower('docente@institucion.edu.ec'));
```

**Prueba de permisos:** con la cuenta docente, la llamada `sb_observer_snapshot` debe funcionar y `sb_admin_snapshot`, `sb_set_open`, `sb_reset_votes`, `sb_import_roster` y `sb_save_profiles` deben ser rechazadas. Comprobar también el acceso negado desde una cuenta autenticada sin permisos.

### Precaución con los resultados preliminares

Si se consultan cifras agregadas tras cada voto individual y a la vez se dispone del estado del padrón, existe riesgo de deducir cómo votó una persona por diferencias sucesivas. Por ello, no se deben usar los datos preliminares para seguimiento individual, y se recomienda una política de actualizaciones por intervalos o grupos y un acuerdo de confidencialidad. Si se requiere una garantía robusta del secreto de voto incluso ante observadores con acceso repetido, debe rediseñarse el sistema para publicar solo escrutinios agregados con umbrales y retrasos adecuados.

**Privacidad:** Los números de identificación, nombres y estado de participación son datos personales. El acceso del observador debe autorizarse formalmente y limitarse al tiempo necesario. No publiques capturas del padrón ni CSV con datos de menores. **No uses la plataforma en elecciones oficiales hasta probar el SQL, los permisos, la integridad del voto y la protección de datos con un proyecto real de Supabase.**
