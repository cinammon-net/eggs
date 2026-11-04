#!/bin/bash
# Cinammon WebHost · entrada del contenedor (Wings pasa el comando en $STARTUP)
cd /home/container || exit 1
export INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}')

# {{VARIABLE}} -> ${VARIABLE}
MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e ":/home/container$ ${MODIFIED_STARTUP}"
eval "${MODIFIED_STARTUP}"
