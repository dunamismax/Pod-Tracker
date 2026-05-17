use std::env;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppConfig {
    pub addr: String,
    pub database_url: Option<String>,
    pub environment: String,
    pub static_dir: String,
    pub smtp2go_api_key: Option<String>,
    pub smtp_sender: String,
}

impl AppConfig {
    pub fn from_env() -> Self {
        Self {
            addr: env_with_default("POD_TRACKER_ADDR", ":8080"),
            database_url: non_empty_env("POD_TRACKER_DATABASE_URL"),
            environment: env_with_default("POD_TRACKER_ENV", "development"),
            static_dir: env_with_default("POD_TRACKER_STATIC_DIR", "crates/pod-web/assets"),
            smtp2go_api_key: non_empty_env("POD_TRACKER_SMTP2GO_API_KEY"),
            smtp_sender: env_with_default("POD_TRACKER_SMTP_SENDER", "pod-tracker@pod-tracker.app"),
        }
    }

    pub fn bind_addr(&self) -> String {
        if self.addr.starts_with(':') {
            format!("0.0.0.0{}", self.addr)
        } else {
            self.addr.clone()
        }
    }

    pub fn database_configured(&self) -> bool {
        self.database_url.is_some()
    }

    pub fn smtp_configured(&self) -> bool {
        self.smtp2go_api_key.is_some() && !self.smtp_sender.is_empty()
    }
}

fn env_with_default(key: &str, fallback: &str) -> String {
    env::var(key)
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| fallback.to_owned())
}

fn non_empty_env(key: &str) -> Option<String> {
    env::var(key).ok().filter(|value| !value.trim().is_empty())
}

#[cfg(test)]
mod tests {
    use super::AppConfig;

    #[test]
    fn colon_prefixed_addresses_bind_on_all_interfaces() {
        let cfg = AppConfig {
            addr: ":8080".to_owned(),
            database_url: None,
            environment: "test".to_owned(),
            static_dir: "assets".to_owned(),
            smtp2go_api_key: None,
            smtp_sender: "pod-tracker@example.test".to_owned(),
        };

        assert_eq!(cfg.bind_addr(), "0.0.0.0:8080");
    }

    #[test]
    fn explicit_host_addresses_are_preserved() {
        let cfg = AppConfig {
            addr: "127.0.0.1:8081".to_owned(),
            database_url: None,
            environment: "test".to_owned(),
            static_dir: "assets".to_owned(),
            smtp2go_api_key: None,
            smtp_sender: "pod-tracker@example.test".to_owned(),
        };

        assert_eq!(cfg.bind_addr(), "127.0.0.1:8081");
    }
}
