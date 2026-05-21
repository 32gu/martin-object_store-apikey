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
