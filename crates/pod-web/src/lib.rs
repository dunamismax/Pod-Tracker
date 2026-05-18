#![recursion_limit = "256"]

pub mod server;
pub mod telemetry;
mod ui;

pub use server::{AppState, build_router};
