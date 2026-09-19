//! Solarized Dark syntax preview for Rust.
//! Demonstrates attributes, lifetimes, generics, macros, and pattern matching.

use std::collections::HashMap;
use std::fmt::{self, Display, Formatter};
use std::time::Duration;

const MAX_CONNECTIONS: usize = 128;
const BUFFER_CAPACITY: u32 = 0xCAFE_BABE;

/// Node operational status enumeration.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NodeStatus {
    Starting,
    Running(u16),
    Degraded { latency_ms: u64 },
    Terminated,
}

/// Generic container abstraction.
pub trait Repository<T> {
    fn find_by_id<'a>(&'a self, id: u64) -> Option<&'a T>;
    fn count(&self) -> usize;
}

/// Production server configuration.
#[derive(Debug, Clone)]
pub struct ServerNode<T>
where
    T: Clone + Display,
{
    pub id: u64,
    pub hostname: String,
    pub status: NodeStatus,
    pub load_factor: f64,
    pub tags: HashMap<String, T>,
}

impl<T: Clone + Display> ServerNode<T> {
    #[inline]
    pub fn new(id: u64, hostname: impl Into<String>) -> Self {
        Self {
            id,
            hostname: hostname.into(),
            status: NodeStatus::Running(8080),
            load_factor: 0.85,
            tags: HashMap::new(),
        }
    }

    pub fn inspect_state(&self) -> &'static str {
        match self.status {
            NodeStatus::Starting => "Node is initializing",
            NodeStatus::Running(port) if port > 1024 => "Node listening on unprivileged port",
            NodeStatus::Running(_) => "Node listening on system port",
            NodeStatus::Degraded { latency_ms } => {
                eprintln!("Warning: high latency of {} ms detected", latency_ms);
                "Node operating in degraded mode"
            }
            NodeStatus::Terminated => "Node has stopped",
        }
    }
}

impl<T: Clone + Display> Display for ServerNode<T> {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "Node {} ({}) [Load: {:.2}]", self.hostname, self.id, self.load_factor)
    }
}

fn main() {
    let mut primary_node: ServerNode<&'static str> = ServerNode::new(101, "node-alpha.lan");
    primary_node.tags.insert("environment".to_string(), "production");

    let timeout = Duration::from_millis(500);
    println!("Max connections: {}, Buffer: {:#X}", MAX_CONNECTIONS, BUFFER_CAPACITY);
    println!("Status: {} (timeout: {:?})", primary_node.inspect_state(), timeout);
}
