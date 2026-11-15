"""Remember transaction nonces and confirmed replacements.

Revision ID: 0003
Revises: 0002
"""

import sqlalchemy as sa
from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "transactions", sa.Column("sender_nonce", sa.Numeric(78, 0), nullable=True)
    )
    op.add_column(
        "transactions", sa.Column("replacement_tx_hash", sa.String(66), nullable=True)
    )
    op.create_check_constraint(
        "ck_sender_nonce_uint256",
        "transactions",
        f"sender_nonce BETWEEN 0 AND {2**256 - 1}",
    )
    op.drop_constraint("ck_tx_status", "transactions", type_="check")
    op.create_check_constraint(
        "ck_tx_status",
        "transactions",
        "status IN ('SUBMITTED','CONFIRMED','REVERTED','REPLACED','CANCELLED')",
    )


def downgrade() -> None:
    op.execute(
        "UPDATE transactions SET status='SUBMITTED', block_number=NULL, block_hash=NULL, failure_code=NULL WHERE status IN ('REPLACED','CANCELLED')"
    )
    op.drop_constraint("ck_tx_status", "transactions", type_="check")
    op.create_check_constraint(
        "ck_tx_status", "transactions", "status IN ('SUBMITTED','CONFIRMED','REVERTED')"
    )
    op.drop_constraint("ck_sender_nonce_uint256", "transactions", type_="check")
    op.drop_column("transactions", "replacement_tx_hash")
    op.drop_column("transactions", "sender_nonce")
