# Headless authoritative game server. Build the engine's Linux template and export the
# "Linux Server" preset first (see docs/DEPLOY.md), so build/server/ holds the binary and its .pck.
#   docker build -f game/deploy/server.Dockerfile -t albion-after-server .
#   docker run -d -p 24565:24565/udp --name world albion-after-server
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /usr/sbin/nologin game
WORKDIR /home/game
COPY build/server/ ./
RUN chmod +x ./albion_after_server.x86_64 && chown -R game:game /home/game
USER game
EXPOSE 24565/udp
# NAKAMA is host:port of the accounts service; leave empty for an offline guest world.
ENV PORT=24565 NAKAMA=""
ENTRYPOINT ["/bin/sh", "-c", "exec ./albion_after_server.x86_64 --headless --script res://scripts/server/server_main.gd -- --port \"$PORT\" ${NAKAMA:+--nakama \"$NAKAMA\"}"]
