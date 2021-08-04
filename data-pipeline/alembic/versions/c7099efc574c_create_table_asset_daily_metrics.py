"""create table asset_daily_metrics

Revision ID: c7099efc574c
Revises: 41b79613f519
Create Date: 2021-07-28 11:56:30.432171

"""
from sqlalchemy.sql.expression import null
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "c7099efc574c"
down_revision = "41b79613f519"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "asset_daily_metrics",
        sa.Column("asset_id", sa.Integer, nullable=False),
        sa.Column("asset_ticker", sa.String(64), nullable=False),
        sa.Column("trading_volume_24h", sa.Float(), nullable=True),
        sa.Column("market_cap", sa.Float(), nullable=True),
        sa.Column("tvl", sa.Float(), nullable=True),
        sa.Column("pool_trading_volume_24h", sa.Float(), nullable=True),
        sa.Column("utilization_rate", sa.Float(), nullable=True),
        sa.Column("tick_size", sa.String(64), nullable=False),
        sa.Column("timestamp", sa.DateTime(), nullable=False),
        sa.Column("1d_return", sa.Float()),
        sa.Column("1w_return", sa.Float()),
        sa.Column("1m_return", sa.Float()),
        sa.Column("1y_return", sa.Float()),
    )

    op.create_index(
        "asset_daily_metrics_index",
        "asset_daily_metrics",
        ["asset_id", "tick_size", "timestamp"],
    )


def downgrade():
    op.drop_table("asset_daily_metrics")
