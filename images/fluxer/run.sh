#!/bin/bash
# Fluxer en un solo servidor de Cinammon.
# Arranca Postgres, NATS y las piezas de Fluxer, y la puerta de entrada en el puerto del servidor.
# Todo lo que se guarda vive en /home/container/data.
set -uo pipefail

HOME_DIR=/home/container
DATA=$HOME_DIR/data
RUN=$DATA/run
SECRETS=$DATA/secretos.env
PIDS=()
NAMES=()

say() { printf '\033[1;35m[Cinammon]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[Cinammon]\033[0m %s\n' "$*"; exit 1; }

: "${SERVER_PORT:?Falta SERVER_PORT}"
DOMAIN="${FLUXER_DOMAIN:-${CIN_SITE_HOST:-}}"
DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN%%/*}"
if [ -z "$DOMAIN" ]; then
	say "Tu Fluxer todavía no tiene dirección."
	say "El panel la pone sola en menos de un minuto (tunombre-xxxx.cinammon.net)."
	say "Espera un momento y pulsa Reiniciar."
	exit 1
fi

mkdir -p "$DATA/postgres" "$DATA/nats" "$DATA/objects" "$RUN" "$DATA/tmp"
chmod 700 "$DATA/postgres"

# ---------- secretos (se crean una sola vez y no cambian) ----------
hex() { openssl rand -hex 32; }
if [ ! -s "$SECRETS" ]; then
	say "Primer arranque: creando las claves de tu Fluxer..."
	vapid_pem=$(mktemp)
	openssl ecparam -name prime256v1 -genkey -noout -out "$vapid_pem" 2>/dev/null
	vapid_pub=$(openssl ec -in "$vapid_pem" -pubout -outform DER 2>/dev/null | tail -c 65 | base64 | tr '/+' '_-' | tr -d '=\n')
	vapid_priv=$(openssl ec -in "$vapid_pem" -outform DER 2>/dev/null | tail -c +8 | head -c 32 | base64 | tr '/+' '_-' | tr -d '=\n')
	rm -f "$vapid_pem"
	umask 077
	cat >"$SECRETS" <<EOF
POSTGRES_PASSWORD=$(hex)
FLUXER_SUDO_MODE_SECRET=$(hex)
FLUXER_CONNECTION_INITIATION_SECRET=$(hex)
FLUXER_PROFILE_PSEUDONYM_SECRET=$(hex)
FLUXER_GATEWAY_RPC_AUTH_TOKEN=$(hex)
FLUXER_ERLANG_COOKIE=$(hex)
FLUXER_MEDIA_PROXY_SECRET_KEY=$(hex)
FLUXER_ADMIN_SECRET_KEY_BASE=$(hex)
FLUXER_ADMIN_OAUTH_CLIENT_SECRET=$(hex)
FLUXER_NATS_AUTH_TOKEN=$(hex)
FLUXER_SETUP_TOKEN=$(hex)
FLUXER_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64=$(openssl rand -base64 32)
FLUXER_MEDIA_PROXY_ATTACHMENT_URL_SECRETS_BASE64=$(openssl rand -base64 32)
FLUXER_VAPID_PUBLIC_KEY=$vapid_pub
FLUXER_VAPID_PRIVATE_KEY=$vapid_priv
EOF
	umask 022
fi
set -a; . "$SECRETS"; set +a

# ---------- puertos internos (solo dentro del contenedor) ----------
export P_API=3101 P_GATEWAY=3102 P_MEDIA=3103 P_STATIC=3104 P_SVC=3105 P_APP=3106 P_ADMIN=3107 \
	P_PUSH=3108 P_DISCOVERY=3188 P_PG=5432 P_NATS=4222
ORIGIN="https://$DOMAIN"

# ---------- ajustes comunes de Fluxer ----------
export FLUXER_ENV=production FLUXER_SELF_HOSTED=true \
	FLUXER_BASE_DOMAIN="$DOMAIN" FLUXER_DOMAIN="$DOMAIN" FLUXER_PUBLIC_SCHEME=https FLUXER_PUBLIC_PORT=443 \
	FLUXER_PUBLIC_ORIGIN="$ORIGIN" FLUXER_APP_ENDPOINT="$ORIGIN" FLUXER_MARKETING_ENDPOINT="$ORIGIN" \
	FLUXER_MEDIA_ENDPOINT="$ORIGIN/media" FLUXER_MEDIA_PROXY_PUBLIC_ENDPOINT="$ORIGIN/media" \
	FLUXER_MEDIA_PROXY_UPLOAD_RELAY_ENDPOINT="$ORIGIN/media" FLUXER_ADMIN_ENDPOINT="$ORIGIN/admin" \
	FLUXER_GATEWAY_MEDIA_PROXY_ENDPOINT="$ORIGIN/media" FLUXER_GATEWAY_STATIC_CDN_ENDPOINT="$ORIGIN" \
	FLUXER_PASSKEY_RP_ID="$DOMAIN" FLUXER_PASSKEY_ADDITIONAL_ALLOWED_ORIGINS="$ORIGIN" \
	FLUXER_VAPID_EMAIL="admin@$DOMAIN" FLUXER_EMAIL_FROM_EMAIL="noreply@$DOMAIN" \
	FLUXER_TRUST_CLIENT_IP_HEADER=true \
	FLUXER_INTERNAL_API_ENDPOINT="http://127.0.0.1:$P_API" \
	FLUXER_INTERNAL_MEDIA_PROXY_ENDPOINT="http://127.0.0.1:$P_MEDIA" \
	FLUXER_DATABASE_BACKEND=postgres FLUXER_POSTGRES_HOST=127.0.0.1 FLUXER_POSTGRES_PORT=$P_PG \
	FLUXER_POSTGRES_DATABASE=fluxer FLUXER_POSTGRES_USERNAME=fluxer FLUXER_POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
	FLUXER_POSTGRES_URL="postgres://fluxer:$POSTGRES_PASSWORD@127.0.0.1:5432/fluxer" \
	FLUXER_KV_MODE=postgres \
	FLUXER_NATS_URL="nats://127.0.0.1:$P_NATS" FLUXER_NATS_JETSTREAM_URL="nats://127.0.0.1:$P_NATS" \
	FLUXER_SVC_NATS_URL="nats://127.0.0.1:$P_NATS" FLUXER_SVC_SHARD_COUNT=1 \
	FLUXER_SEARCH_ENGINE=none \
	FLUXER_STORAGE_BACKEND=filesystem FLUXER_STORAGE_ROOT="$DATA/objects" FLUXER_STORAGE_UPLOADS_TTL=1d \
	FLUXER_MEDIA_PROXY_STORAGE_BACKEND=local FLUXER_MEDIA_PROXY_STORAGE_ROOT="$DATA/objects" \
	FLUXER_LIVEKIT_ENABLED=false FLUXER_LIVEKIT_BUNDLED=false \
	FLUXER_API_PRESIGNED_HARVEST_DOWNLOADS_ENABLED=false \
	FLUXER_APP_PRODUCT_NAME="${FLUXER_APP_PRODUCT_NAME:-}" \
	TMPDIR="$DATA/tmp" MALLOC_ARENA_MAX=2 TOKIO_WORKER_THREADS=2 \
	NO_PROXY=localhost,127.0.0.1 no_proxy=localhost,127.0.0.1
[ -n "${FLUXER_APP_PRODUCT_NAME:-}" ] || unset FLUXER_APP_PRODUCT_NAME
(umask 077; export -p >"$RUN/entorno.sh")

# ---------- arrancar y vigilar procesos ----------
start() { # start <nombre> <comando...>
	local name=$1; shift
	( exec "$@" ) > >(sed -u "s/^/[$name] /") 2>&1 &
	PIDS+=($!); NAMES+=("$name")
}
wait_port() { # wait_port <puerto> <nombre> <segundos>
	for _ in $(seq 1 "$3"); do
		(exec 3<>/dev/tcp/127.0.0.1/"$1") 2>/dev/null && return 0
		sleep 1
	done
	die "$2 no ha arrancado a tiempo (puerto $1)."
}
stopping=0
shutdown() {
	[ $stopping = 1 ] && return; stopping=1
	say "Apagando Fluxer..."
	for ((i=${#PIDS[@]}-1; i>=1; i--)); do kill -TERM "${PIDS[$i]}" 2>/dev/null; done
	for _ in $(seq 1 20); do
		alive=0; for ((i=${#PIDS[@]}-1; i>=1; i--)); do kill -0 "${PIDS[$i]}" 2>/dev/null && alive=1; done
		[ $alive = 0 ] && break; sleep 1
	done
	pg_ctl -D "$DATA/postgres" -m fast -w stop >/dev/null 2>&1
	say "Fluxer apagado."
	exit 0
}
trap shutdown INT TERM

# 1. Postgres
if [ ! -s "$DATA/postgres/PG_VERSION" ]; then
	say "Preparando la base de datos..."
	pw=$(mktemp); printf '%s' "$POSTGRES_PASSWORD" >"$pw"
	initdb -D "$DATA/postgres" -U fluxer --pwfile="$pw" --auth=scram-sha-256 -E UTF8 --locale=C.UTF-8 >/dev/null || die "No se pudo crear la base de datos."
	rm -f "$pw"
fi
cat >"$DATA/postgres/cinammon.conf" <<EOF
listen_addresses = '127.0.0.1'
port = $P_PG
unix_socket_directories = '$RUN'
dynamic_shared_memory_type = mmap
max_connections = 120
shared_buffers = ${FLUXER_PG_SHARED_BUFFERS:-256MB}
effective_cache_size = 1GB
work_mem = 8MB
maintenance_work_mem = 128MB
jit = off
max_wal_size = 1GB
wal_compression = zstd
random_page_cost = 1.1
logging_collector = off
log_min_messages = warning
EOF
grep -q "include_if_exists = 'cinammon.conf'" "$DATA/postgres/postgresql.conf" || echo "include_if_exists = 'cinammon.conf'" >>"$DATA/postgres/postgresql.conf"
rm -f "$DATA/postgres/postmaster.pid"
start postgres postgres -D "$DATA/postgres"
wait_port $P_PG Postgres 60
for _ in $(seq 1 30); do pg_isready -h 127.0.0.1 -p $P_PG -U fluxer >/dev/null 2>&1 && break; sleep 1; done
PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -p $P_PG -U fluxer -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='fluxer'" | grep -q 1 \
	|| PGPASSWORD="$POSTGRES_PASSWORD" createdb -h 127.0.0.1 -p $P_PG -U fluxer fluxer

# 2. NATS
cat >"$RUN/nats.conf" <<EOF
listen: 127.0.0.1:$P_NATS
http: 127.0.0.1:8222
authorization { token: "$FLUXER_NATS_AUTH_TOKEN" }
jetstream { store_dir: "$DATA/nats", max_memory_store: 64MB, max_file_store: 4GB }
EOF
start nats nats-server -c "$RUN/nats.conf"
wait_port $P_NATS NATS 30

# 3. Archivos subidos
for d in "$DATA/objects" "$DATA/objects/.staging" "$DATA/objects/.staging/tmp" "$DATA/objects/.staging/multipart" "$DATA/objects/.staging/trash" "$DATA/objects/.meta"; do mkdir -p "$d"; done
[ -e "$DATA/objects/.layout" ] || printf '{"v":1}' >"$DATA/objects/.layout"

# 4. Servidor principal (usuarios, mensajes, app, admin, avisos)
start servidor env LD_PRELOAD=libjemalloc.so.2 \
	FLUXER_SERVER_SERVICES=snowflakes,users,messages,gifs,unfurl,push,app-proxy,admin \
	FLUXER_SVC_LISTEN_HOST=127.0.0.1 FLUXER_SVC_MODE=combined \
	FLUXER_SERVER_SNOWFLAKES__FLUXER_SVC_NAME=snowflakes FLUXER_SERVER_SNOWFLAKES__FLUXER_SVC_PORT=18090 FLUXER_SERVER_SNOWFLAKES__FLUXER_SVC_METRICS_PORT=18190 FLUXER_SERVER_SNOWFLAKES__FLUXER_SNOWFLAKES_WORKER_GUARD=true \
	FLUXER_SERVER_USERS__FLUXER_SVC_NAME=users FLUXER_SERVER_USERS__FLUXER_SVC_PORT=18091 FLUXER_SERVER_USERS__FLUXER_SVC_METRICS_PORT=18191 \
	FLUXER_SERVER_MESSAGES__FLUXER_SVC_NAME=messages FLUXER_SERVER_MESSAGES__FLUXER_SVC_PORT=18092 FLUXER_SERVER_MESSAGES__FLUXER_SVC_METRICS_PORT=18192 \
	FLUXER_SERVER_GIFS__FLUXER_SVC_NAME=gifs FLUXER_SERVER_GIFS__FLUXER_SVC_PORT=18093 FLUXER_SERVER_GIFS__FLUXER_SVC_METRICS_PORT=18193 \
	FLUXER_SERVER_UNFURL__FLUXER_SVC_NAME=unfurl FLUXER_SERVER_UNFURL__FLUXER_SVC_PORT=18094 FLUXER_SERVER_UNFURL__FLUXER_SVC_METRICS_PORT=18194 \
	FLUXER_SERVER_UNFURL__FLUXER_MEDIA_PROXY_ENDPOINT="http://127.0.0.1:$P_MEDIA" FLUXER_SERVER_ADMIN__FLUXER_API_ENDPOINT="http://127.0.0.1:$P_API" \
	FLUXER_APP_PROXY_HOST=127.0.0.1 FLUXER_APP_PROXY_PORT=$P_APP FLUXER_STATIC_DIR=/srv/app/static \
	DISCOVERY_UPSTREAM_URL="http://127.0.0.1:$P_DISCOVERY/.well-known/fluxer" DISCOVERY_REFRESH_INTERVAL_MS=5000 \
	FLUXER_ADMIN_HOST=127.0.0.1 FLUXER_ADMIN_PORT=$P_ADMIN \
	FLUXER_PUSH_SERVICE_HOST=127.0.0.1 FLUXER_PUSH_SERVICE_PORT=$P_PUSH FLUXER_PUSH_METRICS_PORT=3118 \
	FLUXER_POSTGRES_MAX_CONNECTIONS=20 \
	/usr/local/bin/fluxer-server

# 5. Imágenes y archivos
start imagenes env LD_PRELOAD=libjemalloc.so.2 VIPS_CONCURRENCY=1 VIPS_DISC_THRESHOLD=1g \
	FLUXER_MEDIA_PROXY_HOST=127.0.0.1 FLUXER_MEDIA_PROXY_PORT=$P_MEDIA FLUXER_MEDIA_PROXY_METRICS_PORT=3113 \
	FLUXER_MEDIA_PROXY_MODE=upload FLUXER_MEDIA_PROXY_CORS_ALLOWED_ORIGINS="$ORIGIN" \
	/usr/local/bin/fluxer-media-proxy

# 6. API y tareas en segundo plano
cd /usr/src/app/fluxer_api
start api env FLUXER_API_HOST=127.0.0.1 FLUXER_API_PORT=$P_API FLUXER_API_METRICS_PORT=3111 \
	NODE_ENV=production NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
	NODE_OPTIONS="--max-old-space-size=${FLUXER_API_HEAP_MB:-768}" UV_THREADPOOL_SIZE=8 \
	FLUXER_POSTGRES_MAX_CONNECTIONS=25 FLUXER_API_EMBEDDED_WORKER=false \
	FLUXER_API_PRESIGNED_ATTACHMENT_UPLOADS_ENABLED=true \
	node dist/AppEntrypoint.js
start tareas env FLUXER_API_WORKER_METRICS_PORT=3112 FLUXER_API_PORT=3119 FLUXER_API_METRICS_PORT=3120 \
	NODE_ENV=production NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
	NODE_OPTIONS="--max-old-space-size=${FLUXER_WORKER_HEAP_MB:-512}" UV_THREADPOOL_SIZE=8 \
	FLUXER_API_WORKER_MODE=all_lanes FLUXER_API_WORKER_ENABLE_CRON_SCHEDULER=true FLUXER_POSTGRES_MAX_CONNECTIONS=15 \
	node dist/WorkerEntrypoint.js
cd "$HOME_DIR"

# 7. Tiempo real (gateway)
start gateway env FLUXER_GATEWAY_PORT=$P_GATEWAY FLUXER_ERLANG_DIST_PORT=3121 FLUXER_GATEWAY_RUN_DIR="$RUN" \
	FLUXER_ERLANG_SCHEDULERS_MAX=4 HOME="$RUN" \
	/opt/fluxer_gateway/bin/docker_entrypoint.sh

# 8. Archivos de la web y puerta de entrada
start web caddy run --config /etc/fluxer/Caddyfile.static --adapter caddyfile
start entrada caddy run --config /etc/fluxer/Caddyfile.edge --adapter caddyfile

wait_port $P_API API 180
wait_port "$SERVER_PORT" "La puerta de entrada" 30
say "--------------------------------------------------------------"
say "Tu Fluxer está en marcha: $ORIGIN"
if [ ! -e "$DATA/.admin-creado" ]; then
	say "Para crear tu cuenta de administrador, abre la dirección y"
	say "pega este código de primer uso:"
	say "    $FLUXER_SETUP_TOKEN"
	say "(También está en data/secretos.env, en FLUXER_SETUP_TOKEN.)"
fi
say "--------------------------------------------------------------"

# Vigilar: si una pieza se cae, se avisa y se apaga todo (el panel lo marca y puedes reiniciar)
while true; do
	sleep 5
	for i in "${!PIDS[@]}"; do
		kill -0 "${PIDS[$i]}" 2>/dev/null && continue
		[ $stopping = 1 ] && exit 0
		say "${NAMES[$i]} se ha parado. Apagando para que puedas reiniciar."
		shutdown_reason=1; shutdown; exit 1
	done
done
