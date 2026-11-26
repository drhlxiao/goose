use super::{default_inventory_identity_resolver, InventoryRegistration};

pub fn refresh_only() -> InventoryRegistration {
    InventoryRegistration {
        supports_refresh: true,
        identity: default_inventory_identity_resolver(),
        configured: None,
    }
}
