# DSD Framework

**DSD** (*Deploy Stack Develop*) es una herramienta CLI de línea de comandos que permite a cada desarrollador desplegar una copia aislada y personal de un stack *serverless* dentro de una cuenta de AWS `develop` compartida.

Para lograrlo, reescribe el archivo `serverless.yml` del proyecto de forma que cada recurso nombrado quede prefijado con `dsd-<id_usuario_gitlab>-`, evitando colisiones entre los stacks de distintos desarrolladores que trabajan sobre la misma cuenta.

> **Nota:** Esta herramienta no se ejecuta por sí sola. Está pensada para instalarse como paquete dentro de **otros** proyectos de Serverless Framework, que deben proveer `.env`, `src/`, `infra/` y un `Makefile` con los objetivos que invocan estos comandos.

---

## 🚧 Mejora planificada: migración a Rust

Se realizará una **mejora del proyecto para migrar el código a Rust**.

Actualmente la herramienta está implementada con una combinación de **Python** (procesamiento de YAML) y **Bash** (orquestación, validaciones y llamadas a `sls`/`aws`). La migración a Rust busca:

- **Un único binario distribuible** sin dependencias de runtime de Python ni de múltiples scripts de shell.
- **Mayor robustez y manejo de errores** mediante el sistema de tipos de Rust, reemplazando la lógica dispersa de validación en Bash.
- **Rendimiento y arranque más rápido** para las operaciones de generación y despliegue.
- **Mantenibilidad**: consolidar el pipeline (hoy repartido entre scripts que se comunican por archivos temporales) en un flujo único y tipado.

> ⚠️ La migración a Rust es un trabajo **en planificación / en progreso**. La implementación actual en Python + Bash sigue siendo la versión funcional de referencia mientras se realiza la transición.

---

## Requisitos

Las siguientes herramientas deben estar disponibles en el `PATH` (los scripts las verifican explícitamente):

| Herramienta | Uso |
|-------------|-----|
| `sls` | Serverless Framework (despliegue) |
| `aws` | AWS CLI con credenciales válidas (`aws sts get-caller-identity`) |
| `python` | Procesamiento de YAML |
| `curl` | Consulta a la API de GitLab |
| `make` | Orquestación desde el proyecto consumidor |

Además, el proyecto consumidor debe contar con:

- Un entorno virtual `.venv/`.
- Un archivo `.env` con las variables `GITLAB_TOKEN` y `URL_GITLAB_API`.
- Dependencia de Python: `ruamel.yaml`.

Todos los despliegues se realizan sobre AWS con `--stage dev`.

---

## Comandos

El punto de entrada es `cli.py` (`python cli.py <comando>`). Cada comando ejecuta un script de orquestación en Bash:

| Comando | Descripción |
|---------|-------------|
| `genera_serverless_dsd` | Genera únicamente el archivo serverless con los nombres prefijados. |
| `deploy_serverless_dsd` | Despliega (`sls deploy`) el archivo generado. |
| `dsd_up` | Ejecuta la generación y luego el despliegue. |
| `dsd_rm` | Destruye el stack (`sls remove`) y limpia los archivos locales. |

Habitualmente estos comandos se invocan desde el proyecto consumidor a través de objetivos de `Makefile` (`make dsd_up`, `make dsd_rm`, etc.).

---

## Cómo funciona: el pipeline de generación

La lógica central convierte el `serverless.yml` de un proyecto en un archivo personalizado `.dsd_<usuario>_serverless.yml`. El flujo (orquestado por `scripts/genera_dsd_serverless/genera_serverless_yml.sh`) es:

1. **Localizar el proyecto** — Se busca hacia arriba un directorio que contenga `.env` y `src/`/`infra/`, y se cambia a él. Todas las rutas posteriores son relativas a la raíz del proyecto consumidor.
2. **Identificar al desarrollador** — `nombre_usuario.sh` lee `GITLAB_TOKEN` y `URL_GITLAB_API` desde `.env`, consulta la API de GitLab y devuelve el **id numérico del usuario**, que se usa como sufijo del namespace (`dsd-<id>-...`).
3. **Seleccionar el archivo fuente** — `seleccionar_archivo.sh` busca `serverless.yml` bajo `infra/` (recursivo) y `src/serverless*.yml` (formato plano heredado).
4. **Capturar los recursos AWS existentes** — `recursos/recursos_stack.sh` vuelca los nombres actuales de S3/IAM/SQS/DynamoDB/SNS/StepFunctions en `src/.resources.txt`, para detectar qué recursos son *compartidos* y no deben recrearse.
5. **Aplanar la configuración** — `genera_dsd-serverless.sh` ejecuta `cambia_service.py` (reescribe `custom.serviceName`) y luego `sls print` para resolver imports y variables en un único YAML plano.
6. **Aplicar el namespace** — `dsd_serverless.py` (`DSDServerlessProcessor`) prefija `dsd-<usuario>-` en el servicio, nombres de funciones, rutas `httpApi`, schedulers, buckets S3, recursos compartidos y propiedades de recursos de CloudFormation. Produce `src/.dsd_<usuario>_serverless.yml`.

### Convenciones importantes

- **Límite de 64 caracteres de AWS** — `_total_caracteres` reemplaza `-develop` por `-dev` en nombres que exceden el límite. Los nombres modificados se registran en `src/.dsd_nombres_modificados.txt`.
- **Casos especiales** — Algunos nombres concretos se eliminan durante el procesamiento (por ejemplo, la función `grupos_documentos_endpoint` y el recurso `MensajeriaExClientesBucketPolicy`).
- **Preservación de formato** — El YAML se procesa en modo *round-trip* con `ruamel.yaml` para mantener la salida legible y comparable.
- **Stack compartido** — Si la ruta seleccionada contiene `infra/groups`, primero se despliega `infra/shared/serverless.yml`.

---

## Estructura del proyecto

```
.
├── cli.py                          # Punto de entrada de la CLI
├── __init__.py                     # Metadatos del paquete
└── scripts/
    ├── genera_dsd_serverless/      # Generación del archivo DSD
    │   ├── genera_serverless_yml.sh    # Orquestador principal
    │   ├── genera_dsd-serverless.sh    # Aplanado vía `sls print`
    │   ├── cambia_service.py           # Reescritura de serviceName
    │   ├── dsd_serverless.py           # Procesador de namespace (núcleo)
    │   ├── nombre_usuario.sh           # Obtención del usuario de GitLab
    │   └── seleccionar_archivo.sh      # Selección del serverless.yml
    ├── deploy_dsd_serverless/      # Despliegue del stack
    ├── destroy_dsd_serverless/     # Destrucción del stack
    └── recursos/                   # Snapshot de recursos AWS existentes
```

---

## Autor

Podemos Progresar — Performance Team.
