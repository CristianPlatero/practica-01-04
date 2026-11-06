# Práctica 1.4 — HTTPS con certificado autofirmado en Apache

**Módulo:** Despliegue de Aplicaciones Web (DAW2) · **Curso:** 2026-27
**Autor:** Cristian Platero · **Repositorio:** `practica-01-04`

## Índice

1. [Objetivo y conceptos previos](#1-objetivo-y-conceptos-previos)
2. [Entorno de trabajo](#2-entorno-de-trabajo)
3. [Infraestructura en AWS](#3-infraestructura-en-aws)
4. [Repositorio y acceso a GitHub](#4-repositorio-y-acceso-a-github)
5. [Estructura del proyecto](#5-estructura-del-proyecto)
6. [Los scripts, explicados](#6-los-scripts-explicados)
7. [Plantillas de Apache (`conf/`)](#7-plantillas-de-apache-conf)
8. [Ejecución del despliegue](#8-ejecución-del-despliegue)
9. [Acceso desde el equipo cliente](#9-acceso-desde-el-equipo-cliente)
10. [Verificación y evidencias](#10-verificación-y-evidencias)
11. [Comprobaciones adicionales](#11-comprobaciones-adicionales)
12. [Problemas encontrados y cómo se resolvieron](#12-problemas-encontrados-y-cómo-se-resolvieron)
13. [Seguridad](#13-seguridad)
14. [Cierre del laboratorio](#14-cierre-del-laboratorio)
15. [Conclusiones](#15-conclusiones)

---

## 1. Objetivo y conceptos previos

El objetivo es desplegar un servidor **Apache con HTTPS** en una instancia **EC2** de AWS, con todo el proceso **automatizado mediante scripts Bash**, de modo que se pueda repetir sobre una instancia Ubuntu recién creada sin intervención manual. El sitio debe responder por HTTPS con un certificado autofirmado y redirigir de forma permanente todo el tráfico HTTP a HTTPS.

### Ideas clave

- **HTTPS es HTTP sobre TLS.** El servidor presenta un certificado con su clave pública; el cliente la usa para cifrar la conexión y comprobar la identidad del servidor.
- **Autofirmado frente a certificado de una CA.** El cifrado es igual de fuerte; lo que cambia es la **confianza**. Un certificado de una autoridad reconocida es aceptado automáticamente por el navegador. Uno autofirmado no, y por eso aparece un aviso de seguridad. Es adecuado para pruebas y docencia, no para producción.
- **El aviso del navegador es esperable.** Al aceptarlo, el navegador guarda una excepción temporal para ese sitio; el certificado no pasa a ser de confianza ni se instala en el sistema.
- **El nombre se valida en el SAN, no en el CN.** Chrome y Firefox ignoran el *Common Name*. Por eso el certificado incluye la extensión `subjectAltName` con el dominio y la IP.
- **La clave privada nunca sale del servidor.** Se guarda en `/etc/ssl/private/` con permisos `600` y jamás se sube al repositorio.
- **Dominio `.test`.** Está reservado para pruebas y no choca con mDNS, como sí puede ocurrir con `.local`.

## 2. Entorno de trabajo

| Elemento | Valor |
|---|---|
| Plataforma | AWS Academy Learner Lab |
| Instancia | `practica-https` |
| Sistema operativo | Ubuntu Server LTS (AMI de *Quick Start*) — versión: `26.04 LTS` |
| Tipo de instancia | `t3.micro` |
| Par de claves | Creado desde el asistente de lanzamiento de EC2 (`.pem`) |
| IP elástica | `184.193.128.213` |
| Dominio de prueba | `practica-https.test` |
| Equipo cliente | Linux Mint (máquina virtual) |
| Control de versiones | Git + GitHub, acceso por SSH |

## 3. Infraestructura en AWS

### 3.1 Creación de la instancia

1. Arranqué el laboratorio (*Start Lab*) y abrí la consola de AWS.
2. En **EC2 → Launch instance** creé la instancia `practica-https` con la AMI oficial de Ubuntu Server LTS más reciente y tipo `t3.micro`.
3. En *Key pair* elegí **crear un par nuevo** desde el propio asistente y descargué el archivo `.pem`, que guardé en `~/.claves/` con permisos restringidos:
   ```bash
   chmod 400 ~/.claves/practica-https.pem
   ```

### 3.2 Security Group

Un Security Group funciona como un cortafuegos virtual: bloquea todo el tráfico de entrada que no se permita de forma explícita. Configuré tres reglas de entrada:

| Tipo | Protocolo | Puerto | Origen | Para qué |
|---|---|---|---|---|
| SSH | TCP | 22 | `Mi IP / 0.0.0.0/0` | Administración remota |
| HTTP | TCP | 80 | `0.0.0.0/0` | Acceso HTTP y redirección |
| HTTPS | TCP | 443 | `0.0.0.0/0` | Acceso HTTPS |

> Importante: las reglas solo se aplican al pulsar **Save rules**. Más adelante explico (apartado 12) el problema que tuve por no guardarlas a la primera.

### 3.3 IP elástica

En **EC2 → Elastic IPs** reservé una dirección (*Allocate*) y la asocié a la instancia (*Associate Elastic IP address*). Una IP elástica es una IPv4 pública **fija**: no cambia al parar y arrancar la instancia, cosa que sí ocurre con una IP pública normal. Esa IP es la que se incluye en el SAN del certificado, de modo que si cambiara habría que regenerarlo.

### 3.4 Conexión por SSH

```bash
ssh -i ~/.ssh/<mi-clave>.pem ubuntu@184.193.128.213
```

`ubuntu` es el usuario por defecto de las AMI de Ubuntu. La primera conexión pregunta si se confía en la huella del host; se responde `yes`.

Para que las pruebas 1 y 2 se vieran completas, **no instalé ni toqué Apache** hasta haber preparado el repositorio: se hacen sobre una instancia recién creada.

## 4. Repositorio y acceso a GitHub

Creé el repositorio `practica-01-04` en GitHub y añadí al profesor como colaborador. Lo clono en la instancia para ejecutar los scripts directamente desde allí.

### 4.1 Autenticación desde la instancia

Trabajo siempre por SSH, así que usé la URL SSH del repositorio (`git@github.com:...`). Para que GitHub reconozca a la instancia generé **una clave SSH en la propia instancia** y registré solo la parte pública en mi cuenta:

```bash
ssh-keygen -t ed25519 -C "instancia" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub          # solo la parte pública
```

La línea pública se añadió en **GitHub → Settings → SSH and GPG keys → New SSH key**. Después comprobé la conexión y configuré el repositorio:

```bash
ssh -T git@github.com
git clone git@github.com:CristianPlatero/practica-01-04.git
cd practica-01-04
git config --global user.name "Cristian Platero"
git config --global user.email "<mi_email>"
```

> Tengo por tanto **dos claves distintas** con funciones distintas: la del par de AWS (`.pem`) conecta **mi equipo → la instancia**, y la `id_ed25519` hace que **la instancia → GitHub** se autentique. La clave privada de cada una permanece donde se creó.

### 4.2 `.gitignore`

```
# Secretos: nunca se suben
scripts/.env
.env
*.key
*.pem
```

Subir la clave privada o un `.env` con credenciales está penalizado, así que antes de cada `push` compruebo que no se cuela nada:

```bash
git status
git ls-files | grep -E '\.env$|\.key$|\.pem$'    # no debe devolver nada
```

## 5. Estructura del proyecto

```
.
├── README.md
├── .gitignore
├── img/                      # capturas de las evidencias
├── conf/
│   ├── 000-default.conf          # VirtualHost :80 con redirección
│   └── practica-https-ssl.conf   # VirtualHost :443 con el certificado
└── scripts/
    ├── .env.example              # variables con valores de ejemplo
    ├── install_apache.sh
    └── setup_selfsigned_certificate.sh
```

El `.env` real se crea en la instancia a partir del ejemplo y **no** se sube. Los scripts son ejecutables (`chmod +x scripts/*.sh`).

## 6. Los scripts, explicados

### 6.1 `scripts/.env.example`

Separa la configuración del código: el script no contiene datos concretos y se puede reutilizar con otro dominio, otra IP u otro centro cambiando solo el `.env`.

```bash
CERT_COUNTRY=ES
CERT_STATE=Cantabria
CERT_LOCALITY=Torrelavega
CERT_ORG="IES Miguel Herrero"
CERT_OU=Informatica
CERT_EMAIL=admin@example.com
DOMAIN=practica-https.test
ELASTIC_IP=203.0.113.10
CERT_DAYS=365
KEY_PATH=/etc/ssl/private/apache-selfsigned.key
CERT_PATH=/etc/ssl/certs/apache-selfsigned.crt
SITES_DIR=/etc/apache2/sites-available
```

En el `.env` real, `ELASTIC_IP` lleva mi IP elástica. La IP del ejemplo (`203.0.113.10`) pertenece a un rango reservado para documentación.

### 6.2 `scripts/install_apache.sh`

```bash
#!/bin/bash
set -euo pipefail

if dpkg -s apache2 &> /dev/null; then
    echo "Apache ya está instalado."
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2

systemctl enable --now apache2
echo "Apache instalado y en marcha."
```

| Parte | Qué hace |
|---|---|
| `set -euo pipefail` | Detiene el script ante un error (`-e`), una variable sin definir (`-u`) o un fallo dentro de una tubería (`pipefail`). |
| `dpkg -s apache2` | Consulta si el paquete ya está instalado. Si lo está, el script termina sin hacer nada. |
| `DEBIAN_FRONTEND=noninteractive` y `-y` | Instalación **sin intervención**: no hace ninguna pregunta. |
| `systemctl enable --now` | `enable` hace que arranque en cada inicio del sistema; `--now` lo arranca en ese momento. |

Esto convierte el script en **idempotente**: ejecutarlo una o varias veces deja el sistema en el mismo estado, sin reinstalar nada. Los módulos `ssl` y `rewrite` ya vienen con el paquete; se activan en el segundo script.

### 6.3 `scripts/setup_selfsigned_certificate.sh`

```bash
#!/bin/bash
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
```

**Paso a paso:**

1. **Comprobación previa.** Si Apache no está instalado, el script se detiene y avisa de que hay que ejecutar antes `install_apache.sh`. El orden de ejecución importa.
2. **Lectura del `.env`.** `SCRIPT_DIR` localiza la carpeta del script, así que funciona se ejecute desde donde se ejecute. `set -a` exporta automáticamente las variables que carga `source`, y `set +a` desactiva ese comportamiento.
3. **Generación del certificado.** Con un único comando `openssl` se crean la clave y el certificado:

   | Opción | Significado |
   |---|---|
   | `req -x509` | Genera directamente un certificado autofirmado, en lugar de una solicitud (CSR) para una CA. |
   | `-nodes` | La clave privada **no se cifra** con contraseña, para que Apache pueda arrancar sin pedirla. Es cómodo, pero obliga a proteger el archivo con permisos. |
   | `-days` | Validez del certificado (365). |
   | `-newkey rsa:2048` | Crea una clave RSA nueva de 2048 bits. |
   | `-keyout` / `-out` | Rutas de la clave privada y del certificado. |
   | `-subj` | Datos del sujeto (DN) en una línea, sin preguntas interactivas, lo que permite automatizar. |
   | `-addext subjectAltName` | Dominio y IP elástica para los que vale el certificado. |

   Campos del sujeto: **C** país, **ST** provincia, **L** localidad, **O** organización, **OU** unidad, **CN** nombre común, **emailAddress** correo.

4. **Permisos.** `chmod 600` deja la clave legible solo para root.
5. **Plantillas.** Se copian los archivos de `conf/` a `sites-available` y `sed` sustituye los marcadores (`DOMINIO_PLACEHOLDER`, `CERT_PLACEHOLDER`, `KEY_PLACEHOLDER`) por los valores del `.env`. Uso `|` como separador de `sed` porque las rutas contienen `/`.
6. **Módulos y sitio.** `a2enmod` activa `ssl` y `rewrite`; `a2ensite` crea el enlace del sitio en `sites-enabled`.
7. **Validación antes de reiniciar.** `apache2ctl configtest` comprueba la sintaxis. Si falla, el script termina **sin reiniciar**, para no dejar el servidor caído por una configuración errónea.

## 7. Plantillas de Apache (`conf/`)

### 7.1 `conf/000-default.conf` — HTTP con redirección

```apache
<VirtualHost *:80>
    ServerName DOMINIO_PLACEHOLDER
    DocumentRoot /var/www/html

    RewriteEngine On
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
</VirtualHost>
```

- `^` coincide con cualquier URL.
- `%{HTTP_HOST}` conserva el nombre del host y `%{REQUEST_URI}` conserva la ruta solicitada.
- `R=301` indica una redirección **permanente**; `L` detiene el procesado de más reglas.
- No hace falta `RewriteCond %{HTTPS} off`: en un VirtualHost del puerto 80 la conexión nunca es HTTPS.
- Existe una alternativa equivalente sin `mod_rewrite`: `Redirect permanent / https://practica-https.test/`.

### 7.2 `conf/practica-https-ssl.conf` — HTTPS

```apache
<VirtualHost *:443>
    ServerName DOMINIO_PLACEHOLDER
    DocumentRoot /var/www/html
    DirectoryIndex index.php index.html

    SSLEngine on
    SSLCertificateFile    CERT_PLACEHOLDER
    SSLCertificateKeyFile KEY_PLACEHOLDER

    ErrorLog ${APACHE_LOG_DIR}/practica-https-error.log
    CustomLog ${APACHE_LOG_DIR}/practica-https-access.log combined
</VirtualHost>
```

| Directiva | Función |
|---|---|
| `ServerName` | Dominio al que responde este sitio. |
| `DocumentRoot` | Carpeta de la que se sirven los archivos. |
| `SSLEngine on` | Activa TLS en este VirtualHost. |
| `SSLCertificateFile` | Ruta del certificado (público). |
| `SSLCertificateKeyFile` | Ruta de la clave privada. |
| `ErrorLog` / `CustomLog` | Registros propios de errores y accesos. |

Creé un archivo propio en lugar de sobrescribir `default-ssl.conf`, para no tocar la configuración que trae Apache. Al escribir las plantillas con `<< 'EOF'` (con comillas) bash no interpreta `${APACHE_LOG_DIR}` ni `%{HTTP_HOST}` y se guardan literales.

## 8. Ejecución del despliegue

Siempre en este orden, sobre la instancia recién creada:

```bash
dpkg -s apache2                        # debe indicar que NO está instalado
sudo ./scripts/install_apache.sh       # instalación
systemctl status apache2               # active (running) y enabled (salir con q)
sudo ./scripts/install_apache.sh       # 2.ª ejecución: "Apache ya está instalado."

cp scripts/.env.example scripts/.env
nano scripts/.env                      # poner la IP elástica real
git check-ignore -v scripts/.env       # confirma que Git lo ignora

sudo ./scripts/setup_selfsigned_certificate.sh
```

El segundo script terminó con `Syntax OK` y `HTTPS configurado para practica-https.test`. Los mensajes de `a2enmod` y `a2ensite` del tipo «you need to run systemctl restart apache2» son avisos genéricos: el propio script reinicia Apache al final.

## 9. Acceso desde el equipo cliente

`practica-https.test` no existe en ningún DNS, así que lo resuelvo manualmente en el equipo cliente (Linux Mint) añadiendo una línea a `/etc/hosts`:

```bash
echo "184.193.128.213   practica-https.test" | sudo tee -a /etc/hosts
getent hosts practica-https.test       # comprueba la resolución
```

Con esto el equipo traduce el dominio a la IP elástica de la instancia.

## 10. Verificación y evidencias

| Nº | Comprobación | Comando o acción | Resultado esperado | Evidencia |
|---|---|---|---|---|
| 1 | Instalación de Apache | `sudo ./scripts/install_apache.sh` y `systemctl status apache2` | Instala sin preguntas; `active (running)` y `enabled` | ![Instalación](img/01-install.png) ![Estado](img/01-status.png) |
| 2 | Reejecución del script | `sudo ./scripts/install_apache.sh` | `Apache ya está instalado.` sin reinstalar | ![Reejecución](img/02.png) |
| 3 | Certificado | `openssl x509 -in /etc/ssl/certs/apache-selfsigned.crt -noout -subject -dates -ext subjectAltName` | Mis datos, 365 días y dominio e IP en el SAN | ![Certificado](img/03.png) |
| 4 | Sintaxis de Apache | `sudo apache2ctl configtest` | `Syntax OK` | ![Configtest](img/04.png) |
| 5 | Puertos a la escucha | `sudo ss -tlnp \| grep apache2` | Apache escuchando en 80 y 443 | ![Puertos](img/05.png) |
| 6 | Redirección HTTP → HTTPS | `curl -I http://practica-https.test` | `HTTP/1.1 301` y `Location: https://...` | ![Redirección](img/06.png) |
| 7 | Respuesta HTTPS | `curl -kI https://practica-https.test` | `HTTP/1.1 200 OK` | ![HTTPS](img/07.png) |
| 8 | Negociación TLS | `openssl s_client -connect practica-https.test:443 -servername practica-https.test < /dev/null` | Versión TLS, cifrado y certificado | ![TLS](img/08.png) |
| 9 | Navegador | `https://practica-https.test` | Aviso de CA no confiable; tras aceptarlo se ve la web | ![Aviso](img/09a.png) ![Web](img/09b.png) ![Detalles](img/09c.png) |

### Cómo interpreto los resultados

- **Prueba 3.** El sujeto muestra mis datos (`C=ES, ST=Cantabria, L=Torrelavega, O=IES Miguel Herrero, OU=Informatica, CN=practica-https.test`). Entre `notBefore` y `notAfter` hay 365 días, y el SAN contiene `DNS:practica-https.test` e `IP Address:184.193.128.213`. Que estén los dos nombres es lo que permite acceder tanto por dominio como por IP sin error de nombre.
- **Prueba 5.** `ss -tlnp`: `t` TCP, `l` en escucha, `n` salida numérica, `p` proceso. Aparecen `:80` y `:443`.
- **Prueba 6.** `curl -I` pide solo las cabeceras. El código **301** significa «movido permanentemente»; el navegador recordará la redirección.
- **Prueba 7.** `-k` hace que `curl` acepte el certificado aunque no sea de confianza. Sin esa opción fallaría por ser autofirmado.
- **Prueba 8.** `-servername` envía el **SNI**, que indica al servidor qué dominio quiere el cliente. Al final, `[COMPLETAR: Verify return code]` (con un certificado autofirmado se espera el código 18, `self-signed certificate`: la conexión TLS se establece, pero el cliente no puede validar al emisor). Versión TLS negociada: `[COMPLETAR]`. Cifrado: `[COMPLETAR]`.
- **Prueba 9.** Chrome muestra `NET::ERR_CERT_AUTHORITY_INVALID` porque no reconoce al emisor. Tras aceptar la excepción se ve la página de Apache y, en los detalles del certificado, mis datos.

Las pruebas 1 y 2 se hicieron sobre una instancia recién creada; las 6 y 7, desde mi equipo, lo que comprueba también el Security Group.

## 11. Comprobaciones adicionales

### Acceso por IP elástica

Además de por dominio, accedí por IP. Como la IP está en el SAN, el certificado es válido para esa dirección (el navegador sigue avisando porque no lo firma una CA conocida).

```bash
curl -I  http://184.193.128.213       # 301 → https://184.193.128.213/
curl -kI https://184.193.128.213      # 200 OK
```

![Acceso por IP](img/extra-curl-ip.png)

Con `%{HTTP_HOST}` la redirección conserva la IP, de modo que `http://IP` lleva a `https://IP`.

## 12. Problemas encontrados y cómo se resolvieron

### 12.1 `Permission denied (publickey)` al clonar por SSH

- **Causa:** la URL `git@github.com:...` usa SSH y la instancia no tenía ninguna clave registrada en mi cuenta.
- **Solución:** generar una clave `ed25519` en la instancia y registrar la pública en GitHub (apartado 4.1).

### 12.2 GitHub no aceptaba mi contraseña por HTTPS

- **Causa:** GitHub ya no admite la contraseña de la cuenta en operaciones por HTTPS; exige un token personal.
- **Lección:** un token es un secreto y no debe pegarse en chats ni archivos. Cuando uno queda expuesto hay que **revocarlo** de inmediato, como hice. Finalmente adopté la clave SSH, que no caduca y no obliga a manejar el token.

### 12.3 Timeout al acceder por HTTP y HTTPS

- **Síntoma:** `curl` fallaba con `Connection timed out` sobre el dominio y sobre la IP.
- **Razonamiento:** un *timeout* indica que los paquetes **se descartan por el camino** (cortafuegos o Security Group); un *connection refused* indicaría que llegan, pero no hay nadie escuchando (por ejemplo, Apache parado).
- **Diagnóstico:** probé los puertos uno a uno desde mi equipo:
  ```bash
  nc -zv -w 5 184.193.128.213 22     # succeeded
  nc -zv -w 5 184.193.128.213 80     # timed out
  nc -zv -w 5 184.193.128.213 443    # timed out
  ```
  El 22 abría y el 80 y el 443 no, así que la máquina era alcanzable y el fallo estaba en el Security Group.
- **Causa real:** había añadido las reglas de entrada pero **no las había guardado** (*Save rules*).
- **Solución:** guardarlas. Tras ello `nc` dio `succeeded` en 80 y 443 y las pruebas 6 a 9 funcionaron.

## 13. Seguridad

- La clave privada del certificado vive en `/etc/ssl/private/` con permisos `600`; el certificado, público, en `/etc/ssl/certs/`.
- `.env`, `*.key` y `*.pem` están en `.gitignore`, y comprobé con `git ls-files` que no se sube ninguno.
- Las claves SSH (`.pem` de AWS e `id_ed25519` de la instancia) permanecen fuera del repositorio.
- Antes de publicar las capturas revisé que ninguna mostrara claves, tokens ni credenciales del laboratorio.
- El certificado autofirmado es solo para docencia y pruebas. En un servicio real habría que usar un certificado emitido por una CA reconocida.
- `-nodes` deja la clave sin contraseña: es cómodo para automatizar, pero hace imprescindible proteger bien el archivo.

## 14. Cierre del laboratorio

Con las capturas hechas, el `push` realizado y el repositorio comprobado en GitHub:

1. **Detuve** la instancia (*Stop*, no *Terminate*), con lo que deja de cobrarse el cómputo.
2. **Desasocié y liberé** la IP elástica. Una IP elástica que no está asociada a una instancia en marcha sigue generando coste, y no se libera sola al terminar la sesión del laboratorio.
3. Eliminé de GitHub la clave SSH de la instancia, que ya no hace falta.

Si volviera a arrancar la instancia, tendría otra IP pública y el certificado actual llevaría en el SAN la IP antigua, por lo que habría que regenerarlo.

## 15. Conclusiones

- Todo el despliegue queda **automatizado y reproducible**: dos scripts y un `.env` bastan para pasar de una instancia Ubuntu vacía a un Apache con HTTPS.
- El primer script es **idempotente** y el segundo **valida la configuración antes de reiniciar**, de forma que un error no deja el servicio caído.
- Separar plantillas (`conf/`), código (`scripts/`) y configuración (`.env`) facilita reutilizarlo con otro dominio o IP.
- Un certificado autofirmado cifra igual que uno de una CA, pero no aporta confianza: el aviso del navegador es el comportamiento correcto.
- La mayor parte del tiempo de depuración no fue de Apache, sino de **red y credenciales** (Security Group sin guardar y autenticación con GitHub). Diagnosticar por capas —resolución de nombres, conectividad por puerto, cortafuegos y, por último, el servicio— ahorra mucho tiempo.
