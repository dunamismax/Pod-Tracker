use std::panic;

use tracing_subscriber::{EnvFilter, fmt, prelude::*};

const REDACTED_EMAIL: &str = "[REDACTED_EMAIL]";
const REDACTED_SECRET: &str = "[REDACTED_SECRET]";

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

pub fn redact_log_value(value: &str) -> String {
    let value = redact_postgres_password(value);
    let value = redact_named_value(&value, "pod_tracker_session=");
    let value = redact_named_value(&value, "pod_tracker_csrf=");
    let value = redact_named_value(&value, "invite_token=");
    let value = redact_named_value(&value, "token=");
    redact_email_tokens(&value)
}

fn redact_named_value(value: &str, name: &str) -> String {
    let mut output = String::with_capacity(value.len());
    let mut remainder = value;

    while let Some(index) = remainder.find(name) {
        let (before, after_before) = remainder.split_at(index);
        output.push_str(before);
        output.push_str(name);
        output.push_str(REDACTED_SECRET);

        let secret_start = name.len();
        let after_secret = after_before[secret_start..]
            .find(|character: char| character == ';' || character.is_ascii_whitespace())
            .map(|end| &after_before[secret_start + end..])
            .unwrap_or("");
        remainder = after_secret;
    }

    output.push_str(remainder);
    output
}

fn redact_postgres_password(value: &str) -> String {
    let Some(scheme_index) = value.find("postgres://") else {
        return value.to_owned();
    };
    let authority_start = scheme_index + "postgres://".len();
    let Some(authority_end) = value[authority_start..].find('@') else {
        return value.to_owned();
    };
    let authority = &value[authority_start..authority_start + authority_end];
    let Some(password_start) = authority.find(':') else {
        return value.to_owned();
    };

    format!(
        "{}{}{}",
        &value[..authority_start + password_start + 1],
        REDACTED_SECRET,
        &value[authority_start + authority_end..]
    )
}

fn redact_email_tokens(value: &str) -> String {
    value
        .split_inclusive(char::is_whitespace)
        .map(|token| {
            let trimmed = token.trim_end_matches(char::is_whitespace);
            let whitespace = &token[trimmed.len()..];
            let trimmed = trimmed
                .trim_matches(|character: char| character == ',' || character == ';')
                .to_owned();
            if looks_like_email(&trimmed) {
                format!("{REDACTED_EMAIL}{whitespace}")
            } else {
                token.to_owned()
            }
        })
        .collect()
}

fn looks_like_email(value: &str) -> bool {
    let Some((local, domain)) = value.split_once('@') else {
        return false;
    };

    !local.is_empty() && domain.contains('.') && !domain.starts_with('.') && !domain.ends_with('.')
}

#[cfg(test)]
mod tests {
    use super::{REDACTED_EMAIL, REDACTED_SECRET, redact_log_value};

    #[test]
    fn redacts_session_csrf_invite_tokens_and_email_addresses() {
        let value = "user player@example.test pod_tracker_session=abc123; pod_tracker_csrf=csrf123 invite_token=guest-token";
        let redacted = redact_log_value(value);

        assert!(!redacted.contains("player@example.test"));
        assert!(!redacted.contains("abc123"));
        assert!(!redacted.contains("csrf123"));
        assert!(!redacted.contains("guest-token"));
        assert!(redacted.contains(REDACTED_EMAIL));
        assert!(redacted.contains(REDACTED_SECRET));
    }

    #[test]
    fn redacts_postgres_url_passwords() {
        let value = "connect postgres://pod_tracker:private-password@localhost/pod_tracker";
        let redacted = redact_log_value(value);

        assert!(!redacted.contains("private-password"));
        assert!(redacted.contains("postgres://pod_tracker:[REDACTED_SECRET]@localhost"));
    }
}
