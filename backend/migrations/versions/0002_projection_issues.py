"""Quarantine unsupported chain schedules without stopping Vault log sync.

Revision ID: 0002
Revises: 0001
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None
UINT_MAX = 2**256 - 1


def upgrade() -> None:
    op.create_table(
        "projection_issues",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("chain_id", sa.BigInteger(), nullable=False),
        sa.Column("vault_address", sa.String(42), nullable=False),
        sa.Column("subscription_id", sa.Numeric(78, 0), nullable=False),
        sa.Column("plan_id", sa.Numeric(78, 0), nullable=False),
        sa.Column("merchant_address", sa.String(42), nullable=False),
        sa.Column("subscriber_address", sa.String(42), nullable=False),
        sa.Column("code", sa.String(64), nullable=False),
        sa.Column("raw_timestamps", postgresql.JSONB(), nullable=False),
        sa.Column("synced_block_number", sa.Numeric(78, 0), nullable=False),
        sa.Column("synced_block_hash", sa.String(66), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "chain_id", "vault_address", "subscription_id", name="uq_projection_issue"
        ),
        sa.CheckConstraint(
            "code = 'UNSUPPORTED_TIMESTAMP'", name="ck_projection_issue_code"
        ),
        *[
            sa.CheckConstraint(
                f"{name} BETWEEN 0 AND {UINT_MAX}", name=f"ck_{name}_uint256"
            )
            for name in ("subscription_id", "plan_id", "synced_block_number")
        ],
    )
    op.create_index(
        "ix_issue_subscriber",
        "projection_issues",
        ["chain_id", "vault_address", "subscriber_address"],
    )
    op.create_index(
        "ix_issue_merchant",
        "projection_issues",
        ["chain_id", "vault_address", "merchant_address"],
    )


def downgrade() -> None:
    op.drop_index("ix_issue_merchant", table_name="projection_issues")
    op.drop_index("ix_issue_subscriber", table_name="projection_issues")
    op.drop_table("projection_issues")
