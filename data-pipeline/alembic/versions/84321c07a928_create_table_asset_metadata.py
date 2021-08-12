"""create table asset_metadata

Revision ID: 84321c07a928
Revises: c7099efc574c
Create Date: 2021-07-28 12:07:41.079193

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "84321c07a928"
down_revision = "c7099efc574c"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "asset_metadata",
        sa.Column("asset_id", sa.Integer, primary_key=True),
        sa.Column("asset_ticker", sa.String(64), nullable=False, unique=True),
        sa.Column("asset_name", sa.String(256), nullable=False),
        sa.Column("asset_type", sa.String(64), nullable=False),
        sa.Column("asset_description", sa.String(256), nullable=True),
        sa.Column("asset_img_url", sa.String(256), nullable=True),
        sa.Column("asset_url", sa.String(256), nullable=True),
        sa.Column("risk_score_defi_safety", sa.Float, nullable=True),
        sa.Column("risk_score_mpl", sa.Float, nullable=True),
        sa.Column("risk_assesment", sa.ARRAY(sa.String(256)), nullable=True),
    )


def downgrade():
    op.drop_table("asset_metadata")
