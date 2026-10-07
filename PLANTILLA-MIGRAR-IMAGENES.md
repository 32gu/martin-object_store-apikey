# Plantilla para Migrar Otras Imágenes

Para migrar otras imágenes, simplemente ejecuta el script con variables de entorno:

## Ejemplo 1: Usando variables de entorno

```bash
DOCKER_HUB_IMAGE="nginx" \
DOCKER_HUB_TAG="alpine" \
ACR_NAME="crtdpnortheu" \
ACR_IMAGE_NAME="nginx-custom" \
ACR_TAG="alpine" \
./migrate-image-to-acr.sh
```

## Ejemplo 2: Migrar una imagen privada de Docker Hub

```bash
# Primero autenticarse en Docker Hub si es privada
docker login

# Luego migrar
DOCKER_HUB_IMAGE="tu-usuario/imagen-privada" \
DOCKER_HUB_TAG="v2.0" \
ACR_NAME="crtdpnortheu" \
ACR_IMAGE_NAME="imagen-privada" \
ACR_TAG="v2.0" \
./migrate-image-to-acr.sh
```

## Ejemplo 3: Migrar múltiples imágenes con un loop

```bash
#!/bin/bash

# Lista de imágenes a migrar
declare -A images=(
    ["geragb/martin-fix-v2:latest"]="martin-fix-v2:latest"
    ["nginx:alpine"]="nginx:alpine"
    ["redis:7"]="redis:7"
)

# Migrar cada una
for source in "${!images[@]}"; do
    target="${images[$source]}"
    
    IFS=':' read -r img_name img_tag <<< "$source"
    IFS=':' read -r acr_name acr_tag <<< "$target"
    
    echo "Migrando $source → crtdpnortheu.azurecr.io/$target"
    
    DOCKER_HUB_IMAGE="$img_name" \
    DOCKER_HUB_TAG="$img_tag" \
    ACR_NAME="crtdpnortheu" \
    ACR_IMAGE_NAME="$acr_name" \
    ACR_TAG="$acr_tag" \
    ./migrate-image-to-acr.sh
    
    echo ""
done
```

## Ejemplo 4: Desde otro registry (no Docker Hub)

```bash
# Si la imagen viene de otro registry (ej: ghcr.io, quay.io)
SOURCE_REGISTRY="ghcr.io"
SOURCE_IMAGE="owner/repo"
SOURCE_TAG="latest"

# Pull desde el registry origen
docker pull ${SOURCE_REGISTRY}/${SOURCE_IMAGE}:${SOURCE_TAG}

# Tag para ACR
docker tag ${SOURCE_REGISTRY}/${SOURCE_IMAGE}:${SOURCE_TAG} crtdpnortheu.azurecr.io/${SOURCE_IMAGE}:${SOURCE_TAG}

# Push a ACR
az acr login --name crtdpnortheu
docker push crtdpnortheu.azurecr.io/${SOURCE_IMAGE}:${SOURCE_TAG}
```

## Uso rápido para tu imagen actual

```bash
# Ejecuta directamente con valores por defecto ya configurados
./migrate-image-to-acr.sh
```

O con confirmación:

```bash
# Ver ayuda
./migrate-image-to-acr.sh --help

# Modo verbose
./migrate-image-to-acr.sh --verbose
```

---

## Casos de uso comunes

### Migrar imagen de producción a staging

```bash
# Primero migrar como latest
./migrate-image-to-acr.sh

# Luego crear tag de staging
az acr import \
  --name crtdpnortheu \
  --source crtdpnortheu.azurecr.io/martin-fix-v2:latest \
  --image martin-fix-v2:staging
```

### Crear múltiples tags en ACR

```bash
# Migrar la imagen una vez
./migrate-image-to-acr.sh

# Luego crear tags adicionales
docker tag crtdpnortheu.azurecr.io/martin-fix-v2:latest crtdpnortheu.azurecr.io/martin-fix-v2:v1.0
docker tag crtdpnortheu.azurecr.io/martin-fix-v2:latest crtdpnortheu.azurecr.io/martin-fix-v2:stable

docker push crtdpnortheu.azurecr.io/martin-fix-v2:v1.0
docker push crtdpnortheu.azurecr.io/martin-fix-v2:stable
```

### Migrar con compresión automática

```bash
# ACR optimiza automáticamente, pero puedes forzar recompresión
docker pull geragb/martin-fix-v2:latest
docker save geragb/martin-fix-v2:latest | docker load
# Ahora hacer push normal
```
