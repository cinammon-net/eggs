# Fluxer en un solo contenedor para Pelican (Cinammon).
# Junta las imágenes oficiales de Fluxer (todas Debian 13) con Postgres, NATS y Caddy.
# Versión de Fluxer: paquete compose 2026.1124.80040
FROM ghcr.io/fluxerapp/fluxer-server@sha256:27036a0619da301f0f0e2914edb1bc002c5e8e1a51e3602dffc39fec648fe105 AS server
FROM ghcr.io/fluxerapp/fluxer-api@sha256:27d02b3cb9db84abfbe16f9f93bfee9df20b96c5063d33b1dd57189245a42ae7 AS api
FROM ghcr.io/fluxerapp/fluxer-gateway@sha256:609cc1a8c784ef902a192ae4482fa4972428379f3b078d0845d57d1f80669db0 AS gateway
FROM ghcr.io/fluxerapp/fluxer-static@sha256:491a5d7850e3794a3b03b95678c84fdb2d98f1a5cfcc5dee90ff952947800242 AS static
FROM nats:2.14-alpine AS nats

FROM ghcr.io/fluxerapp/fluxer-media-proxy@sha256:af113983fd545d843d1ee9804765d01684290d15040c3e5faf76dac11c0f6727
USER 0
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends postgresql-17 postgresql-contrib iproute2 procps ca-certificates curl openssl libnss-wrapper openssl \
 && rm -rf /var/lib/apt/lists/*
COPY --from=nats /usr/local/bin/nats-server /usr/local/bin/nats-server
COPY --from=static /usr/bin/caddy /usr/bin/caddy
COPY --from=static /srv/fluxer-static /srv/fluxer-static
COPY --from=server /usr/local/bin/fluxer-server /usr/local/bin/fluxer-server
COPY --from=server /srv/app /srv/app
COPY --from=api /usr/local/bin/node /usr/local/bin/node
COPY --from=api /usr/src/app /usr/src/app
COPY --from=gateway /usr/local/lib/erlang /usr/local/lib/erlang
COPY --from=gateway /opt/fluxer_gateway /opt/fluxer_gateway
COPY --from=gateway /opt/fluxer_bouncer /opt/fluxer_bouncer
RUN ln -sf ../lib/erlang/bin/erl /usr/local/bin/erl \
 && useradd -m -d /home/container -u 988 -s /bin/bash container 2>/dev/null || true
COPY run.sh /usr/local/bin/fluxer-run
COPY Caddyfile.edge /etc/fluxer/Caddyfile.edge
COPY Caddyfile.static /etc/fluxer/Caddyfile.static
COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /usr/local/bin/fluxer-run /entrypoint.sh
ENV PATH=/usr/lib/postgresql/17/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    LD_PRELOAD= HOME=/home/container USER=container
USER container
WORKDIR /home/container
HEALTHCHECK NONE
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/entrypoint.sh"]
