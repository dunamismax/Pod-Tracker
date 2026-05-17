use serde::Serialize;

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum HealthStatus {
    Ok,
    Ready,
    NotReady,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct HealthResponse {
    pub status: HealthStatus,
}

impl HealthResponse {
    pub fn ok() -> Self {
        Self {
            status: HealthStatus::Ok,
        }
    }

    pub fn ready() -> Self {
        Self {
            status: HealthStatus::Ready,
        }
    }
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct ReadinessFailure {
    pub status: HealthStatus,
    pub check: &'static str,
}

impl ReadinessFailure {
    pub fn not_ready(check: &'static str) -> Self {
        Self {
            status: HealthStatus::NotReady,
            check,
        }
    }
}
