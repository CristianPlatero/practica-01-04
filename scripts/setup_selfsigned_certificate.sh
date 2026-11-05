#!/bin/bash
# Crea un certificado autofirmado y configura Apache con HTTPS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$SCRIPT_DIR/../conf"
ENV_FILE="$SCRIPT_DIR/.env"

# 1. Comprobar que Apache está instalado
if ! dpkg -s apache2 &> /dev/null; then
    echo "Apache no está instalado. Ejecuta antes install_apache.sh" >&2
    exit 1
fi

# 2. Leer variables del .env
if [ ! -f "$ENV_FILE" ]; then
    echo "No existe $ENV_FILE. Copia .env.example a .env y ajústalo." >&2
    exit 1
fi
set -a
source "$ENV_FILE"
set +a

# 3. Crear el certificado con subjectAltName (dominio + IP elástica)
openssl req -x509 -nodes -days "$CERT_DAYS" -newkey rsa:2048 \
    -keyout "$KEY_PATH" \
    -out "$CERT_PATH" \
    -subj "/C=$CERT_COUNTRY/ST=$CERT_STATE/L=$CERT_LOCALITY/O=$CERT_ORG/OU=$CERT_OU/CN=$DOMAIN/emailAddress=$CERT_EMAIL" \
    -addext "subjectAltName=DNS:$DOMAIN,IP:$ELASTIC_IP"
chmod 600 "$KEY_PATH"

# 4. Copiar plantillas y sustituir marcadores
cp "$CONF_DIR/000-default.conf"        "$SITES_DIR/000-default.conf"
cp "$CONF_DIR/practica-https-ssl.conf" "$SITES_DIR/practica-https-ssl.conf"
sed -i \
    -e "s|DOMINIO_PLACEHOLDER|$DOMAIN|g" \
    -e "s|CERT_PLACEHOLDER|$CERT_PATH|g" \
    -e "s|KEY_PLACEHOLDER|$KEY_PATH|g" \
    "$SITES_DIR/000-default.conf" "$SITES_DIR/practica-https-ssl.conf"

# 5. Habilitar módulos y sitio HTTPS
a2enmod ssl rewrite
a2ensite practica-https-ssl.conf

# 6. Comprobar configuración antes de reiniciar
if ! apache2ctl configtest; then
    echo "Error en la configuración de Apache. No se reinicia." >&2
    exit 1
fi
systemctl restart apache2

echo "HTTPS configurado para $DOMAIN"
