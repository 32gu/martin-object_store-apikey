# Imagen base: Ubuntu 24.04 LTS
FROM ubuntu:24.04

# Metadata de la imagen
LABEL org.opencontainers.image.title="Martin Tile Server (Custom Build)"
LABEL org.opencontainers.image.description="Blazing fast tile server with PostGIS, MBTiles, and PMTiles support"
LABEL org.opencontainers.image.source="https://github.com/maplibre/martin"
LABEL org.opencontainers.image.licenses="Apache-2.0 OR MIT"
LABEL org.opencontainers.image.documentation="https://maplibre.org/martin/"

# Instalar dependencias runtime necesarias
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        mesa-vulkan-drivers \
        libcurl4 \
        libglfw3 \
        libicu74 \
        libjpeg-turbo8 \
        libpng16-16t64 \
        libuv1 \
        libwebp7 \
        wget \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Copiar binarios precompilados desde el host
COPY binaries/martin /usr/local/bin/martin
COPY binaries/martin-cp /usr/local/bin/martin-cp
COPY binaries/mbtiles /usr/local/bin/mbtiles

# Asegurar que los binarios son ejecutables
RUN chmod +x /usr/local/bin/martin && \
    chmod +x /usr/local/bin/martin-cp && \
    chmod +x /usr/local/bin/mbtiles

# Verificar que los binarios funcionan
RUN /usr/local/bin/martin --version && \
    /usr/local/bin/martin-cp --version && \
    /usr/local/bin/mbtiles --version

# Health check para verificar que el servidor responde
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --spider http://127.0.0.1:3000/health || exit 1

# Exponer puerto por defecto de Martin
EXPOSE 3000

# Punto de entrada: ejecutar martin
ENTRYPOINT ["/usr/local/bin/martin"]

# Comando por defecto: mostrar ayuda si no se pasan argumentos
CMD ["--help"]
