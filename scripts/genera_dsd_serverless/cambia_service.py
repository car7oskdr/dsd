import argparse
import os

from ruamel.yaml import YAML


# Configurar YAML para preservar el formato
yaml = YAML(typ="rt")  # Usar round-trip para preservar el formato
yaml.indent(mapping=2, sequence=4, offset=2)  # Ajustar la indentación
yaml.preserve_quotes = True  # Preservar comillas
yaml.width = 4096  # Evitar que las líneas se dividan
yaml.default_flow_style = False  # Forzar el estilo de bloque

# Crear un parser para recibir dos argumentos
parser = argparse.ArgumentParser(
    description="Procesar un archivo yml y usuario para generar un archivo serverless.yml"
)
parser.add_argument("archivo_seleccionado", help="El archivo serverless seleccionado")
parser.add_argument("user_dsd", help="El nombre de usuario")
args = parser.parse_args()

archivo_seleccionado = args.archivo_seleccionado
user_dsd = args.user_dsd

base_dir = os.path.dirname(os.path.abspath(archivo_seleccionado))
input_file = os.path.join(base_dir, ".dsd-cp-serverless.yml")
output_file = os.path.join(base_dir, ".dsd-service-serverless.yml")

with open(input_file, "r") as file:
    try:
        config = yaml.load(file)
    except Exception as e:
        print(f"Error loading YAML file: {e}")
        exit(1)

servicio = config.get("service", "default")

if "custom" in config:
    config["custom"]["serviceName"] = f"dsd-{user_dsd}-{servicio}"

with open(output_file, "w") as file:
    try:
        yaml.dump(config, file)
    except Exception as e:
        print(f"Error dumping YAML file: {e}")
        exit(1)
