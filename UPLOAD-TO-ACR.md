# Guía: Subir Imagen Local a Azure Container Registry (ACR)

Esta guía explica cómo subir la imagen Docker generada localmente (`martin-custom-fix-inotify-tools:latest`) directamente a Azure Container Registry sin pasar por Docker Hub.

---

## Prerrequisitos

1. **Azure CLI** instalado y configurado
   ```bash
   az login
   ```

2. **Permisos** en el Azure Container Registry de destino
   - Necesitas al menos el rol `AcrPush` o `Contributor`

3. **Imagen local** construida exitosamente
   - Verifica con: `docker images martin-custom-fix-inotify-tools`

---

## Opción 1: Usar el Script Automatizado (Recomendado)

El script `upload-local-to-acr.sh` automatiza todo el proceso:

### Uso Básico

```bash
# Dar permisos de ejecución
chmod +x upload-local-to-acr.sh

# Ejecutar con valores por defecto
./upload-local-to-acr.sh
```

### Personalizar Configuración

Puedes sobrescribir los valores por defecto usando variables de entorno:

```bash
# Ejemplo: cambiar el nombre de la imagen en ACR
ACR_IMAGE_NAME="martin-fork-custom" \
ACR_TAG="v1.0.0" \
./upload-local-to-acr.sh
```

### Variables Disponibles

| Variable | Valor por Defecto | Descripción |
|----------|-------------------|-------------|
| `LOCAL_IMAGE` | `martin-custom-fix-inotify-tools` | Nombre de la imagen local |
| `LOCAL_TAG` | `latest` | Tag de la imagen local |
| `ACR_NAME` | `crtdpnortheu` | Nombre del ACR |
| `ACR_IMAGE_NAME` | `martin-custom-fix-inotify-tools` | Nombre en ACR |
| `ACR_TAG` | `latest` | Tag en ACR |

---

## Opción 2: Paso a Paso Manual

Si prefieres ejecutar los comandos manualmente:

### 1. Verificar Imagen Local

```bash
docker images martin-custom-fix-inotify-tools
```

Deberías ver algo como:
```
REPOSITORY                          TAG      IMAGE ID       CREATED         SIZE
martin-custom-fix-inotify-tools    latest   abc123def456   5 minutes ago   250MB
```

### 2. Autenticar en Azure Container Registry

```bash
az acr login --name crtdpnortheu
```

Deberías ver: `Login Succeeded`

### 3. Etiquetar la Imagen para ACR

```bash
docker tag martin-custom-fix-inotify-tools:latest \
  crtdpnortheu.azurecr.io/martin-custom-fix-inotify-tools:latest
```

### 4. Subir la Imagen a ACR

```bash
docker push crtdpnortheu.azurecr.io/martin-custom-fix-inotify-tools:latest
```

Este proceso puede tardar varios minutos dependiendo del tamaño de la imagen y tu conexión.

### 5. Verificar que la Imagen Está en ACR

```bash
# Listar todos los repositorios
az acr repository list --name crtdpnortheu --output table

# Ver tags específicos de tu imagen
az acr repository show-tags \
  --name crtdpnortheu \
  --repository martin-custom-fix-inotify-tools \
  --output table
```

---

## Usar la Imagen desde ACR

### En Azure Container Apps

```bash
az containerapp update \
  --name tu-container-app \
  --resource-group tu-resource-group \
  --image crtdpnortheu.azurecr.io/martin-custom-fix-inotify-tools:latest
```

### En Docker Compose Local (testing)

```yaml
services:
  martin:
    image: crtdpnortheu.azurecr.io/martin-custom-fix-inotify-tools:latest
    ports:
      - "3000:3000"
```

Antes de hacer `docker-compose up`, autentícate:
```bash
az acr login --name crtdpnortheu
```

### En Kubernetes/AKS

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: martin-server
spec:
  template:
    spec:
      containers:
      - name: martin
        image: crtdpnortheu.azurecr.io/martin-custom-fix-inotify-tools:latest
        ports:
        - containerPort: 3000
```

---

## Gestión de Versiones

### Etiquetar con Versión Específica

```bash
# Etiquetar con versión
docker tag martin-custom-fix-inotify-tools:latest \
  crtdpnortheu.azurecr.io/martin-custom-fix-inotify-tools:v1.0.0

# Subir versión específica
docker push crtdpnortheu.azurecr.io/martin-custom-fix-inotify-tools:v1.0.0

# También mantener 'latest'
docker push crtdpnortheu.azurecr.io/martin-custom-fix-inotify-tools:latest
```

### Estrategia Recomendada de Tags

```bash
# Tag con fecha y hora
TAG="$(date +%Y%m%d-%H%M%S)"
docker tag martin-custom-fix-inotify-tools:latest \
  crtdpnortheu.azurecr.io/martin-custom-fix-inotify-tools:${TAG}

docker push crtdpnortheu.azurecr.io/martin-custom-fix-inotify-tools:${TAG}
```

---

## Troubleshooting

### Error: "authentication required"

```bash
# Renovar autenticación
az acr login --name crtdpnortheu
```

### Error: "unauthorized: authentication required"

Verifica que tienes permisos en el ACR:
```bash
az acr show --name crtdpnortheu --query loginServer
az role assignment list --scope /subscriptions/YOUR-SUB/resourceGroups/YOUR-RG/providers/Microsoft.ContainerRegistry/registries/crtdpnortheu
```

### Error: "denied: requested access to the resource is denied"

Solicita al administrador del ACR que te asigne el rol `AcrPush`:
```bash
az role assignment create \
  --assignee tu-email@dominio.com \
  --role AcrPush \
  --scope /subscriptions/YOUR-SUB/resourceGroups/YOUR-RG/providers/Microsoft.ContainerRegistry/registries/crtdpnortheu
```

### Ver Espacio Usado en ACR

```bash
az acr show-usage --name crtdpnortheu --output table
```

---

## Limpieza

### Eliminar Tag Local de ACR (opcional)

```bash
docker rmi crtdpnortheu.azurecr.io/martin-custom-fix-inotify-tools:latest
```

Esto solo elimina el tag local, **no afecta** la imagen en ACR.

### Eliminar Imagen del ACR

```bash
# Eliminar un tag específico
az acr repository delete \
  --name crtdpnortheu \
  --image martin-custom-fix-inotify-tools:latest

# Eliminar todo el repositorio
az acr repository delete \
  --name crtdpnortheu \
  --repository martin-custom-fix-inotify-tools
```

---

## Referencias

- [Azure Container Registry Documentation](https://docs.microsoft.com/azure/container-registry/)
- [Docker Push/Pull ACR](https://docs.microsoft.com/azure/container-registry/container-registry-get-started-docker-cli)
- [ACR Authentication](https://docs.microsoft.com/azure/container-registry/container-registry-authentication)
