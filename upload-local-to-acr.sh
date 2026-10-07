#!/bin/bash
set -e

# ============================================
# Script: Subida Directa de Imagen Local -> Azure Container Registry
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
LOCAL_IMAGE="${LOCAL_IMAGE:-martin-custom-fix-inotify-tools}"
LOCAL_TAG="${LOCAL_TAG:-latest}"
ACR_NAME="${ACR_NAME:-crtdpnortheu}"
ACR_IMAGE_NAME="${ACR_IMAGE_NAME:-martin-custom-fix-inotify-tools}"
ACR_TAG="${ACR_TAG:-latest}"

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
echo "  Subida Directa: Local → Azure ACR"
echo "============================================"
echo ""
echo "Configuración:"
echo "  Imagen Local: ${LOCAL_IMAGE}:${LOCAL_TAG}"
echo "  Destino ACR: ${ACR_NAME}.azurecr.io/${ACR_IMAGE_NAME}:${ACR_TAG}"
echo ""

# Verificar comandos necesarios
print_step "Verificando herramientas necesarias..."
check_command docker
check_command az
print_success "Docker y Azure CLI están instalados"
echo ""

# ============================================
# PROCESO DE SUBIDA
# ============================================

# Paso 1: Verificar imagen local
print_step "Paso 1/5: Verificando imagen local..."
if docker images ${LOCAL_IMAGE} | grep -q ${LOCAL_TAG}; then
    echo ""
    docker images ${LOCAL_IMAGE}:${LOCAL_TAG}
    echo ""
    print_success "Imagen encontrada localmente"
else
    print_error "No se encontró la imagen ${LOCAL_IMAGE}:${LOCAL_TAG}"
    echo ""
    echo "Imágenes Docker disponibles:"
    docker images
    exit 1
fi
echo ""

# Paso 2: Autenticarse en Azure Container Registry
print_step "Paso 2/5: Autenticando en Azure Container Registry..."
if az acr login --name ${ACR_NAME}; then
    print_success "Autenticación exitosa en ACR"
else
    print_error "Error al autenticar en Azure Container Registry"
    echo ""
    print_warning "Asegúrate de:"
    echo "  1. Tener instalado Azure CLI"
    echo "  2. Haber iniciado sesión con 'az login'"
    echo "  3. Tener permisos en el ACR '${ACR_NAME}'"
    exit 1
fi
echo ""

# Paso 3: Etiquetar imagen con nombre de ACR
print_step "Paso 3/5: Etiquetando imagen para ACR..."
ACR_FULL_NAME="${ACR_NAME}.azurecr.io/${ACR_IMAGE_NAME}:${ACR_TAG}"
if docker tag ${LOCAL_IMAGE}:${LOCAL_TAG} ${ACR_FULL_NAME}; then
    print_success "Imagen etiquetada: ${ACR_FULL_NAME}"
else
    print_error "Error al etiquetar la imagen"
    exit 1
fi
echo ""

# Paso 4: Subir imagen a ACR
print_step "Paso 4/5: Subiendo imagen a Azure Container Registry..."
echo "⏳ Este proceso puede tardar varios minutos dependiendo del tamaño de la imagen..."
echo ""
if docker push ${ACR_FULL_NAME}; then
    echo ""
    print_success "Imagen subida exitosamente a ACR"
else
    print_error "Error al subir la imagen a ACR"
    exit 1
fi
echo ""

# Paso 5: Verificar imagen en ACR
print_step "Paso 5/5: Verificando imagen en ACR..."
echo ""
echo "Repositorios en ACR:"
az acr repository list --name ${ACR_NAME} --output table
echo ""
echo "Tags de la imagen ${ACR_IMAGE_NAME}:"
az acr repository show-tags --name ${ACR_NAME} --repository ${ACR_IMAGE_NAME} --output table
echo ""
print_success "Verificación completada"
echo ""

# ============================================
# RESUMEN FINAL
# ============================================

echo ""
echo "============================================"
echo "  ✅ SUBIDA COMPLETADA EXITOSAMENTE"
echo "============================================"
echo ""
echo "📦 Imagen disponible en:"
echo "   ${ACR_FULL_NAME}"
echo ""
echo "🔗 Para usar en Azure Container Apps:"
echo "   az containerapp update \\"
echo "     --name TU-CONTAINER-APP \\"
echo "     --resource-group TU-RESOURCE-GROUP \\"
echo "     --image ${ACR_FULL_NAME}"
echo ""
echo "🧹 Limpieza (opcional):"
echo "   Para eliminar tag local de ACR:"
echo "   docker rmi ${ACR_FULL_NAME}"
echo ""
