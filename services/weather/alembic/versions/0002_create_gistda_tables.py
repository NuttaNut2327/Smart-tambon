"""create gistda cache tables

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-23 16:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from geoalchemy2 import Geometry
from sqlalchemy.dialects import postgresql

revision: str = '0002'
down_revision: str | None = '0001'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table('gistda_fetches',
    sa.Column('id', sa.BigInteger(), nullable=False),
    sa.Column('dataset', sa.String(length=32), nullable=False),
    sa.Column('period_days', sa.Integer(), nullable=False),
    sa.Column('bbox_key', sa.String(length=96), nullable=False),
    sa.Column('bbox', Geometry(geometry_type='POLYGON', srid=4326, spatial_index=False), nullable=False),
    sa.Column('fetched_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('number_matched', sa.Integer(), nullable=True),
    sa.Column('number_stored', sa.Integer(), server_default='0', nullable=False),
    sa.Column('truncated', sa.Boolean(), server_default='false', nullable=False),
    sa.Column('data_timestamp', sa.String(length=40), nullable=True),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_gistda_fetches_lookup', 'gistda_fetches', ['dataset', 'period_days', 'bbox_key', 'fetched_at'])
    op.create_table('gistda_features',
    sa.Column('id', sa.BigInteger(), nullable=False),
    sa.Column('fetch_id', sa.BigInteger(), nullable=False),
    sa.Column('feature_id', sa.String(length=64), nullable=True),
    sa.Column('geom', Geometry(geometry_type='GEOMETRY', srid=4326, spatial_index=False), nullable=False),
    sa.Column('properties', postgresql.JSONB(astext_type=sa.Text()), server_default='{}', nullable=False),
    sa.ForeignKeyConstraint(['fetch_id'], ['gistda_fetches.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_gistda_features_fetch_id', 'gistda_features', ['fetch_id'])
    op.create_index('ix_gistda_features_geom', 'gistda_features', ['geom'], postgresql_using='gist')
    op.create_table('gistda_tiles',
    sa.Column('id', sa.BigInteger(), nullable=False),
    sa.Column('layer', sa.String(length=32), nullable=False),
    sa.Column('period_days', sa.Integer(), nullable=False),
    sa.Column('z', sa.Integer(), nullable=False),
    sa.Column('x', sa.Integer(), nullable=False),
    sa.Column('y', sa.Integer(), nullable=False),
    sa.Column('content', sa.LargeBinary(), nullable=True),
    sa.Column('content_type', sa.String(length=64), nullable=True),
    sa.Column('fetched_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('layer', 'period_days', 'z', 'x', 'y', name='uq_gistda_tiles')
    )
    op.create_index('ix_gistda_tiles_expires_at', 'gistda_tiles', ['expires_at'])


def downgrade() -> None:
    op.drop_table('gistda_tiles')
    op.drop_table('gistda_features')
    op.drop_table('gistda_fetches')
