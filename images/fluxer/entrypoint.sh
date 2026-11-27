#!/bin/bash
# Arranque al estilo Pelican: entra en /home/container y ejecuta el STARTUP del egg.
cd /home/container || exit 1
# Postgres necesita que el usuario exista; si el panel usa otro UID, se crea uno de mentira.
if ! getent passwd "$(id -u)" >/dev/null 2>&1; then
	export NSS_WRAPPER_PASSWD=/tmp/passwd NSS_WRAPPER_GROUP=/tmp/group
	cp /etc/passwd "$NSS_WRAPPER_PASSWD"; cp /etc/group "$NSS_WRAPPER_GROUP"
	echo "container:x:$(id -u):$(id -g)::/home/container:/bin/bash" >>"$NSS_WRAPPER_PASSWD"
	echo "container:x:$(id -g):" >>"$NSS_WRAPPER_GROUP"
	export LD_PRELOAD=libnss_wrapper.so
fi
export INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}')
STARTUP=${STARTUP:-fluxer-run}
MODIFIED_STARTUP=$(echo -e "$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')")
echo "container@cinammon~ ${MODIFIED_STARTUP}"
eval ${MODIFIED_STARTUP}
