#!/bin/bash
set -e

# ============================================
# Script de Migración: Docker Hub -> Azure Container Registry
# ============================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# CONFIGURACIÓN - EDITA ESTOS VALORES
# ============================================
DOCKER_HUB_IMAGE="${DOCKER_HUB_IMAGE:-geragb/martin-fix-v2}"
DOCKER_HUB_TAG="${DOCKER_HUB_TAG:-latest}"
ACR_NAME="${ACR_NAME:-crtdpnortheu}"
ACR_IMAGE_NAME="${ACR_IMAGE_NAME:-martin-fix-v2}"
ACR_TAG="${ACR_TAG:-latest}"

# Para actualizar Container App (opcional - comentar si no se necesita)
# RESOURCE_GROUP="tu-resource-group"
# CONTAINER_APP_NAME="tu-container-app"

# ============================================
# FUNCIONES
# ============================================

print_step() {
    echo -e "${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "El comando '$1' no está instalado"
        exit 1
    fi
}

# ============================================
# VALIDACIONES PREVIAS
# ============================================

echo ""
echo "============================================"
echo "  Migración Docker Hub → Azure ACR"
echo "============================================"
echo ""
echo "Configuración:"
echo "  Origen: ${DOCKER_HUB_IMAGE}:${DOCKER_HUB_TAG}"
echo "  Destino: ${ACR_NAME}.azurecr.io/${ACR_IMAGE_NAME}:${ACR_TAG}"
echo ""

# Verificar comandos necesarios
print_step "Verificando herramientas necesarias..."
check_command docker
check_command az
print_success "Docker y Azure CLI están instalados"
echo ""

# ============================================
# MIGRACIÓN
# ============================================

# Paso 1: Pull desde Docker Hub
print_step "Paso 1/6: Descargando imagen desde Docker Hub..."
if docker pull ${DOCKER_HUB_IMAGE}:${DOCKER_HUB_TAG}; then
    print_success "Imagen descargada correctamente"
else
    print_error "Error al descargar la imagen de Docker Hub"
    exit 1
fi
echo ""

# Paso 2: Verificar imagen
print_step "Paso 2/6: Verificando imagen local..."
if docker images ${DOCKER_HUB_IMAGE} | grep -q ${DOCKER_HUB_TAG}; then
    docker images ${DOCKER_HUB_IMAGE}:${DOCKER_HUB_TAG}
    print_success "Imagen verificada"
else
    print_error "No se encontró la imagen localmente"
    exit 1
fi
echo ""

# Paso 3: Login a ACR
print_step "Paso 3/6: Autenticando en Azure Container Registry..."
if az acr login --name ${ACR_NAME}; then
    print_success "Autenticación exitosa en ACR"
else
    print_error "Error al autenticar en ACR"
    print_warning "Verifica que tienes permisos y que el nombre del ACR es correcto"
    exit 1
fi
echo ""

# Paso 4: Tag imagen
print_step "Paso 4/6: Etiquetando imagen para ACR..."
TARGET_IMAGE="${ACR_NAME}.azurecr.io/${ACR_IMAGE_NAME}:${ACR_TAG}"
if docker tag ${DOCKER_HUB_IMAGE}:${DOCKER_HUB_TAG} ${TARGET_IMAGE}; then
    print_success "Imagen etiquetada: ${TARGET_IMAGE}"
else
    print_error "Error al etiquetar la imagen"
    exit 1
fi
echo ""

# Paso 5: Push a ACR
print_step "Paso 5/6: Subiendo imagen a Azure Container Registry..."
if docker push ${TARGET_IMAGE}; then
    print_success "Imagen subida correctamente a ACR"
else
    print_error "Error al subir la imagen a ACR"
    exit 1
fi
echo ""

# Paso 6: Verificar en ACR
print_step "Paso 6/6: Verificando imagen en ACR..."
if az acr repository show --name ${ACR_NAME} --repository ${ACR_IMAGE_NAME} &> /dev/null; then
    az acr repository show-tags --name ${ACR_NAME} --repository ${ACR_IMAGE_NAME} --output table
    print_success "Imagen verificada en ACR"
else
    print_error "No se pudo verificar la imagen en ACR"
    exit 1
fi
echo ""

# ============================================
# RESUMEN
# ============================================

echo "============================================"
echo -e "${GREEN}✨ ¡Migración completada exitosamente!${NC}"
echo "============================================"
echo ""
echo "Imagen disponible en:"
echo "  ${TARGET_IMAGE}"
echo ""

# Si hay configuración de Container App
if [ ! -z "${RESOURCE_GROUP}" ] && [ ! -z "${CONTAINER_APP_NAME}" ]; then
    echo "Para actualizar tu Container App, ejecuta:"
    echo ""
    echo "  az containerapp update \\"
    echo "    --name ${CONTAINER_APP_NAME} \\"
    echo "    --resource-group ${RESOURCE_GROUP} \\"
    echo "    --image ${TARGET_IMAGE}"
    echo ""
else
    print_warning "Para actualizar tu Container App, configura RESOURCE_GROUP y CONTAINER_APP_NAME"
    echo ""
fi

# ============================================
# LIMPIEZA OPCIONAL
# ============================================

read -p "¿Deseas eliminar las imágenes locales para liberar espacio? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_step "Eliminando imágenes locales..."
    docker rmi ${DOCKER_HUB_IMAGE}:${DOCKER_HUB_TAG} 2>/dev/null || true
    docker rmi ${TARGET_IMAGE} 2>/dev/null || true
    print_success "Imágenes locales eliminadas"
else
    print_warning "Imágenes locales conservadas"
fi

echo ""
echo "¡Listo! 🎉"
