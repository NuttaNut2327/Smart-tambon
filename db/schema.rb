# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_10_01_143000) do
  create_schema "tiger"
  create_schema "tiger_data"
  create_schema "topology"

  # These are extensions that must be enabled in order to support this database
  enable_extension "fuzzystrmatch"
  enable_extension "plpgsql"
  enable_extension "postgis"
  enable_extension "postgis_tiger_geocoder"
  enable_extension "postgis_topology"

  create_table "analysis_records", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "subdistrict_id"
    t.string "name", null: false
    t.string "selection_type", null: false
    t.jsonb "geometry", default: {}, null: false
    t.jsonb "summary", default: {}, null: false
    t.jsonb "places", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subdistrict_id"], name: "index_analysis_records_on_subdistrict_id"
    t.index ["user_id"], name: "index_analysis_records_on_user_id"
  end

  create_table "population_datasets", force: :cascade do |t|
    t.bigint "subdistrict_id", null: false
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "source_file", null: false
    t.jsonb "records", default: [], null: false
    t.jsonb "summary", default: {}, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "shared_with_all", default: false, null: false
    t.index ["shared_with_all"], name: "index_population_datasets_on_shared_with_all"
    t.index ["subdistrict_id"], name: "index_population_datasets_on_subdistrict_id"
    t.index ["user_id"], name: "index_population_datasets_on_user_id"
  end

  create_table "provinces", force: :cascade do |t|
    t.string "code", null: false
    t.string "name_th", null: false
    t.string "name_en"
    t.geography "boundary", limit: {:srid=>4326, :type=>"multi_polygon", :geographic=>true}
    t.geometry "center", limit: {:srid=>4326, :type=>"st_point"}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["boundary"], name: "index_provinces_on_boundary", using: :gist
    t.index ["code"], name: "index_provinces_on_code", unique: true
  end

  create_table "subdistricts", force: :cascade do |t|
    t.bigint "province_id", null: false
    t.string "code", null: false
    t.string "name_th", null: false
    t.string "name_en"
    t.string "district_code"
    t.string "district_name_th"
    t.string "district_name_en"
    t.integer "population"
    t.string "source_name"
    t.date "source_date"
    t.geometry "boundary", limit: {:srid=>4326, :type=>"multi_polygon"}
    t.geometry "center", limit: {:srid=>4326, :type=>"st_point"}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["boundary"], name: "index_subdistricts_on_boundary", using: :gist
    t.index ["code"], name: "index_subdistricts_on_code", unique: true
    t.index ["province_id"], name: "index_subdistricts_on_province_id"
  end

  create_table "terrain_tiles", force: :cascade do |t|
    t.integer "zoom_level", null: false
    t.integer "tile_x", null: false
    t.integer "tile_y", null: false
    t.binary "image_data", null: false
    t.string "source", default: "AWS Open Data Terrain Tiles", null: false
    t.datetime "imported_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["zoom_level", "tile_x", "tile_y"], name: "index_terrain_tiles_on_coordinates", unique: true
    t.check_constraint "zoom_level >= 0 AND zoom_level <= 15", name: "terrain_tiles_zoom_level_range"
  end

  create_table "user_access_areas", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "source", default: "subdistricts", null: false
    t.jsonb "subdistrict_ids", default: [], null: false
    t.geography "boundary", limit: {:srid=>4326, :type=>"multi_polygon", :geographic=>true}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "organization_type", default: "subdistrict_administrative_organization", null: false
    t.index ["boundary"], name: "index_user_access_areas_on_boundary", using: :gist
    t.index ["user_id"], name: "index_user_access_areas_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role"
    t.bigint "subdistrict_id"
    t.string "username", null: false
    t.string "organization_key", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["organization_key"], name: "index_users_on_organization_key"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["subdistrict_id"], name: "index_users_on_subdistrict_id"
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "water_station_latest_readings", force: :cascade do |t|
    t.bigint "water_station_id", null: false
    t.float "water_level_m_msl"
    t.datetime "water_level_observed_at"
    t.string "water_level_source"
    t.float "rainfall_value"
    t.datetime "rainfall_observed_at"
    t.string "rainfall_source"
    t.float "flow_rate_m3_s"
    t.float "river_capacity_percent"
    t.datetime "source_observed_at"
    t.string "payload_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["water_station_id"], name: "index_water_station_latest_readings_on_water_station_id", unique: true
  end

  create_table "water_stations", force: :cascade do |t|
    t.string "station_id", null: false
    t.string "station_code"
    t.string "station_name_th"
    t.string "station_name_en"
    t.string "agency"
    t.string "province_code"
    t.string "province_name_th"
    t.string "district_name_th"
    t.string "subdistrict_name_th"
    t.string "main_basin_code"
    t.string "main_basin_name_th"
    t.string "sub_basin_code"
    t.string "sub_basin_name_th"
    t.jsonb "equipment", default: [], null: false
    t.float "water_level_m_msl"
    t.datetime "water_level_observed_at"
    t.float "rainfall_value"
    t.datetime "rainfall_observed_at"
    t.float "flow_rate_m3_s"
    t.float "river_capacity_percent"
    t.datetime "source_observed_at"
    t.geometry "location", limit: {:srid=>4326, :type=>"st_point"}, null: false
    t.jsonb "source_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source", default: "dwr", null: false
    t.string "source_station_id"
    t.string "agency_name"
    t.string "water_level_source"
    t.string "rainfall_source"
    t.jsonb "source_metadata", default: {}, null: false
    t.string "canonical_station_key"
    t.datetime "last_seen_at"
    t.integer "missing_sync_count", default: 0, null: false
    t.string "sync_status", default: "online", null: false
    t.index ["canonical_station_key"], name: "index_water_stations_on_canonical_station_key"
    t.index ["location"], name: "index_water_stations_on_location", using: :gist
    t.index ["source", "source_station_id"], name: "index_water_stations_on_source_identity", unique: true, where: "(source_station_id IS NOT NULL)"
    t.index ["source", "sync_status"], name: "index_water_stations_on_source_and_sync_status"
    t.index ["station_id"], name: "index_water_stations_on_station_id", unique: true
  end

  add_foreign_key "analysis_records", "subdistricts"
  add_foreign_key "analysis_records", "users"
  add_foreign_key "population_datasets", "subdistricts"
  add_foreign_key "population_datasets", "users"
  add_foreign_key "subdistricts", "provinces"
  add_foreign_key "user_access_areas", "users"
  add_foreign_key "users", "subdistricts"
  add_foreign_key "water_station_latest_readings", "water_stations"
end
