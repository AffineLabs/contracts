"""create user_balance table

Revision ID: e748848714cd
Revises: 84321c07a928
Create Date: 2021-10-25 21:29:51.503246

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "e748848714cd"
down_revision = "84321c07a928"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "user_balance",
        sa.Column("user_id", sa.Integer, nullable=False),
        sa.Column("user_public_address", sa.String(64), nullable=False),
        sa.Column("timestamp", sa.DateTime(), nullable=False),
        sa.Column("tick_size", sa.String(64), nullable=False),
        sa.Column("user_balance", sa.Float(), nullable=True),
    )

    op.create_index(
        "user_balance_index",
        "user_balance",
        ["user_id", "tick_size", "timestamp"],
    )


def downgrade():
    op.drop_table("user_balance")
