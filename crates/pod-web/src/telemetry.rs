use std::panic;

use tracing_subscriber::{EnvFilter, fmt, prelude::*};

pub fn init(environment: &str) {
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        EnvFilter::new("pod_web=info,pod_worker=info,pod_db=info,tower_http=info")
    });

    let fmt_layer = fmt::layer()
        .json()
        .with_target(true)
        .with_current_span(false)
        .with_span_list(false);

    let _ = tracing_subscriber::registry()
        .with(env_filter)
        .with(fmt_layer)
        .try_init();

    let environment = environment.to_owned();
    panic::set_hook(Box::new(move |panic_info| {
        let location = panic_info
            .location()
            .map(|location| format!("{}:{}", location.file(), location.line()))
            .unwrap_or_else(|| "unknown".to_owned());
        tracing::error!(%environment, %location, "panic");
    }));
}
