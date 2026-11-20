"""Club schedule, hourly attendance, announcements and member invitations."""

import sqlalchemy as sa
from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = depends_on = None


def upgrade():
    op.create_table(
        "club_entries",
        sa.Column("id", sa.Uuid, primary_key=True),
        sa.Column(
            "merchant_id", sa.Uuid, sa.ForeignKey("merchants.id"), nullable=False
        ),
        sa.Column("branch", sa.String(100), nullable=False),
        sa.Column("kind", sa.String(12), nullable=False),
        sa.Column("title", sa.String(120), nullable=False),
        sa.Column("detail", sa.String(500), nullable=False),
        sa.Column("day", sa.Date, nullable=False),
        sa.Column("minute", sa.Integer, nullable=False),
        sa.Column("amount", sa.Integer, nullable=False),
        sa.Column("created", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_club_day", "club_entries", ["merchant_id", "branch", "day", "kind"]
    )
    op.create_index(
        "uq_club_hour",
        "club_entries",
        ["merchant_id", "branch", "day", "minute"],
        unique=True,
        postgresql_where=sa.text("kind = 'attendance'"),
    )
    op.create_table(
        "buddy_invites",
        sa.Column("digest", sa.String(64), primary_key=True),
        sa.Column("owner", sa.Uuid, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("expires", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_table(
        "buddy_pairs",
        sa.Column("first_id", sa.Uuid, sa.ForeignKey("users.id"), primary_key=True),
        sa.Column("second_id", sa.Uuid, sa.ForeignKey("users.id"), primary_key=True),
    )


def downgrade():
    op.drop_table("buddy_pairs")
    op.drop_table("buddy_invites")
    op.drop_table("club_entries")
