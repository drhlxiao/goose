pub use oi_kit_providers::canonical::catalog::{
    ModelCapabilities, ModelTemplate, ProviderCatalogEntry, ProviderFormat,
    ProviderSetupCapabilities, ProviderSetupCatalogEntry, ProviderSetupCategory,
    ProviderSetupField, ProviderSetupFieldOverride, ProviderSetupGroup, ProviderSetupMetadata,
    ProviderSetupMethod, ProviderTemplate,
};
use std::collections::HashSet;

pub async fn get_providers_by_format(format: ProviderFormat) -> Vec<ProviderCatalogEntry> {
    let native_provider_ids = super::providers()
        .await
        .into_iter()
        .map(|(metadata, _)| metadata.name)
        .collect::<HashSet<_>>();
    oi_kit_providers::canonical::catalog::get_providers_by_format(format, &native_provider_ids)
}

pub async fn get_setup_catalog_entries() -> Vec<ProviderSetupCatalogEntry> {
    oi_kit_providers::canonical::catalog::get_setup_catalog_entries(
        super::providers()
            .await
            .into_iter()
            .map(|(metadata, _)| metadata),
    )
}

pub fn get_provider_template(provider_id: &str) -> Option<ProviderTemplate> {
    oi_kit_providers::canonical::catalog::get_provider_template(provider_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn setup_catalog_keeps_goose_and_copilot() {
        let entries = get_setup_catalog_entries().await;
        assert!(entries.iter().any(|entry| entry.provider_id == "goose"));
        let copilot = entries
            .iter()
            .find(|entry| entry.provider_id == "github_copilot")
            .unwrap();
        assert_eq!(copilot.setup_method, ProviderSetupMethod::OauthDeviceCode);
        for removed in ["openai", "anthropic", "ollama", "claude-acp", "zai"] {
            assert!(!entries.iter().any(|entry| entry.provider_id == removed));
        }
    }
}
