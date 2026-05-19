# =====================================================
# AGREGAR API KEY A MARTIN FORK (ACTIX-WEB)
# =====================================================

## Martin usa Actix-Web, no Axum.
## Solución para tu fork específico.

---

## PASO 1: Ver el archivo actual de content.rs

El archivo clave está en: `martin/src/srv/tiles/content.rs`

Contiene la función `get_tile` que procesa las peticiones de tiles.

---

## PASO 2: Crear módulo de autenticación

**Archivo: `martin/src/srv/auth.rs` (NUEVO)**

```rust
use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage, body::BoxBody,
    error::{self, ErrorUnauthorized, ErrorForbidden},
    http::StatusCode,
};
use futures::future::LocalBoxFuture;
use serde_json::json;
use std::future::{ready, Ready};
use tracing::{warn, debug};

/// Middleware para validar API Key en requests de tiles
pub struct ApiKeyMiddleware {
    api_key: String,
    enabled: bool,
}

impl ApiKeyMiddleware {
    pub fn new(api_key: String, enabled: bool) -> Self {
        Self { api_key, enabled }
    }
}

impl<S, B> Transform<S, ServiceRequest> for ApiKeyMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<BoxBody>;
    type Error = Error;
    type Transform = ApiKeyMiddlewareService<S>;
    type InitError = ();
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(ApiKeyMiddlewareService {
            service,
            api_key: self.api_key.clone(),
            enabled: self.enabled,
        }))
    }
}

pub struct ApiKeyMiddlewareService<S> {
    service: S,
    api_key: String,
    enabled: bool,
}

impl<S, B> Service<ServiceRequest> for ApiKeyMiddlewareService<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<BoxBody>;
    type Error = Error;
    type Future = LocalBoxFuture<'static, Result<Self::Response, Self::Error>>;

    forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        // Si auth está deshabilitado, pasar directo
        if !self.enabled {
            let fut = self.service.call(req);
            return Box::pin(async move {
                fut.await.map(|res| res.map_into_boxed_body())
            });
        }

        // Solo validar rutas de tiles (que contienen formato {source}/{z}/{x}/{y})
        let path = req.path();
        let is_tile_request = path.contains('/') && 
                             !path.starts_with("/catalog") && 
                             !path.starts_with("/health") &&
                             !path.starts_with("/_/");

        if !is_tile_request {
            let fut = self.service.call(req);
            return Box::pin(async move {
                fut.await.map(|res| res.map_into_boxed_body())
            });
        }

        // Obtener API Key del header o query string
        let api_key_from_header = req
            .headers()
            .get("x-api-key")
            .and_then(|h| h.to_str().ok())
            .map(|s| s.to_string());

        let api_key_from_query = req
            .query_string()
            .split('&')
            .find_map(|param| {
                if let Some(value) = param.strip_prefix("key=") {
                    Some(value.to_string())
                } else {
                    None
                }
            });

        let provided_key = api_key_from_header.or(api_key_from_query);

        match provided_key {
            Some(key) if key == self.api_key => {
                debug!("Valid API key provided for tile request");
                let fut = self.service.call(req);
                Box::pin(async move {
                    fut.await.map(|res| res.map_into_boxed_body())
                })
            }
            Some(_) => {
                warn!("Invalid API key attempted for: {}", path);
                let error_response = json!({
                    "error": "Forbidden",
                    "message": "Invalid API key"
                });
                Box::pin(async move {
                    Err(error::ErrorForbidden(error_response.to_string()))
                })
            }
            None => {
                warn!("Missing API key for tile request: {}", path);
                let error_response = json!({
                    "error": "Unauthorized",
                    "message": "Missing API key. Use X-API-Key header or ?key=YOUR_KEY"
                });
                Box::pin(async move {
                    Err(error::ErrorUnauthorized(error_response.to_string()))
                })
            }
        }
    }
}

/// Extractor para API Key (alternativa más limpia)
pub struct ValidatedApiKey {
    pub key: String,
}

impl ValidatedApiKey {
    pub fn from_request(req: &actix_web::HttpRequest, expected_key: &str) -> Result<Self, Error> {
        // Obtener del header
        if let Some(header_value) = req.headers().get("x-api-key") {
            if let Ok(key) = header_value.to_str() {
                if key == expected_key {
                    return Ok(ValidatedApiKey {
                        key: key.to_string(),
                    });
                } else {
                    return Err(ErrorForbidden("Invalid API key"));
                }
            }
        }

        // Obtener del query string
        if let Some(query) = req.query_string().split('&').find(|p| p.starts_with("key=")) {
            if let Some(key) = query.strip_prefix("key=") {
                if key == expected_key {
                    return Ok(ValidatedApiKey {
                        key: key.to_string(),
                    });
                } else {
                    return Err(ErrorForbidden("Invalid API key"));
                }
            }
        }

        Err(ErrorUnauthorized("Missing API key"))
    }
}
```

---

## PASO 3: Integrar el middleware en server.rs

**Modificar: `martin/src/srv/server.rs`**

Agregar al inicio del archivo:

```rust
mod auth;
use crate::srv::auth::ApiKeyMiddleware;
```

Luego, en la función `new_server`, cambiar la sección donde se crea el factory:

**ORIGINAL (líneas 222-256):**
```rust
let factory = move || {
    let cors_middleware = cors_config.make_cors_middleware();

    let app = App::new()
        .app_data(Data::new(catalog.clone()))
        .app_data(Data::new(config.clone()));

    #[cfg(feature = "_tiles")]
    let app = app.app_data(Data::new(state.tile_manager.clone()));
    
    // ... más código ...

    let app = app.wrap(middleware::Condition::new(
        cors_middleware.is_some(),
        cors_middleware.unwrap_or_default(),
    ));

    #[cfg(feature = "metrics")]
    let app = app.wrap(prometheus.clone());

    app.wrap(TracingLogger::default())
        .wrap(NormalizePath::new(TrailingSlash::MergeOnly))
        .configure(|c| router(c, &config))
};
```

**NUEVO:**
```rust
let factory = move || {
    let cors_middleware = cors_config.make_cors_middleware();

    let app = App::new()
        .app_data(Data::new(catalog.clone()))
        .app_data(Data::new(config.clone()));

    #[cfg(feature = "_tiles")]
    let app = app.app_data(Data::new(state.tile_manager.clone()));

    #[cfg(feature = "sprites")]
    let app = app
        .app_data(Data::new(state.sprites.clone()))
        .app_data(Data::new(state.sprite_cache.clone()));

    #[cfg(feature = "fonts")]
    let app = app
        .app_data(Data::new(state.fonts.clone()))
        .app_data(Data::new(state.font_cache.clone()));

    #[cfg(feature = "styles")]
    let app = app.app_data(Data::new(state.styles.clone()));

    let app = app.wrap(middleware::Condition::new(
        cors_middleware.is_some(),
        cors_middleware.unwrap_or_default(),
    ));

    // ===== AGREGAR: API Key Middleware =====
    let api_key = std::env::var("API_KEY").ok();
    let auth_enabled = std::env::var("AUTH_ENABLED")
        .ok()
        .and_then(|v| v.parse::<bool>().ok())
        .unwrap_or(false);

    let app = if let (Some(api_key), true) = (api_key.clone(), auth_enabled) {
        app.wrap(ApiKeyMiddleware::new(api_key, true))
    } else {
        app.wrap(ApiKeyMiddleware::new("".to_string(), false))
    };
    // ======================================

    #[cfg(feature = "metrics")]
    let app = app.wrap(prometheus.clone());

    app.wrap(TracingLogger::default())
        .wrap(NormalizePath::new(TrailingSlash::MergeOnly))
        .configure(|c| router(c, &config))
};
```

---

## PASO 4: Actualizar Cargo.toml

Asegúrate de tener estas dependencias en `martin/Cargo.toml`:

```toml
[dependencies]
actix-web = "4"
tokio = { version = "1", features = ["full"] }
serde_json = "1"
tracing = "0.1"
futures = "0.3"
serde = { version = "1", features = ["derive"] }
```

---

## PASO 5: Modificar mod.rs del servidor

**Archivo: `martin/src/srv/mod.rs`**

Agregar:

```rust
pub mod auth;
```

---

## PASO 6: Variables de entorno

En tu Docker, Azure Container Instances, o donde ejecutes Martin:

```
API_KEY=sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5...
AUTH_ENABLED=true
RUST_LOG=info,martin=debug
```

---

## PASO 7: Compilar

```bash
cd /ruta/a/martin

# Compilar con todas las features
cargo build --release --all-features

# O compilar solo lo necesario
cargo build --release \
  --features "pmtiles,mbtiles,postgres,tiles,fonts,sprites,styles"
```

---

## PASO 8: Probar

```bash
# Con API Key válida
curl -H "X-API-Key: sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5..." \
  http://localhost:3000/aqueduct40_baseline_annual_w_overall_water_risk_simpl_1_v3/2/2/1.pbf

# O con query string
curl http://localhost:3000/aqueduct40_baseline_annual_w_overall_water_risk_simpl_1_v3/2/2/1.pbf?key=sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5...

# Sin API Key (debe fallar con 401)
curl http://localhost:3000/aqueduct40_baseline_annual_w_overall_water_risk_simpl_1_v3/2/2/1.pbf

# Health check sin validación
curl http://localhost:3000/health
```

---

## PASO 9: En Azure Container Instances

Cuando despliegues el contenedor:

**docker-compose.yml:**
```yaml
version: '3.8'
services:
  martin:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      - API_KEY=sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5...
      - AUTH_ENABLED=true
      - RUST_LOG=info,martin=debug
      - MARTIN_CONFIG=/tmp/martin-config.yaml
    volumes:
      - ./data:/mnt/mbtiles
```

O directamente en Azure:
```
Configuration → Application Settings:

API_KEY = sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5...
AUTH_ENABLED = true
RUST_LOG = info,martin=debug
MARTIN_CONFIG = /tmp/martin-config.yaml
```

---

## PASO 10: En QGIS

Para acceder a los tiles desde QGIS con API Key:

**Layer → Add Layer → Add XYZ Tile Layer**

```
Name:           Aqueduct Risk
URL:            https://fmartin.azurewebsites.net/{source}/{z}/{x}/{y}.pbf?key=sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5...
Min Zoom:       0
Max Zoom:       20
```

O con header personalizado (si QGIS lo soporta):
```
URL:            https://fmartin.azurewebsites.net/{source}/{z}/{x}/{y}.pbf
Headers:        X-API-Key: sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5...
```

---

## COSAS IMPORTANTES

⚠️ **DIFERENCIAS CON AXUM:**

Martin usa **Actix-Web**, no Axum. Las diferencias principales:

- ✅ Middleware en Actix-Web es más complejo pero más poderoso
- ✅ No hay extractores directo, usamos `req.headers()` y `req.query_string()`
- ✅ Actix usa `Transform` + `Service` traits en lugar de funciones simples
- ✅ El error handling es diferente

La solución anterior está específicamente diseñada para Actix-Web.

---

## FLUJO DE LA SOLUCIÓN

```
Request → ApiKeyMiddleware
           ├─ ¿Es tile request?
           │   └─ Sí: Validar API Key
           │       ├─ Header X-API-Key?
           │       ├─ Query param ?key=?
           │       └─ Si no → 401 Unauthorized
           │       └─ Si inválido → 403 Forbidden
           │       └─ Si válido → Continuar
           └─ No: Pasar directo (health, catalog, etc.)
         
         ↓
         
    Handler original (get_tile, etc.)
         
         ↓
         
    Response
```

---

## ALTERNATIVA: Rate Limiting Adicional

Si también quieres agregar rate limiting por API Key:

```rust
use governor::RateLimiter;
use governor::state::{InMemoryState, NotKeyed};

pub struct RateLimitMiddleware {
    limiters: std::sync::Arc<std::sync::Mutex<std::collections::HashMap<String, RateLimiter<NotKeyed, InMemoryState>>>>,
    requests_per_second: u32,
}

impl RateLimitMiddleware {
    pub fn new(requests_per_second: u32) -> Self {
        Self {
            limiters: std::sync::Arc::new(std::sync::Mutex::new(std::collections::HashMap::new())),
            requests_per_second,
        }
    }
}

// Implementar Transform para rate limiting...
// (más complejo, por ahora la solución de API Key es suficiente)
```

---

## MONITOREO Y LOGS

Para ver los logs de validación de API Key:

```bash
# En desarrollo
RUST_LOG=debug cargo run

# En Docker
docker run -e RUST_LOG=debug your-image

# En Azure
Configuration → Application Settings → RUST_LOG=debug
```

Los logs mostrarán:
```
[DEBUG] Valid API key provided for tile request
[WARN] Invalid API key attempted for: /source/2/2/1.pbf
[WARN] Missing API key for tile request: /source/2/2/1.pbf
```

---

## CHECKLIST FINAL

- [ ] Crear archivo `martin/src/srv/auth.rs`
- [ ] Modificar `martin/src/srv/server.rs` con middleware
- [ ] Agregar módulo en `martin/src/srv/mod.rs`
- [ ] Verificar dependencias en Cargo.toml
- [ ] Compilar: `cargo build --release`
- [ ] Probar localmente sin AUTH_ENABLED
- [ ] Probar con AUTH_ENABLED=true
- [ ] Probar con QGIS
- [ ] Desplegar en Azure
- [ ] Verificar logs en Azure

---

**¿Necesitas ayuda con algo específico de la compilación o implementación?** 🚀

