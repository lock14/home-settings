/*
 * Solarized Dark SQL Syntax Highlighting Showcase
 * Demonstrates DDL tables, constraints, CTEs, window functions, and CASE logic.
 */

-- Table schema definitions
CREATE TABLE IF NOT EXISTS customer_accounts (
    account_id BIGSERIAL PRIMARY KEY,
    organization_name VARCHAR(128) NOT NULL,
    plan_tier VARCHAR(32) NOT NULL DEFAULT 'standard' CHECK (plan_tier IN ('starter', 'standard', 'enterprise')),
    monthly_budget NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ledger_transactions (
    transaction_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id BIGINT NOT NULL REFERENCES customer_accounts(account_id) ON DELETE CASCADE,
    amount_cents BIGINT NOT NULL CHECK (amount_cents > 0),
    currency CHAR(3) NOT NULL DEFAULT 'USD',
    settled_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_ledger_account_settled
    ON ledger_transactions(account_id, settled_at DESC);

-- Analytical aggregation with CTE, Window Functions, and CASE logic
WITH monthly_billing_summary AS (
    SELECT
        a.account_id,
        a.organization_name,
        a.plan_tier,
        COUNT(t.transaction_id) AS total_invoices,
        COALESCE(SUM(t.amount_cents) / 100.0, 0.0) AS aggregate_spend,
        CASE
            WHEN a.plan_tier = 'enterprise' THEN 0.15
            WHEN a.plan_tier = 'standard'   THEN 0.05
            ELSE 0.00
        END AS discount_percentage
    FROM customer_accounts a
    LEFT JOIN ledger_transactions t
        ON t.account_id = a.account_id
        AND t.settled_at >= DATE_TRUNC('month', NOW() - INTERVAL '30 days')
    WHERE a.is_active = TRUE
    GROUP BY a.account_id, a.organization_name, a.plan_tier
)
SELECT
    s.account_id,
    s.organization_name,
    s.plan_tier,
    s.total_invoices,
    s.aggregate_spend,
    ROUND(s.aggregate_spend * (1.0 - s.discount_percentage), 2) AS net_billed_amount,
    DENSE_RANK() OVER (ORDER BY s.aggregate_spend DESC) AS revenue_rank
FROM monthly_billing_summary s
GROUP BY s.account_id, s.organization_name, s.plan_tier, s.total_invoices, s.aggregate_spend, s.discount_percentage
HAVING s.total_invoices > 0
ORDER BY revenue_rank ASC, s.aggregate_spend DESC
LIMIT 25;
