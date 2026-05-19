# =====================================================
# CÓDIGO LISTO PARA COPIAR Y PEGAR
# =====================================================

## Este archivo contiene todo el código necesario
## para agregar API Key a tu fork de Martin

---

## ARCHIVO 1: martin/src/srv/auth.rs (NUEVO - CREAR)

```rust
use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, body::BoxBody,
    error::{self},
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

        // Solo validar rutas de tiles
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
                Box::pin(async move {
                    let error_response = json!({
                        "error": "Forbidden",
                        "message": "Invalid API key"
                    });
                    Err(error::ErrorForbidden(error_response.to_string()))
                })
            }
            None => {
                warn!("Missing API key for tile request: {}", path);
                Box::pin(async move {
                    let error_response = json!({
                        "error": "Unauthorized",
                        "message": "Missing API key. Use X-API-Key header or ?key=YOUR_KEY"
                    });
                    Err(error::ErrorUnauthorized(error_response.to_string()))
                })
            }
        }
    }
}
```

---

## ARCHIVO 2: Modificaciones a martin/src/srv/server.rs

**PASO 1: Agregar import al inicio del archivo (después de otros imports)**

Busca la línea:
```rust
use crate::srv::admin::{Catalog, get_catalog};
```

Y agrega después:
```rust
use crate::srv::auth::ApiKeyMiddleware;
```

**PASO 2: Modificar la función `new_server`**

En la función `new_server`, busca esta sección (alrededor de línea 222):

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

    #[cfg(feature = "metrics")]
    let app = app.wrap(prometheus.clone());

    app.wrap(TracingLogger::default())
        .wrap(NormalizePath::new(TrailingSlash::MergeOnly))
        .configure(|c| router(c, &config))
};
```

**REEMPLÁZALO CON:**

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

    // ===== NUEVA SECCIÓN: API KEY MIDDLEWARE =====
    let api_key = std::env::var("API_KEY").ok();
    let auth_enabled = std::env::var("AUTH_ENABLED")
        .ok()
        .and_then(|v| v.parse::<bool>().ok())
        .unwrap_or(false);

    let app = if let (Some(key), true) = (api_key, auth_enabled) {
        app.wrap(ApiKeyMiddleware::new(key, true))
    } else {
        app.wrap(ApiKeyMiddleware::new(String::new(), false))
    };
    // =============================================

    #[cfg(feature = "metrics")]
    let app = app.wrap(prometheus.clone());

    app.wrap(TracingLogger::default())
        .wrap(NormalizePath::new(TrailingSlash::MergeOnly))
        .configure(|c| router(c, &config))
};
```

---

## ARCHIVO 3: Modificaciones a martin/src/srv/mod.rs

**AGREGAR UNA LÍNEA:**

Busca donde están los otros módulos (probablemente al inicio del archivo), ejemplo:

```rust
pub mod admin;
pub mod fonts;
pub mod sprites;
pub mod styles;
```

**AGREGA ESTA LÍNEA:**

```rust
pub mod auth;
```

**RESULTADO ESPERADO:**

```rust
pub mod admin;
pub mod auth;  // ← NUEVA
pub mod fonts;
pub mod sprites;
pub mod styles;
```

---

### Para Azure Container Instances:

En Azure Portal → Container Instances → tu contenedor → Settings → Configuration:

```
MARTIN_CONFIG = (el YAML entero aquí)
API_KEY = sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5ZjlkMjE0YzY4YWE...
AUTH_ENABLED = true
RUST_LOG = info,martin=debug
```

---

## COMPILACIÓN

```bash
# Desde la raíz del fork de Martin
cd /ruta/a/martin

# Compilar con todas las features
cargo build --release --all-features

# O especificar features
cargo build --release \
  --features "pmtiles,mbtiles,postgres,tiles,fonts,sprites,styles"
```

---

## TESTING

```bash
# Antes de compilar, testear cambios de sintaxis
cargo check

# Después de compilar, ejecutar tests
cargo test

# Ejecutar con logs
RUST_LOG=debug ./target/release/martin --config config.yaml
```

---

## USO EN QGIS

### Opción 1: Con query parameter

```
URL: https://fmartin.azurewebsites.net/aqueduct40_baseline_annual_w_overall_water_risk_simpl_1_v3/{z}/{x}/{y}.pbf?key=sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5ZjlkMjE0YzY4YWE...
```

### Opción 2: Con header (si QGIS lo soporta)

```
URL: https://fmartin.azurewebsites.net/aqueduct40_baseline_annual_w_overall_water_risk_simpl_1_v3/{z}/{x}/{y}.pbf
Header X-API-Key: sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5ZjlkMjE0YzY4YWE...
```

---

## VERIFICACIÓN

```bash
# Sin API Key (debe devolver 401)
curl https://fmartin.azurewebsites.net/aqueduct40_baseline_annual_w_overall_water_risk_simpl_1_v3/2/2/1.pbf
# Resultado esperado: {"error":"Unauthorized","message":"Missing API key..."}

# Con API Key válida (debe devolver tile)
curl -H "X-API-Key: sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5ZjlkMjE0YzY4YWE..." \
     https://fmartin.azurewebsites.net/aqueduct40_baseline_annual_w_overall_water_risk_simpl_1_v3/2/2/1.pbf
# Resultado esperado: [datos binarios del tile]

# Con API Key inválida (debe devolver 403)
curl -H "X-API-Key: wrong-key" \
     https://fmartin.azurewebsites.net/aqueduct40_baseline_annual_w_overall_water_risk_simpl_1_v3/2/2/1.pbf
# Resultado esperado: {"error":"Forbidden","message":"Invalid API key"}

# Health check sin validación (debe funcionar sin API Key)
curl https://fmartin.azurewebsites.net/health
# Resultado esperado: OK
```

---

## LOGS ESPERADOS

Si compilas y ejecutas con `RUST_LOG=debug`:

```
[DEBUG] Valid API key provided for tile request
[DEBUG] get_tile called for source: aqueduct40...
[WARN] Invalid API key attempted for: /aqueduct40.../2/2/1.pbf
[WARN] Missing API key for tile request: /aqueduct40.../2/2/1.pbf
```

---

## TROUBLESHOOTING

### Error al compilar: "cannot find function `ApiKeyMiddleware`"

**Solución:** Verifica que agregaste `pub mod auth;` en `martin/src/srv/mod.rs`

### Error: "expected `impl Service` found `ApiKeyMiddleware`"

**Solución:** Asegúrate que el trait `Transform` está implementado correctamente (copia exacta del código arriba)

### Las tiles no requieren API Key

**Solución:** Verifica que `AUTH_ENABLED=true` está configurado

### QGIS muestra "Tile download failed"

**Solución:** 
1. Verifica que el API Key es correcto
2. Prueba con curl primero
3. Revisa los logs del servidor

---

## ARCHIVOS A MODIFICAR - RESUMEN

| Archivo | Acción | Líneas |
|---------|--------|--------|
| `martin/src/srv/auth.rs` | CREAR | Nuevo archivo |
| `martin/src/srv/mod.rs` | MODIFICAR | +1 línea (`pub mod auth;`) |
| `martin/src/srv/server.rs` | MODIFICAR | +1 import + ~15 líneas en factory |
| `Cargo.toml` | NO CAMBIAR | Ya tiene lo necesario |
| `docker-compose.yml` o Azure | CONFIGURAR | Variables de entorno |

---

## ¿LISTO PARA COMPILAR?

1. Copia `auth.rs` tal cual está arriba a `martin/src/srv/auth.rs`
2. Modifica `mod.rs` y `server.rs` exactamente como se indica
3. Ejecuta: `cargo build --release`
4. Configura variables de entorno
5. ¡Listo! 🚀

