use std::sync::{Arc, RwLock};

use super::{
    base::{Provider, ProviderMetadata, ProviderType},
    githubcopilot::GithubCopilotProvider,
    provider_registry::{ProviderEntry, ProviderRegistry},
};
use crate::config::{declarative_providers::register_declarative_providers, ExtensionConfig};
use anyhow::Result;
use tokio::sync::OnceCell;

static REGISTRY: OnceCell<RwLock<ProviderRegistry>> = OnceCell::const_new();

async fn init_registry() -> RwLock<ProviderRegistry> {
    let tls_config =
        crate::config::tls::provider_tls_config_from_config(crate::config::Config::global())
            .expect("failed to load provider TLS config");
    let mut registry = ProviderRegistry::new(tls_config);
    registry.register_with_inventory::<GithubCopilotProvider>(
        true,
        Some(super::inventory::registrations::refresh_only()),
    );
    registry.set_cleanup(
        "github_copilot",
        Arc::new(|| Box::pin(GithubCopilotProvider::cleanup())),
    );
    if let Err(e) = register_declarative_providers(&mut registry) {
        tracing::warn!("Failed to load custom providers: {}", e);
    }
    RwLock::new(registry)
}

async fn get_registry() -> &'static RwLock<ProviderRegistry> {
    REGISTRY.get_or_init(init_registry).await
}

pub async fn providers() -> Vec<(ProviderMetadata, ProviderType)> {
    get_registry()
        .await
        .read()
        .unwrap()
        .all_metadata_with_types()
}

/// Providers that may be shown to users, honouring the operator allowlist.
pub async fn listable_providers() -> Vec<(ProviderMetadata, ProviderType)> {
    providers()
        .await
        .into_iter()
        .filter(|(metadata, _)| super::allowlist::is_provider_allowed(&metadata.name))
        .collect()
}

pub async fn refresh_custom_providers() -> Result<()> {
    let registry = get_registry().await;
    let mut registry = registry.write().unwrap();
    registry.remove_custom_providers();
    register_declarative_providers(&mut registry)?;
    Ok(())
}

pub async fn get_from_registry(name: &str) -> Result<ProviderEntry> {
    get_registry()
        .await
        .read()
        .unwrap()
        .entries
        .get(name)
        .ok_or_else(|| anyhow::anyhow!("Unknown provider: {}", name))
        .cloned()
}

pub async fn inventory_identity(name: &str) -> Result<super::inventory::InventoryIdentityInput> {
    get_from_registry(name).await?.inventory_identity()
}

pub async fn create(name: &str, extensions: Vec<ExtensionConfig>) -> Result<Arc<dyn Provider>> {
    get_from_registry(name).await?.create(extensions).await
}

pub async fn create_with_default_model(
    name: impl AsRef<str>,
    extensions: Vec<ExtensionConfig>,
) -> Result<Arc<dyn Provider>> {
    get_from_registry(name.as_ref())
        .await?
        .create_with_default_model(extensions)
        .await
}

pub async fn cleanup_provider(name: &str) -> Result<()> {
    let cleanup = get_registry()
        .await
        .read()
        .unwrap()
        .entries
        .get(name)
        .and_then(|entry| entry.cleanup.clone());
    if let Some(cleanup) = cleanup {
        cleanup().await?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn only_copilot_is_registered_as_a_builtin() {
        let builtins: Vec<_> = providers()
            .await
            .into_iter()
            .filter(|(_, kind)| matches!(kind, ProviderType::Builtin | ProviderType::Preferred))
            .map(|(metadata, _)| metadata.name)
            .collect();
        assert_eq!(builtins, ["github_copilot"]);
        assert!(get_from_registry("github_copilot")
            .await
            .unwrap()
            .supports_inventory_refresh());
        assert!(get_from_registry("openai").await.is_err());
        assert!(get_from_registry("anthropic").await.is_err());
    }
}
