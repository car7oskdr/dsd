import argparse
import os
import sys
from typing import Any, Dict, List

from ruamel.yaml import YAML
from ruamel.yaml.error import YAMLError


class DSDServerlessError(Exception):
    """Excepción personalizada para errores del procesador DSD Serverless"""

    pass


class DSDServerlessProcessor:
    def __init__(self, archivo_seleccionado: str, user_dsd: str):
        self.archivo_seleccionado = archivo_seleccionado
        self.user_dsd = user_dsd
        self.input_file = (
            "./src/.dsd-shared-serverless.yml"
            if "shared" in archivo_seleccionado
            else "./src/.dsd-serverless.yml"
        )
        self.output_file = (
            f"./src/.dsd-{user_dsd}-shared-serverless.yml"
            if "shared" in archivo_seleccionado
            else f"./src/.dsd_{user_dsd}_serverless.yml"
        )
        self.nombre_recursos_modificado: List[str] = []

        # Configurar YAML para preservar el formato
        self.yaml = YAML(typ="rt")
        self.yaml.indent(mapping=2, sequence=4, offset=2)
        self.yaml.preserve_quotes = True
        self.yaml.width = 4096
        self.yaml.default_flow_style = False

    def _safe_load_yaml(self, file_path: str) -> Dict[str, Any]:
        """Cargar archivo YAML con manejo de errores"""
        try:
            if not os.path.exists(file_path):
                raise DSDServerlessError(f"El archivo {file_path} no existe")

            with open(file_path, "r", encoding="utf-8") as file:
                return self.yaml.load(file)
        except YAMLError as e:
            raise DSDServerlessError(f"Error al parsear YAML en {file_path}: {str(e)}")
        except Exception as e:
            raise DSDServerlessError(f"Error al leer archivo {file_path}: {str(e)}")

    def _safe_save_yaml(self, config: Dict[str, Any], file_path: str) -> None:
        """Guardar configuración YAML con manejo de errores"""
        try:
            # Crear directorio si no existe
            os.makedirs(os.path.dirname(file_path), exist_ok=True)

            with open(file_path, "w", encoding="utf-8") as file:
                self.yaml.dump(config, file)
        except Exception as e:
            raise DSDServerlessError(f"Error al guardar archivo {file_path}: {str(e)}")

    def _total_caracteres(self, recurso: str) -> str:
        """Procesar nombre de recurso respetando límite de 64 caracteres"""
        if not isinstance(recurso, str):
            raise DSDServerlessError(
                f"El recurso debe ser una cadena, recibido: {type(recurso)}"
            )

        if len(recurso) > 64:
            new_name = recurso.replace("-develop", "-dev")
            if new_name not in self.nombre_recursos_modificado:
                self.nombre_recursos_modificado.append(new_name)
            return new_name
        return recurso

    def _safe_get_nested(self, obj: Dict[str, Any], *keys: str, default=None) -> Any:
        """Acceso seguro a valores anidados en diccionarios"""
        try:
            for key in keys:
                if isinstance(obj, dict) and key in obj:
                    obj = obj[key]
                else:
                    return default
            return obj
        except Exception:
            return default

    def _safe_set_nested(self, obj: Dict[str, Any], value: Any, *keys: str) -> None:
        """Asignación segura a valores anidados en diccionarios"""
        try:
            for key in keys[:-1]:
                if key not in obj:
                    obj[key] = {}
                obj = obj[key]
            obj[keys[-1]] = value
        except Exception as e:
            raise DSDServerlessError(
                f"Error al asignar valor en ruta {'.'.join(keys)}: {str(e)}"
            )

    def _process_functions(self, config: Dict[str, Any]) -> None:
        """Procesar funciones con manejo de errores"""
        try:
            functions = config.get("functions", {})
            if not isinstance(functions, dict):
                raise DSDServerlessError("La sección 'functions' debe ser un diccionario")

            funciones_eliminar = []

            for function_name, function_config in functions.items():
                if not isinstance(function_config, dict):
                    print(
                        f"⚠️  Advertencia: Configuración de función "
                        f"'{function_name}' no válida, saltando..."
                    )
                    continue

                # Procesar nombre de función
                if "name" in function_config:
                    try:
                        new_name = f"dsd-{self.user_dsd}-{function_config['name']}"
                        function_config["name"] = self._total_caracteres(new_name)
                    except Exception as e:
                        print(
                            f"⚠️  Error procesando nombre de función "
                            f"'{function_name}': {str(e)}"
                        )

                # Eliminar función específica
                if function_name == "grupos_documentos_endpoint":
                    funciones_eliminar.append(function_name)

                # Procesar eventos
                self._process_events(function_config)

            # Eliminar funciones marcadas
            for function_name in funciones_eliminar:
                functions.pop(function_name, None)

        except Exception as e:
            raise DSDServerlessError(f"Error procesando funciones: {str(e)}")

    def _process_events(self, function_config: Dict[str, Any]) -> None:
        """Procesar eventos de función con manejo de errores"""
        try:
            events = function_config.get("events", [])
            if not isinstance(events, list):
                return

            for event in events:
                if not isinstance(event, dict):
                    continue

                # Procesar httpApi
                if "httpApi" in event and isinstance(event["httpApi"], dict):
                    path = event["httpApi"].get("path")
                    if path:
                        event["httpApi"]["path"] = f"{path}/dsd-{self.user_dsd}"

                # Procesar s3
                if "s3" in event and isinstance(event["s3"], dict):
                    self._process_s3_event(event, function_config)

                # Procesar sheduler
                if "schedule" in event and isinstance(event["schedule"], dict):
                    name = event["schedule"].get("name")
                    if name:
                        event["schedule"]["name"] = f"dsd-{self.user_dsd}-{name}"

        except Exception as e:
            print(f"⚠️  Error procesando eventos: {str(e)}")

    def _process_s3_event(
        self, event: Dict[str, Any], function_config: Dict[str, Any]
    ) -> None:
        """Procesar evento S3 específico"""
        try:
            bucket = event["s3"].get("bucket")
            if not bucket:
                return

            # Leer archivo de recursos
            resources_content = self._read_resources_file()

            if bucket in resources_content:
                new_bucket = f"dsd-{self.user_dsd}-{bucket}"
                event["s3"]["bucket"] = self._total_caracteres(new_bucket)

                # Actualizar BUCKET_NAME en environment
                environment = function_config.get("environment", {})
                if isinstance(environment, dict) and "BUCKET_NAME" in environment:
                    new_bucket_name = f"dsd-{self.user_dsd}-{environment['BUCKET_NAME']}"
                    environment["BUCKET_NAME"] = self._total_caracteres(new_bucket_name)

        except Exception as e:
            print(f"⚠️  Error procesando evento S3: {str(e)}")

    def _read_resources_file(self) -> str:
        """Leer archivo de recursos con manejo de errores"""
        try:
            resources_file = "./src/.resources.txt"
            if os.path.exists(resources_file):
                with open(resources_file, "r", encoding="utf-8") as file:
                    return file.read()
            return ""
        except Exception as e:
            print(f"⚠️  Error leyendo archivo de recursos: {str(e)}")
            return ""

    def _process_resources(self, config: Dict[str, Any]) -> None:
        """Procesar recursos con manejo de errores"""
        try:
            resources = self._safe_get_nested(config, "resources", "Resources")
            if not resources:
                return

            recursos_eliminar = []

            for recurso, config_recurso in resources.items():
                if not isinstance(config_recurso, dict):
                    continue

                # Eliminar recurso específico
                if recurso == "MensajeriaExClientesBucketPolicy":
                    recursos_eliminar.append(recurso)
                    continue

                self._process_resource_properties(recurso, config_recurso)

            # Eliminar recursos marcados
            for recurso in recursos_eliminar:
                resources.pop(recurso, None)

        except Exception as e:
            raise DSDServerlessError(f"Error procesando recursos: {str(e)}")

    def _process_shared_resources(self, config: Dict[str, Any]) -> None:
        """Procesar recursos compartidos con manejo de errores"""
        try:
            shared_resources = self._safe_get_nested(
                config, "custom", "config", "sharedResources"
            )
            if not isinstance(shared_resources, dict):
                return

            for key, value in shared_resources.items():
                if isinstance(value, str):
                    new_value = f"dsd-{self.user_dsd}-{value}"
                    new_value = self._total_caracteres(new_value)
                    shared_resources[key] = new_value

                    # Actualizar referencias en variables de entorno
                    self._update_environment_references(config, value, new_value)

        except Exception as e:
            print(f"⚠️  Error procesando recursos compartidos: {str(e)}")

    def _update_environment_references(
        self, config: Dict[str, Any], original_value: str, new_value: str
    ) -> None:
        """Actualizar referencias en variables de entorno de funciones"""
        try:
            functions = config.get("functions", {})
            if not isinstance(functions, dict):
                return

            for func_config in functions.values():
                if not isinstance(func_config, dict):
                    continue

                environment = func_config.get("environment", {})
                if not isinstance(environment, dict):
                    continue

                for env_key, env_value in environment.items():
                    if env_value == original_value:
                        environment[env_key] = new_value

        except Exception as e:
            print(f"⚠️  Error actualizando referencias de entorno: {str(e)}")

    def _process_resource_properties(
        self, recurso: str, config_recurso: Dict[str, Any]
    ) -> None:
        """Procesar propiedades de recurso específico"""
        try:
            properties = config_recurso.get("Properties", {})
            if not isinstance(properties, dict):
                return

            resource_type = config_recurso.get("Type", "")

            # Mapeo de tipos de recursos y sus propiedades de nombre
            resource_name_props = {
                "AWS::S3::Bucket": "BucketName",
                "AWS::DynamoDB::Table": "TableName",
                "AWS::IAM::Role": "RoleName",
                "AWS::SQS::Queue": "QueueName",
                "AWS::SNS::Topic": "TopicName",
                "AWS::CloudWatch::Alarm": "AlarmName",
            }

            name_prop = resource_name_props.get(resource_type)
            if name_prop and name_prop in properties:
                current_name = properties[name_prop]
                if isinstance(current_name, str) and "dsd-" not in current_name:
                    new_name = f"dsd-{self.user_dsd}-{current_name}"
                    properties[name_prop] = self._total_caracteres(new_name)

        except Exception as e:
            print(
                f"⚠️  Error procesando propiedades del recurso " f"'{recurso}': {str(e)}"
            )

    def _process_step_functions(self, config: Dict[str, Any]) -> None:
        """Procesar step functions con manejo de errores"""
        try:
            step_functions = self._safe_get_nested(
                config, "stepFunctions", "stateMachines"
            )
            if not step_functions:
                return

            resources_content = self._read_resources_file()
            step_functions_eliminar = []

            for state_machine_name in step_functions:
                if state_machine_name in resources_content:
                    step_functions_eliminar.append(state_machine_name)

            # Eliminar step functions marcadas
            for state_machine_name in step_functions_eliminar:
                step_functions.pop(state_machine_name, None)

        except Exception as e:
            print(f"⚠️  Error procesando step functions: {str(e)}")

    def _save_modified_names(self) -> None:
        """Guardar nombres modificados en archivo"""
        try:
            if self.nombre_recursos_modificado:
                archivo_nombres = "./src/.dsd_nombres_modificados.txt"
                os.makedirs(os.path.dirname(archivo_nombres), exist_ok=True)

                with open(archivo_nombres, "w", encoding="utf-8") as nombres_txt:
                    for nombre in self.nombre_recursos_modificado:
                        nombres_txt.write(nombre + "\n")

        except Exception as e:
            print(f"⚠️  Error guardando nombres modificados: {str(e)}")

    def _process_outputs_resources(self, config: Dict[str, Any]) -> None:
        """Dentro de outputs se encuentran los recursos que se usan en el proyecto se
        requiere renombrar para que lleven dsd-user.
        """
        try:
            outputs = self._safe_get_nested(config, "resources", "Outputs")
            if not outputs:
                return

            for output_name in outputs:
                outputs[output_name]["Export"]["Name"] = (
                    f"dsd-{self.user_dsd}-{output_name}"
                )

        except Exception as e:
            print(f"⚠️  Error procesando outputs: {str(e)}")

    def process(self) -> None:
        """Proceso principal con manejo completo de errores"""
        try:
            print(f"🔄 Procesando archivo: {self.archivo_seleccionado}")
            print(f"👤 Usuario DSD: {self.user_dsd}")

            # Cargar configuración
            config = self._safe_load_yaml(self.input_file)
            if not config:
                raise DSDServerlessError("No se pudo cargar la configuración YAML")

            # Actualizar nombre del servicio
            service_name = config.get("service", "default-service")
            config["service"] = f"dsd-{self.user_dsd}-{service_name}"

            # Procesar secciones
            self._process_functions(config)
            self._process_shared_resources(config)
            self._process_resources(config)
            self._process_step_functions(config)
            self._process_outputs_resources(config)

            # Guardar configuración procesada
            self._safe_save_yaml(config, self.output_file)

            # Guardar nombres modificados
            self._save_modified_names()

            print(f"✅ Archivo procesado exitosamente: {self.output_file}")
            if self.nombre_recursos_modificado:
                print(
                    f"📝 {len(self.nombre_recursos_modificado)} nombres "
                    f"fueron modificados por límite de caracteres"
                )

        except DSDServerlessError as e:
            print(f"❌ Error en procesamiento: {str(e)}")
            sys.exit(1)
        except Exception as e:
            print(f"❌ Error inesperado: {str(e)}")
            sys.exit(1)


def main():
    """Función principal con validación de argumentos"""
    try:
        parser = argparse.ArgumentParser(
            description=(
                "Procesar un archivo yml y usuario para generar "
                "un archivo serverless.yml"
            )
        )
        parser.add_argument(
            "archivo_seleccionado", help="El archivo serverless seleccionado"
        )
        parser.add_argument("user_dsd", help="El nombre de usuario")

        args = parser.parse_args()

        # Validar argumentos
        if not args.archivo_seleccionado or not args.user_dsd:
            raise DSDServerlessError("Ambos argumentos son requeridos")

        if not args.archivo_seleccionado.strip() or not args.user_dsd.strip():
            raise DSDServerlessError("Los argumentos no pueden estar vacíos")

        # Crear y ejecutar procesador
        processor = DSDServerlessProcessor(args.archivo_seleccionado, args.user_dsd)
        processor.process()

    except DSDServerlessError as e:
        print(f"❌ Error de argumentos: {str(e)}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error inesperado en main: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
