# ==============================================================
# READY-TO-COPY-AND-PASTE CODE to add API Key to the Martin fork
# ==============================================================

## This file contains all the code needed
## to add an API Key to your Martin fork

---

## FILE 1: martin/src/srv/auth.rs (NEW - CREATE)

```rust
use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, body::{BoxBody, MessageBody},
    error::{self},
};
use futures::future::LocalBoxFuture;
use serde_json::json;
use std::future::{ready, Ready};
use tracing::{warn, debug};

/// Middleware to validate API Key on tile requests
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
    B: MessageBody + 'static,
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
    B: MessageBody + 'static,
{
    type Response = ServiceResponse<BoxBody>;
    type Error = Error;
    type Future = LocalBoxFuture<'static, Result<Self::Response, Self::Error>>;

    forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        // If auth is disabled, pass through
        if !self.enabled {
            let fut = self.service.call(req);
            return Box::pin(async move {
                fut.await.map(|res| res.map_into_boxed_body())
            });
        }

        // Only validate tile routes
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

        // Get API Key from header or query string
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

## FILE 2: Changes to martin/src/srv/server.rs

**STEP 1: Add import at the top of the file (after other imports)**

Find the line:
```rust
use crate::srv::admin::{Catalog, get_catalog};
```

And add after it:
```rust
use crate::srv::auth::ApiKeyMiddleware;
```

**STEP 2: Modify the `new_server` function**

In the `new_server` function, find this section (around line 222):

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

**REPLACE IT WITH:**

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

    // ===== NEW SECTION: API KEY MIDDLEWARE =====
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
    // ===========================================

    #[cfg(feature = "metrics")]
    let app = app.wrap(prometheus.clone());

    app.wrap(TracingLogger::default())
        .wrap(NormalizePath::new(TrailingSlash::MergeOnly))
        .configure(|c| router(c, &config))
};
```

---

## FILE 3: Changes to martin/src/srv/mod.rs

**ADD TWO LINES after the `admin` module block:**

The real format of this file uses `mod` + `pub use`, not `pub mod`. Find this block at the top:

```rust
mod admin;
pub use admin::Catalog;
#[cfg(feature = "unstable-schemas")]
pub use admin::{__path_get_catalog, get_catalog};
```

**ADD AFTER IT:**

```rust
mod auth;
pub use auth::ApiKeyMiddleware;
```

**EXPECTED RESULT:**

```rust
mod admin;
pub use admin::Catalog;
#[cfg(feature = "unstable-schemas")]
pub use admin::{__path_get_catalog, get_catalog};

mod auth;                              // ← NEW
pub use auth::ApiKeyMiddleware;        // ← NEW
```

---

## STEP 4: Exact place to fix compilation

Apply these edits directly in `martin/src/srv/auth.rs`.

### 4.1 Update import

Find:

```rust
Error, body::BoxBody,
```

Replace with:

```rust
Error, body::{BoxBody, MessageBody},
```

### 4.2 Update bound in `impl Transform`

Find:

```rust
B: 'static,
```

Replace with:

```rust
B: MessageBody + 'static,
```

### 4.3 Update bound in `impl Service`

Find:

```rust
B: 'static,
```

Replace with:

```rust
B: MessageBody + 'static,
```

---

### For Azure Container Instances:

In Azure Portal → Container Instances → your container → Settings → Configuration:

```
MARTIN_CONFIG = (the entire YAML here)
API_KEY = sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5ZjlkMjE0YzY4YWE...
AUTH_ENABLED = true
RUST_LOG = info,martin=debug
```

---

## COMPILATION

```bash
# From the root of the Martin fork
cd /path/to/martin

# Build with all features
cargo build --release --all-features

# Or specify features
cargo build --release \
  --features "pmtiles,mbtiles,postgres,tiles,fonts,sprites,styles"

# OR BETTER:
# RE-EXECUTE NOTEBOOK _fork-01-Custom Martin Docker Image Build with object_store support.ipynb
```
---

## TESTING

```bash
# Before compiling, check syntax
cargo check

# After compiling, run tests
cargo test

# Run with logs
RUST_LOG=debug ./target/release/martin --config config.yaml
```

---

## USAGE IN QGIS

### Option 1: With query parameter

```
URL: https://fmartin.azurewebsites.net/aqueduct40_baseline_annual_w_overall_water_risk_simpl_1_v3/{z}/{x}/{y}.pbf?key=sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5ZjlkMjE0YzY4YWE...
```

### Option 2: With header (if QGIS supports it)

```
URL: https://fmartin.azurewebsites.net/aqueduct40_baseline_annual_w_overall_water_risk_simpl_1_v3/{z}/{x}/{y}.pbf
Header X-API-Key: sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5ZjlkMjE0YzY4YWE...
```

---

## VERIFICATION

```bash
# Without API Key (should return 401)
curl https://fmartin.azurewebsites.net/aqueduct40_baseline_annual_w_overall_water_risk_simpl_1_v3/2/2/1.pbf
# Expected result: {"error":"Unauthorized","message":"Missing API key..."}

# With valid API Key (should return tile)
curl -H "X-API-Key: sk.eyJ1OiJmZm1hcnRpbiIsImEiOiJjbHM5ZjlkMjE0YzY4YWE..." \
     https://fmartin.azurewebsites.net/aqueduct40_baseline_annual_w_overall_water_risk_simpl_1_v3/2/2/1.pbf
# Expected result: [binary tile data]

# With invalid API Key (should return 403)
curl -H "X-API-Key: wrong-key" \
     https://fmartin.azurewebsites.net/aqueduct40_baseline_annual_w_overall_water_risk_simpl_1_v3/2/2/1.pbf
# Expected result: {"error":"Forbidden","message":"Invalid API key"}

# Health check without validation (should work without API Key)
curl https://fmartin.azurewebsites.net/health
# Expected result: OK
```

---

## EXPECTED LOGS

If you compile and run with `RUST_LOG=debug`:

```
[DEBUG] Valid API key provided for tile request
[DEBUG] get_tile called for source: aqueduct40...
[WARN] Invalid API key attempted for: /aqueduct40.../2/2/1.pbf
[WARN] Missing API key for tile request: /aqueduct40.../2/2/1.pbf
```

---

## TROUBLESHOOTING

### Compile error: "cannot find function `ApiKeyMiddleware`"

**Solution:** Verify you added both lines in `martin/src/srv/mod.rs`:

```rust
mod auth;
pub use auth::ApiKeyMiddleware;
```

### Error: "expected `impl Service` found `ApiKeyMiddleware`"

**Solution:** Make sure the `Transform` trait is correctly implemented (exact copy of the code above)

### Tiles do not require API Key

**Solution:** Verify that `AUTH_ENABLED=true` is set

### QGIS shows "Tile download failed"

**Solution:**
1. Verify the API Key is correct
2. Test with curl first
3. Check the server logs

---

## FILES TO MODIFY - SUMMARY

| File | Action | Lines |
|------|--------|-------|
| `martin/src/srv/auth.rs` | CREATE | New file |
| `martin/src/srv/mod.rs` | MODIFY | +2 lines (`mod auth;` + `pub use auth::ApiKeyMiddleware;`) |
| `martin/src/srv/server.rs` | MODIFY | +1 import + ~15 lines in factory |
| `Cargo.toml` | DO NOT CHANGE | Already has everything needed |
| `docker-compose.yml` or Azure | CONFIGURE | Environment variables |

---

## READY TO COMPILE?

1. Copy `auth.rs` exactly as shown above to `martin/src/srv/auth.rs`
2. Modify `mod.rs` and `server.rs` exactly as indicated
3. Run: `cargo build --release`
4. Configure environment variables
5. Done!


## LINUX KEY GENERAION

```bash
openssl rand -base64 32 | tr -d '\n' | tr '+/' '-_' | tr -d '='
```

