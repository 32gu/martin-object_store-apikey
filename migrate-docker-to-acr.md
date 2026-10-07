# Guía: Migrar Imagen Docker de Docker Hub a Azure Container Registry

## Variables de configuración

Para este caso específico:
```bash
# Configuración de la imagen origen (Docker Hub)
DOCKER_HUB_IMAGE="geragb/martin-fix-v2"
DOCKER_HUB_TAG="latest"

# Configuración de Azure Container Registry
ACR_NAME="crtdpnortheu"
ACR_IMAGE_NAME="martin-fix-v2"
ACR_TAG="latest"
```

---

## Pasos de Migración

### 1. Descargar la imagen desde Docker Hub

```bash
docker pull ${DOCKER_HUB_IMAGE}:${DOCKER_HUB_TAG}
```

O con los valores específicos:
```bash
docker pull geragb/martin-fix-v2:latest
```

### 2. Verificar que la imagen se descargó correctamente

```bash
docker images | grep martin-fix-v2
```

### 3. Autenticarse en Azure Container Registry

```bash
az acr login --name ${ACR_NAME}
```

O con el valor específico:
```bash
az acr login --name crtdpnortheu
```

> **Nota:** Si no tienes `az` CLI instalado, puedes instalarlo siguiendo: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli

### 4. Etiquetar la imagen con el nuevo registro

```bash
docker tag ${DOCKER_HUB_IMAGE}:${DOCKER_HUB_TAG} ${ACR_NAME}.azurecr.io/${ACR_IMAGE_NAME}:${ACR_TAG}
```

O con los valores específicos:
```bash
docker tag geragb/martin-fix-v2:latest crtdpnortheu.azurecr.io/martin-fix-v2:latest
```

### 5. Subir la imagen a Azure Container Registry

```bash
docker push ${ACR_NAME}.azurecr.io/${ACR_IMAGE_NAME}:${ACR_TAG}
```

O con los valores específicos:
```bash
docker push crtdpnortheu.azurecr.io/martin-fix-v2:latest
```

### 6. Verificar que la imagen está en ACR

```bash
az acr repository list --name ${ACR_NAME} --output table
```

O:
```bash
az acr repository show-tags --name ${ACR_NAME} --repository ${ACR_IMAGE_NAME} --output table
```

Con valores específicos:
```bash
az acr repository list --name crtdpnortheu --output table
az acr repository show-tags --name crtdpnortheu --repository martin-fix-v2 --output table
```

---

## Actualizar Azure Container App

### Opción 1: Usando Azure Portal
1. Ve a tu Container App en el portal de Azure
2. En "Containers", edita el contenedor
3. Cambia la imagen de `docker.io/geragb/martin-fix-v2:latest` a `crtdpnortheu.azurecr.io/martin-fix-v2:latest`
4. Guarda y despliega

### Opción 2: Usando Azure CLI

```bash
# Variables para Container App
RESOURCE_GROUP="<tu-resource-group>"
CONTAINER_APP_NAME="<tu-container-app-name>"
CONTAINER_NAME="<nombre-del-contenedor>"

# Actualizar la imagen del contenedor
az containerapp update \
  --name ${CONTAINER_APP_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --image ${ACR_NAME}.azurecr.io/${ACR_IMAGE_NAME}:${ACR_TAG} \
  --container-name ${CONTAINER_NAME}
```

O si usas un archivo de configuración:
```bash
az containerapp update \
  --name ${CONTAINER_APP_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --yaml container-app-config.yaml
```

---

## Script completo para copiar y pegar

```bash
#!/bin/bash
set -e

# ============================================
# CONFIGURACIÓN - EDITA ESTOS VALORES
# ============================================
DOCKER_HUB_IMAGE="geragb/martin-fix-v2"
DOCKER_HUB_TAG="latest"
ACR_NAME="crtdpnortheu"
ACR_IMAGE_NAME="martin-fix-v2"
ACR_TAG="latest"

# Para actualizar Container App (opcional)
RESOURCE_GROUP="tu-resource-group"
CONTAINER_APP_NAME="tu-container-app"
CONTAINER_NAME="tu-contenedor"

# ============================================
# MIGRACIÓN
# ============================================

echo "📥 Paso 1: Descargando imagen desde Docker Hub..."
docker pull ${DOCKER_HUB_IMAGE}:${DOCKER_HUB_TAG}

echo "✅ Paso 2: Verificando imagen..."
docker images | grep ${ACR_IMAGE_NAME}

echo "🔐 Paso 3: Autenticando en Azure Container Registry..."
az acr login --name ${ACR_NAME}

echo "🏷️  Paso 4: Etiquetando imagen para ACR..."
docker tag ${DOCKER_HUB_IMAGE}:${DOCKER_HUB_TAG} ${ACR_NAME}.azurecr.io/${ACR_IMAGE_NAME}:${ACR_TAG}

echo "📤 Paso 5: Subiendo imagen a ACR..."
docker push ${ACR_NAME}.azurecr.io/${ACR_IMAGE_NAME}:${ACR_TAG}

echo "🔍 Paso 6: Verificando imagen en ACR..."
az acr repository show-tags --name ${ACR_NAME} --repository ${ACR_IMAGE_NAME} --output table

echo "✨ ¡Migración completada!"
echo ""
echo "Nueva imagen disponible en:"
echo "  ${ACR_NAME}.azurecr.io/${ACR_IMAGE_NAME}:${ACR_TAG}"
echo ""
echo "Para actualizar tu Container App, ejecuta:"
echo "  az containerapp update \\"
echo "    --name ${CONTAINER_APP_NAME} \\"
echo "    --resource-group ${RESOURCE_GROUP} \\"
echo "    --image ${ACR_NAME}.azurecr.io/${ACR_IMAGE_NAME}:${ACR_TAG}"
```

---

## Limpieza (Opcional)

Si quieres liberar espacio después de la migración:

```bash
# Eliminar la imagen local de Docker Hub
docker rmi ${DOCKER_HUB_IMAGE}:${DOCKER_HUB_TAG}

# Eliminar la imagen etiquetada para ACR
docker rmi ${ACR_NAME}.azurecr.io/${ACR_IMAGE_NAME}:${ACR_TAG}
```

---

## Plantilla para otras imágenes

Para migrar otras imágenes, copia el script y cambia estos valores:

```bash
# Ejemplo para otra imagen
DOCKER_HUB_IMAGE="usuario/otra-imagen"
DOCKER_HUB_TAG="v1.0"
ACR_NAME="crtdpnortheu"
ACR_IMAGE_NAME="otra-imagen"
ACR_TAG="v1.0"
```

---

## Troubleshooting

### Error: "unauthorized: authentication required"
- Verifica que estés autenticado: `az acr login --name ${ACR_NAME}`
- Verifica que tienes permisos en el ACR

### Error: "denied: requested access to the resource is denied"
- Verifica que el nombre del ACR es correcto
- Verifica que tu usuario tiene el rol `AcrPush` en el ACR

### Container App no actualiza la imagen
- Puede que necesites forzar una nueva revisión
- Verifica que la identidad del Container App tiene permisos `AcrPull` en el ACR

### Para habilitar ACR en tu Container App automáticamente:
```bash
az containerapp registry set \
  --name ${CONTAINER_APP_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --server ${ACR_NAME}.azurecr.io \
  --identity system
```

---

## Referencias

- [Azure Container Registry Documentation](https://docs.microsoft.com/en-us/azure/container-registry/)
- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Docker CLI Reference](https://docs.docker.com/engine/reference/commandline/cli/)
