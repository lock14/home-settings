# Open Policy Agent (OPA Rego v1) admission and authorization policy
# Validates telemetry cluster ingestion requests, mTLS identities, and rate limits.

package telemetry.authz.v1

import rego.v1
import data.clusters.topology as cluster_topology
import input.request

MAX_BURST_RATE := 5000
DEFAULT_MIN_SCORE := 0.85

default allow := false

# Primary authorization decision for telemetry ingestion batches
allow if {
    request.mtls.verified == true
    request.principal.role in {"ingestor", "cluster_admin"}
    not is_rate_limited(request, MAX_BURST_RATE)
    all_endpoints_healthy
    count(violations) == 0
    request.metadata.trace_id != null
}

# Multi-value set rule collecting policy violation messages
violations contains msg if {
    some endpoint in request.endpoints
    not regex.match(`^https://[a-z0-9.-]+\.example\.org:[0-9]+/v[12]/ingest$`, endpoint.url)
    msg := sprintf("endpoint %q failed TLS URI schema validation", [endpoint.id])
}

violations contains msg if {
    count(request.endpoints) == 0
    msg := "ingest batch must declare at least one target endpoint"
}

# Universal quantification over all target endpoints in the batch
all_endpoints_healthy if {
    every ep in request.endpoints {
        ep.status == "READY"
        ep.latency_ms <= 250
        ep.error_budget_delta >= -10
        ep.health_score >= DEFAULT_MIN_SCORE
    }
}

# Parameterized helper function with fallback else branch
is_rate_limited(req, limit) if {
    req.rate_per_sec > limit
} else if {
    req.burst_tokens <= 0
}

# Rule with value assignment and else fallback
tier_name := "platinum" if {
    request.priority >= 90
} else := "standard" {
    request.priority >= 50
}

# Array comprehension filtering healthy topology node IDs
active_node_ids := [node.id |
    some node in cluster_topology.nodes
    node.healthy == true
]

# Structured policy evaluation summary
audit_decision := {
    "allowed": allow,
    "tier": tier_name,
    "violation_count": count(violations),
    "active_nodes": active_node_ids,
}

# Policy evaluation helper exercising `with` input override
allow_emergency_override if {
    allow with input.request.priority as 95
}
