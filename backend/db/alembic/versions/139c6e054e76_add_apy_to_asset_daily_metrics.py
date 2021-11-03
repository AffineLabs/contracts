"""add apy to asset_daily_metrics

Revision ID: 139c6e054e76
Revises: e748848714cd
Create Date: 2021-11-02 22:47:47.152486

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "139c6e054e76"
down_revision = "e748848714cd"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("asset_daily_metrics", sa.Column("apy", sa.Float()))


def downgrade():
    op.drop_column("asset_daily_metrics", "apy")
