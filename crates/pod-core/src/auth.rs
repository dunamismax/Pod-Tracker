use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::{Algorithm, Argon2, Params, Version};
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use rand_core::{OsRng, RngCore};
use sha2::{Digest, Sha256};
use thiserror::Error;

pub const MINIMUM_PASSWORD_LENGTH: usize = 12;
pub const SESSION_COOKIE_NAME: &str = "pod_tracker_session";
pub const SESSION_TOKEN_BYTES: usize = 32;
pub const SESSION_TOKEN_HASH_BYTES: usize = 32;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionToken {
    pub encoded: String,
    pub hash: [u8; SESSION_TOKEN_HASH_BYTES],
}

#[derive(Debug, Error)]
pub enum AuthError {
    #[error("password must be at least {MINIMUM_PASSWORD_LENGTH} characters")]
    PasswordTooShort,
    #[error("password hash failed")]
    PasswordHash,
    #[error("session token is invalid")]
    InvalidSessionToken,
}

pub fn hash_password(password: &str) -> Result<String, AuthError> {
    if password.len() < MINIMUM_PASSWORD_LENGTH {
        return Err(AuthError::PasswordTooShort);
    }

    let salt = SaltString::generate(&mut OsRng);
    let hash = password_hasher()
        .hash_password(password.as_bytes(), &salt)
        .map_err(|_| AuthError::PasswordHash)?;

    Ok(hash.to_string())
}

pub fn verify_password(hash: &str, password: &str) -> bool {
    if hash.is_empty() || password.is_empty() {
        return false;
    }

    let Ok(parsed_hash) = PasswordHash::new(hash) else {
        return false;
    };

    password_hasher()
        .verify_password(password.as_bytes(), &parsed_hash)
        .is_ok()
}

pub fn new_session_token() -> SessionToken {
    let mut token = [0_u8; SESSION_TOKEN_BYTES];
    OsRng.fill_bytes(&mut token);
    let encoded = URL_SAFE_NO_PAD.encode(token);
    let hash = hash_session_token_bytes(&token);

    SessionToken { encoded, hash }
}

pub fn hash_session_token(encoded: &str) -> Result<[u8; SESSION_TOKEN_HASH_BYTES], AuthError> {
    let token = URL_SAFE_NO_PAD
        .decode(encoded)
        .map_err(|_| AuthError::InvalidSessionToken)?;

    if token.len() != SESSION_TOKEN_BYTES {
        return Err(AuthError::InvalidSessionToken);
    }

    Ok(hash_session_token_bytes(&token))
}

fn hash_session_token_bytes(token: &[u8]) -> [u8; SESSION_TOKEN_HASH_BYTES] {
    Sha256::digest(token).into()
}

fn password_hasher() -> Argon2<'static> {
    let params = Params::new(19_456, 2, 1, None).expect("valid Argon2id params");
    Argon2::new(Algorithm::Argon2id, Version::V0x13, params)
}

#[cfg(test)]
mod tests {
    use super::{
        AuthError, MINIMUM_PASSWORD_LENGTH, hash_password, hash_session_token, new_session_token,
        verify_password,
    };

    #[test]
    fn hashes_and_verifies_argon2id_passwords() {
        let password = "correct horse battery staple";
        let hash = hash_password(password).expect("hash password");

        assert!(hash.starts_with("$argon2id$"));
        assert!(verify_password(&hash, password));
        assert!(!verify_password(&hash, "wrong password"));
    }

    #[test]
    fn rejects_short_passwords() {
        let err = hash_password(&"x".repeat(MINIMUM_PASSWORD_LENGTH - 1))
            .expect_err("short password should fail");

        assert!(matches!(err, AuthError::PasswordTooShort));
    }

    #[test]
    fn creates_and_hashes_session_tokens() {
        let token = new_session_token();

        assert!(!token.encoded.is_empty());
        assert_eq!(
            hash_session_token(&token.encoded).expect("hash session token"),
            token.hash
        );
        assert!(hash_session_token("not a session token").is_err());
    }
}
