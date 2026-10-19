"""create weather tables

Revision ID: 0001
Revises: 
Create Date: 2026-10-16 16:31:09.652502
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from geoalchemy2 import Geometry
from sqlalchemy.dialects import postgresql

revision: str = '0001'
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")
    op.create_geospatial_table('weather_locations',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('code', sa.String(length=64), nullable=False),
    sa.Column('name', sa.String(length=255), nullable=False),
    sa.Column('name_th', sa.String(length=255), nullable=True),
    sa.Column('province', sa.String(length=128), nullable=True),
    sa.Column('district', sa.String(length=128), nullable=True),
    sa.Column('subdistrict', sa.String(length=128), nullable=True),
    sa.Column('latitude', sa.Float(), nullable=False),
    sa.Column('longitude', sa.Float(), nullable=False),
    sa.Column('geom', Geometry(geometry_type='POINT', srid=4326, dimension=2, spatial_index=False, from_text='ST_GeomFromEWKT', name='geometry', nullable=False), nullable=False),
    sa.Column('timezone', sa.String(length=64), nullable=False),
    sa.Column('elevation_m', sa.Float(), nullable=True),
    sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('code')
    )
    op.create_geospatial_index('ix_weather_locations_geom', 'weather_locations', ['geom'], unique=False, postgresql_using='gist', postgresql_ops={})
    op.create_index(op.f('ix_weather_locations_province'), 'weather_locations', ['province'], unique=False)
    op.create_table('weather_current',
    sa.Column('id', sa.BigInteger(), nullable=False),
    sa.Column('location_id', sa.Integer(), nullable=False),
    sa.Column('observed_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('interval_seconds', sa.Integer(), nullable=True),
    sa.Column('temperature_c', sa.Float(), nullable=True),
    sa.Column('apparent_temperature_c', sa.Float(), nullable=True),
    sa.Column('relative_humidity_pct', sa.Float(), nullable=True),
    sa.Column('dew_point_c', sa.Float(), nullable=True),
    sa.Column('precipitation_mm', sa.Float(), nullable=True),
    sa.Column('rain_mm', sa.Float(), nullable=True),
    sa.Column('weather_code', sa.Integer(), nullable=True),
    sa.Column('cloud_cover_pct', sa.Float(), nullable=True),
    sa.Column('pressure_msl_hpa', sa.Float(), nullable=True),
    sa.Column('surface_pressure_hpa', sa.Float(), nullable=True),
    sa.Column('wind_speed_kmh', sa.Float(), nullable=True),
    sa.Column('wind_direction_deg', sa.Float(), nullable=True),
    sa.Column('wind_gusts_kmh', sa.Float(), nullable=True),
    sa.Column('visibility_m', sa.Float(), nullable=True),
    sa.Column('uv_index', sa.Float(), nullable=True),
    sa.Column('is_day', sa.Boolean(), nullable=True),
    sa.Column('provider', sa.String(length=64), nullable=False),
    sa.Column('model', sa.String(length=64), nullable=False),
    sa.Column('fetched_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('is_fallback', sa.Boolean(), server_default='false', nullable=False),
    sa.Column('fallback_reason', sa.Text(), nullable=True),
    sa.Column('unavailable_params', postgresql.JSONB(astext_type=sa.Text()), server_default='[]', nullable=False),
    sa.ForeignKeyConstraint(['location_id'], ['weather_locations.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('location_id', 'provider', 'model', 'observed_at', name='uq_weather_current_obs')
    )
    op.create_index('ix_weather_current_loc_time', 'weather_current', ['location_id', 'observed_at'], unique=False)
    op.create_index(op.f('ix_weather_current_location_id'), 'weather_current', ['location_id'], unique=False)
    op.create_table('weather_daily_forecast',
    sa.Column('id', sa.BigInteger(), nullable=False),
    sa.Column('location_id', sa.Integer(), nullable=False),
    sa.Column('run_id', sa.String(length=128), nullable=False),
    sa.Column('run_init_time', sa.DateTime(timezone=True), nullable=True),
    sa.Column('run_id_source', sa.String(length=32), nullable=False),
    sa.Column('issue_date', sa.Date(), nullable=False),
    sa.Column('forecast_date', sa.Date(), nullable=False),
    sa.Column('forecast_lead_days', sa.Integer(), nullable=False),
    sa.Column('weather_code', sa.Integer(), nullable=True),
    sa.Column('temperature_max_c', sa.Float(), nullable=True),
    sa.Column('temperature_min_c', sa.Float(), nullable=True),
    sa.Column('apparent_temperature_max_c', sa.Float(), nullable=True),
    sa.Column('apparent_temperature_min_c', sa.Float(), nullable=True),
    sa.Column('precipitation_sum_mm', sa.Float(), nullable=True),
    sa.Column('rain_sum_mm', sa.Float(), nullable=True),
    sa.Column('precipitation_hours', sa.Float(), nullable=True),
    sa.Column('precipitation_probability_max_pct', sa.Float(), nullable=True),
    sa.Column('wind_speed_max_kmh', sa.Float(), nullable=True),
    sa.Column('wind_gusts_max_kmh', sa.Float(), nullable=True),
    sa.Column('wind_direction_dominant_deg', sa.Float(), nullable=True),
    sa.Column('relative_humidity_mean_pct', sa.Float(), nullable=True),
    sa.Column('cloud_cover_mean_pct', sa.Float(), nullable=True),
    sa.Column('shortwave_radiation_sum_mj_m2', sa.Float(), nullable=True),
    sa.Column('et0_mm', sa.Float(), nullable=True),
    sa.Column('uv_index_max', sa.Float(), nullable=True),
    sa.Column('sunrise', sa.DateTime(timezone=True), nullable=True),
    sa.Column('sunset', sa.DateTime(timezone=True), nullable=True),
    sa.Column('daylight_duration_s', sa.Float(), nullable=True),
    sa.Column('provider', sa.String(length=64), nullable=False),
    sa.Column('model', sa.String(length=64), nullable=False),
    sa.Column('fetched_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('is_fallback', sa.Boolean(), server_default='false', nullable=False),
    sa.Column('fallback_reason', sa.Text(), nullable=True),
    sa.Column('unavailable_params', postgresql.JSONB(astext_type=sa.Text()), server_default='[]', nullable=False),
    sa.ForeignKeyConstraint(['location_id'], ['weather_locations.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('provider', 'model', 'run_id', 'location_id', 'forecast_date', name='uq_weather_daily_forecast_run')
    )
    op.create_index('ix_weather_daily_forecast_lead', 'weather_daily_forecast', ['forecast_lead_days'], unique=False)
    op.create_index('ix_weather_daily_forecast_lookup', 'weather_daily_forecast', ['location_id', 'forecast_date', 'fetched_at'], unique=False)
    op.create_table('weather_daily_observation',
    sa.Column('id', sa.BigInteger(), nullable=False),
    sa.Column('location_id', sa.Integer(), nullable=False),
    sa.Column('observation_date', sa.Date(), nullable=False),
    sa.Column('source_type', sa.String(length=32), nullable=False),
    sa.Column('source_name', sa.String(length=64), nullable=False),
    sa.Column('model', sa.String(length=64), nullable=True),
    sa.Column('data_quality', sa.String(length=16), nullable=False),
    sa.Column('is_final', sa.Boolean(), server_default='false', nullable=False),
    sa.Column('revision', sa.Integer(), server_default='1', nullable=False),
    sa.Column('fetched_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('finalized_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('unavailable_params', postgresql.JSONB(astext_type=sa.Text()), server_default='[]', nullable=False),
    sa.Column('weather_code', sa.Integer(), nullable=True),
    sa.Column('temperature_max_c', sa.Float(), nullable=True),
    sa.Column('temperature_min_c', sa.Float(), nullable=True),
    sa.Column('temperature_mean_c', sa.Float(), nullable=True),
    sa.Column('precipitation_sum_mm', sa.Float(), nullable=True),
    sa.Column('rain_sum_mm', sa.Float(), nullable=True),
    sa.Column('precipitation_hours', sa.Float(), nullable=True),
    sa.Column('wind_speed_max_kmh', sa.Float(), nullable=True),
    sa.Column('wind_gusts_max_kmh', sa.Float(), nullable=True),
    sa.Column('wind_direction_dominant_deg', sa.Float(), nullable=True),
    sa.Column('relative_humidity_mean_pct', sa.Float(), nullable=True),
    sa.Column('shortwave_radiation_sum_mj_m2', sa.Float(), nullable=True),
    sa.Column('et0_mm', sa.Float(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['location_id'], ['weather_locations.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('location_id', 'observation_date', 'source_type', 'source_name', name='uq_weather_daily_observation')
    )
    op.create_index('ix_weather_daily_observation_lookup', 'weather_daily_observation', ['location_id', 'observation_date'], unique=False)
    op.create_table('weather_hourly',
    sa.Column('id', sa.BigInteger(), nullable=False),
    sa.Column('location_id', sa.Integer(), nullable=False),
    sa.Column('data_kind', sa.String(length=16), nullable=False),
    sa.Column('provider', sa.String(length=64), nullable=False),
    sa.Column('model', sa.String(length=64), nullable=False),
    sa.Column('run_id', sa.String(length=128), nullable=False),
    sa.Column('valid_time', sa.DateTime(timezone=True), nullable=False),
    sa.Column('fetched_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('is_fallback', sa.Boolean(), server_default='false', nullable=False),
    sa.Column('source_type', sa.String(length=32), nullable=True),
    sa.Column('temperature_c', sa.Float(), nullable=True),
    sa.Column('apparent_temperature_c', sa.Float(), nullable=True),
    sa.Column('relative_humidity_pct', sa.Float(), nullable=True),
    sa.Column('dew_point_c', sa.Float(), nullable=True),
    sa.Column('precipitation_mm', sa.Float(), nullable=True),
    sa.Column('precipitation_probability_pct', sa.Float(), nullable=True),
    sa.Column('weather_code', sa.Integer(), nullable=True),
    sa.Column('cloud_cover_pct', sa.Float(), nullable=True),
    sa.Column('pressure_msl_hpa', sa.Float(), nullable=True),
    sa.Column('wind_speed_kmh', sa.Float(), nullable=True),
    sa.Column('wind_direction_deg', sa.Float(), nullable=True),
    sa.Column('wind_gusts_kmh', sa.Float(), nullable=True),
    sa.Column('visibility_m', sa.Float(), nullable=True),
    sa.Column('uv_index', sa.Float(), nullable=True),
    sa.Column('is_day', sa.Boolean(), nullable=True),
    sa.ForeignKeyConstraint(['location_id'], ['weather_locations.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('location_id', 'data_kind', 'provider', 'model', 'run_id', 'valid_time', name='uq_weather_hourly')
    )
    op.create_index('ix_weather_hourly_lookup', 'weather_hourly', ['location_id', 'data_kind', 'valid_time'], unique=False)
    op.create_table('weather_ingestion_logs',
    sa.Column('id', sa.BigInteger(), nullable=False),
    sa.Column('job_type', sa.String(length=32), nullable=False),
    sa.Column('status', sa.String(length=16), nullable=False),
    sa.Column('provider', sa.String(length=64), nullable=True),
    sa.Column('model', sa.String(length=64), nullable=True),
    sa.Column('location_id', sa.Integer(), nullable=True),
    sa.Column('run_id', sa.String(length=128), nullable=True),
    sa.Column('is_fallback', sa.Boolean(), server_default='false', nullable=False),
    sa.Column('attempts', sa.Integer(), server_default='0', nullable=False),
    sa.Column('records_inserted', sa.Integer(), server_default='0', nullable=False),
    sa.Column('records_skipped', sa.Integer(), server_default='0', nullable=False),
    sa.Column('started_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('finished_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('duration_ms', sa.Integer(), nullable=True),
    sa.Column('error', sa.Text(), nullable=True),
    sa.Column('details', postgresql.JSONB(astext_type=sa.Text()), server_default='{}', nullable=False),
    sa.ForeignKeyConstraint(['location_id'], ['weather_locations.id'], ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_weather_ingestion_logs_job_type'), 'weather_ingestion_logs', ['job_type'], unique=False)
    op.create_index('ix_weather_ingestion_logs_started', 'weather_ingestion_logs', ['started_at'], unique=False)
    op.create_table('weather_daily_observation_revisions',
    sa.Column('id', sa.BigInteger(), nullable=False),
    sa.Column('observation_id', sa.BigInteger(), nullable=False),
    sa.Column('revision', sa.Integer(), nullable=False),
    sa.Column('data_quality', sa.String(length=16), nullable=False),
    sa.Column('is_final', sa.Boolean(), nullable=False),
    sa.Column('model', sa.String(length=64), nullable=True),
    sa.Column('values', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('fetched_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('superseded_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['observation_id'], ['weather_daily_observation.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_weather_daily_observation_revisions_observation_id'), 'weather_daily_observation_revisions', ['observation_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_weather_daily_observation_revisions_observation_id'), table_name='weather_daily_observation_revisions')
    op.drop_table('weather_daily_observation_revisions')
    op.drop_index('ix_weather_ingestion_logs_started', table_name='weather_ingestion_logs')
    op.drop_index(op.f('ix_weather_ingestion_logs_job_type'), table_name='weather_ingestion_logs')
    op.drop_table('weather_ingestion_logs')
    op.drop_index('ix_weather_hourly_lookup', table_name='weather_hourly')
    op.drop_table('weather_hourly')
    op.drop_index('ix_weather_daily_observation_lookup', table_name='weather_daily_observation')
    op.drop_table('weather_daily_observation')
    op.drop_index('ix_weather_daily_forecast_lookup', table_name='weather_daily_forecast')
    op.drop_index('ix_weather_daily_forecast_lead', table_name='weather_daily_forecast')
    op.drop_table('weather_daily_forecast')
    op.drop_index(op.f('ix_weather_current_location_id'), table_name='weather_current')
    op.drop_index('ix_weather_current_loc_time', table_name='weather_current')
    op.drop_table('weather_current')
    op.drop_index(op.f('ix_weather_locations_province'), table_name='weather_locations')
    op.drop_geospatial_index('ix_weather_locations_geom', table_name='weather_locations', postgresql_using='gist', column_name='geom')
    op.drop_geospatial_table('weather_locations')
