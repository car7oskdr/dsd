#!/usr/bin/env python3
import argparse
import logging
import subprocess
from pathlib import Path


logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)


def get_package_dir():
    """Obtiene el directorio del paquete instalado"""
    try:
        # Obtener la ruta del módulo actual
        current_file = Path(__file__).resolve()
        package_dir = current_file.parent
        return package_dir
    except Exception as e:
        logging.error(f"Error obteniendo directorio del paquete: {e}")
        return None


def get_script_path(script_name):
    """Obtiene la ruta absoluta de un script"""
    package_dir = get_package_dir()
    if not package_dir:
        return None

    script_path = package_dir / script_name
    return str(script_path) if script_path.exists() else None


def ejecutar_script(script_path, args=None):
    """Ejecuta un script shell de forma segura"""
    try:
        resultado = subprocess.run(
            ["bash", script_path] + (args or []),
            check=True,
        )
        return True, resultado.stdout, resultado.stderr
    except subprocess.CalledProcessError as e:
        return False, e.stdout, e.stderr


def genera_serverless_dsd():
    script_path = get_script_path(
        "scripts/genera_dsd_serverless/genera_serverless_yml.sh"
    )

    if script_path:
        exito, salida, error = ejecutar_script(script_path)
        if not exito:
            logging.error("Error ejecutando script:")
            if error:
                logging.error(f"Error: {error}")
            if salida:
                logging.error(f"Salida: {salida}")
    else:
        logging.error(
            "Script no encontrado: scripts/genera_dsd_serverless/genera_serverless_yml.sh"
        )


def deploy_serverless_dsd():
    script_path = get_script_path(
        "scripts/deploy_dsd_serverless/deploy_dsd_serverless.sh"
    )

    if script_path:
        exito, salida, error = ejecutar_script(script_path)
        if not exito:
            logging.error("Error en deploy:")
            logging.error(error)
    else:
        logging.error(
            "Script no encontrado: scripts/deploy_dsd_serverless/deploy_dsd_serverless.sh"
        )


def dsd_up():
    genera_serverless_dsd()
    deploy_serverless_dsd()


def dsd_rm():
    script_path = get_script_path(
        "scripts/destroy_dsd_serverless/destroy_dsd_serverless.sh"
    )

    if script_path:
        exito, salida, error = ejecutar_script(script_path)
        if not exito:
            logging.error("Error en destroy:")
            logging.error(error)
    else:
        logging.error(
            "Script no encontrado: scripts/destroy_dsd_serverless/destroy_dsd_serverless.sh"
        )


def main():
    parser = argparse.ArgumentParser(description="DSD Serverless CLI")
    parser.add_argument(
        "command",
        choices=["genera_serverless_dsd", "deploy_serverless_dsd", "dsd_up", "dsd_rm"],
        help="Comando a ejecutar",
    )

    args = parser.parse_args()

    if args.command == "genera_serverless_dsd":
        genera_serverless_dsd()
    elif args.command == "deploy_serverless_dsd":
        deploy_serverless_dsd()
    elif args.command == "dsd_up":
        dsd_up()
    elif args.command == "dsd_rm":
        dsd_rm()


if __name__ == "__main__":
    main()
