"""create table asset_price

Revision ID: 41b79613f519
Revises: 
Create Date: 2021-07-28 11:34:18.115234

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "41b79613f519"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "asset_price",
        sa.Column("asset_id", sa.Integer, nullable=False),
        sa.Column("asset_ticker", sa.String(64), nullable=False),
        sa.Column("timestamp", sa.DateTime(), nullable=False),
        sa.Column("tick_size", sa.String(64), nullable=False),
        sa.Column("closing_price", sa.Float(), nullable=True),
        sa.Column("latest_apy", sa.Float(), nullable=True),
    )

    op.create_primary_key(
        "asset_price_index",
        "asset_price",
        ["asset_id", "tick_size", "timestamp"],
    )


def downgrade():
    op.drop_table("asset_price")
