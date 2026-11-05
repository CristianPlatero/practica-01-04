#!/bin/bash
# Instala Apache de forma desatendida. Es idempotente:
# si ya está instalado, no hace nada.
set -euo pipefail

# Comprobar si Apache ya está instalado
if dpkg -s apache2 &> /dev/null; then
    echo "Apache ya está instalado."
    exit 0
fi

# Instalación sin intervención del usuario
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2

# Dejar el servicio habilitado y en marcha
systemctl enable --now apache2

echo "Apache instalado y en marcha."
