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

ActiveRecord::Schema[7.2].define(version: 2026_09_14_100000) do
  create_schema "tiger"
  create_schema "tiger_data"
  create_schema "topology"

  # These are extensions that must be enabled in order to support this database
  enable_extension "fuzzystrmatch"
  enable_extension "plpgsql"
  enable_extension "postgis"
  enable_extension "postgis_tiger_geocoder"
  enable_extension "postgis_topology"

  create_table "addr", primary_key: "gid", id: :serial, force: :cascade do |t|
    t.bigint "tlid"
    t.string "fromhn", limit: 12
    t.string "tohn", limit: 12
    t.string "side", limit: 1
    t.string "zip", limit: 5
    t.string "plus4", limit: 4
    t.string "fromtyp", limit: 1
    t.string "totyp", limit: 1
    t.integer "fromarmid"
    t.integer "toarmid"
    t.string "arid", limit: 22
    t.string "mtfcc", limit: 5
    t.string "statefp", limit: 2
    t.index ["tlid", "statefp"], name: "idx_tiger_addr_tlid_statefp"
    t.index ["zip"], name: "idx_tiger_addr_zip"
  end

  create_table "addrfeat", primary_key: "gid", id: :serial, force: :cascade do |t|
    t.bigint "tlid"
    t.string "statefp", limit: 2, null: false
    t.string "aridl", limit: 22
    t.string "aridr", limit: 22
    t.string "linearid", limit: 22
    t.string "fullname", limit: 100
    t.string "lfromhn", limit: 12
    t.string "ltohn", limit: 12
    t.string "rfromhn", limit: 12
    t.string "rtohn", limit: 12
    t.string "zipl", limit: 5
    t.string "zipr", limit: 5
    t.string "edge_mtfcc", limit: 5
    t.string "parityl", limit: 1
    t.string "parityr", limit: 1
    t.string "plus4l", limit: 4
    t.string "plus4r", limit: 4
    t.string "lfromtyp", limit: 1
    t.string "ltotyp", limit: 1
    t.string "rfromtyp", limit: 1
    t.string "rtotyp", limit: 1
    t.string "offsetl", limit: 1
    t.string "offsetr", limit: 1
    t.geometry "the_geom", limit: {:srid=>4269, :type=>"line_string"}
    t.index ["the_geom"], name: "idx_addrfeat_geom_gist", using: :gist
    t.index ["tlid"], name: "idx_addrfeat_tlid"
    t.index ["zipl"], name: "idx_addrfeat_zipl"
    t.index ["zipr"], name: "idx_addrfeat_zipr"
    t.check_constraint "geometrytype(the_geom) = 'LINESTRING'::text OR the_geom IS NULL", name: "enforce_geotype_the_geom"
    t.check_constraint "st_ndims(the_geom) = 2", name: "enforce_dims_the_geom"
    t.check_constraint "st_srid(the_geom) = 4269", name: "enforce_srid_the_geom"
  end

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

  create_table "bg", primary_key: "bg_id", id: { type: :string, limit: 12 }, comment: "block groups", force: :cascade do |t|
    t.serial "gid", null: false
    t.string "statefp", limit: 2
    t.string "countyfp", limit: 3
    t.string "tractce", limit: 6
    t.string "blkgrpce", limit: 1
    t.string "namelsad", limit: 13
    t.string "mtfcc", limit: 5
    t.string "funcstat", limit: 1
    t.float "aland"
    t.float "awater"
    t.string "intptlat", limit: 11
    t.string "intptlon", limit: 12
    t.geometry "the_geom", limit: {:srid=>4269, :type=>"multi_polygon"}
    t.check_constraint "geometrytype(the_geom) = 'MULTIPOLYGON'::text OR the_geom IS NULL", name: "enforce_geotype_geom"
    t.check_constraint "st_ndims(the_geom) = 2", name: "enforce_dims_geom"
    t.check_constraint "st_srid(the_geom) = 4269", name: "enforce_srid_geom"
  end

  create_table "county", primary_key: "cntyidfp", id: { type: :string, limit: 5 }, force: :cascade do |t|
    t.serial "gid", null: false
    t.string "statefp", limit: 2
    t.string "countyfp", limit: 3
    t.string "countyns", limit: 8
    t.string "name", limit: 100
    t.string "namelsad", limit: 100
    t.string "lsad", limit: 2
    t.string "classfp", limit: 2
    t.string "mtfcc", limit: 5
    t.string "csafp", limit: 3
    t.string "cbsafp", limit: 5
    t.string "metdivfp", limit: 5
    t.string "funcstat", limit: 1
    t.bigint "aland"
    t.float "awater"
    t.string "intptlat", limit: 11
    t.string "intptlon", limit: 12
    t.geometry "the_geom", limit: {:srid=>4269, :type=>"multi_polygon"}
    t.index ["countyfp"], name: "idx_tiger_county"
    t.check_constraint "geometrytype(the_geom) = 'MULTIPOLYGON'::text OR the_geom IS NULL", name: "enforce_geotype_geom"
    t.check_constraint "st_ndims(the_geom) = 2", name: "enforce_dims_geom"
    t.check_constraint "st_srid(the_geom) = 4269", name: "enforce_srid_geom"
    t.unique_constraint ["gid"], name: "uidx_county_gid"
  end

  create_table "county_lookup", primary_key: ["st_code", "co_code"], force: :cascade do |t|
    t.integer "st_code", null: false
    t.string "state", limit: 2
    t.integer "co_code", null: false
    t.string "name", limit: 90
    t.index "soundex((name)::text)", name: "county_lookup_name_idx"
    t.index ["state"], name: "county_lookup_state_idx"
  end

  create_table "countysub_lookup", primary_key: ["st_code", "co_code", "cs_code"], force: :cascade do |t|
    t.integer "st_code", null: false
    t.string "state", limit: 2
    t.integer "co_code", null: false
    t.string "county", limit: 90
    t.integer "cs_code", null: false
    t.string "name", limit: 90
    t.index "soundex((name)::text)", name: "countysub_lookup_name_idx"
    t.index ["state"], name: "countysub_lookup_state_idx"
  end

  create_table "cousub", primary_key: "cosbidfp", id: { type: :string, limit: 10 }, force: :cascade do |t|
    t.serial "gid", null: false
    t.string "statefp", limit: 2
    t.string "countyfp", limit: 3
    t.string "cousubfp", limit: 5
    t.string "cousubns", limit: 8
    t.string "name", limit: 100
    t.string "namelsad", limit: 100
    t.string "lsad", limit: 2
    t.string "classfp", limit: 2
    t.string "mtfcc", limit: 5
    t.string "cnectafp", limit: 3
    t.string "nectafp", limit: 5
    t.string "nctadvfp", limit: 5
    t.string "funcstat", limit: 1
    t.decimal "aland", precision: 14
    t.decimal "awater", precision: 14
    t.string "intptlat", limit: 11
    t.string "intptlon", limit: 12
    t.geometry "the_geom", limit: {:srid=>4269, :type=>"multi_polygon"}
    t.index ["the_geom"], name: "tige_cousub_the_geom_gist", using: :gist
    t.check_constraint "geometrytype(the_geom) = 'MULTIPOLYGON'::text OR the_geom IS NULL", name: "enforce_geotype_the_geom"
    t.check_constraint "st_ndims(the_geom) = 2", name: "enforce_dims_the_geom"
    t.check_constraint "st_srid(the_geom) = 4269", name: "enforce_srid_the_geom"
    t.unique_constraint ["gid"], name: "uidx_cousub_gid"
  end

  create_table "direction_lookup", primary_key: "name", id: { type: :string, limit: 20 }, force: :cascade do |t|
    t.string "abbrev", limit: 3
    t.index ["abbrev"], name: "direction_lookup_abbrev_idx"
  end

  create_table "edges", primary_key: "gid", id: :serial, force: :cascade do |t|
    t.string "statefp", limit: 2
    t.string "countyfp", limit: 3
    t.bigint "tlid"
    t.decimal "tfidl", precision: 10
    t.decimal "tfidr", precision: 10
    t.string "mtfcc", limit: 5
    t.string "fullname", limit: 100
    t.string "smid", limit: 22
    t.string "lfromadd", limit: 12
    t.string "ltoadd", limit: 12
    t.string "rfromadd", limit: 12
    t.string "rtoadd", limit: 12
    t.string "zipl", limit: 5
    t.string "zipr", limit: 5
    t.string "featcat", limit: 1
    t.string "hydroflg", limit: 1
    t.string "railflg", limit: 1
    t.string "roadflg", limit: 1
    t.string "olfflg", limit: 1
    t.string "passflg", limit: 1
    t.string "divroad", limit: 1
    t.string "exttyp", limit: 1
    t.string "ttyp", limit: 1
    t.string "deckedroad", limit: 1
    t.string "artpath", limit: 1
    t.string "persist", limit: 1
    t.string "gcseflg", limit: 1
    t.string "offsetl", limit: 1
    t.string "offsetr", limit: 1
    t.decimal "tnidf", precision: 10
    t.decimal "tnidt", precision: 10
    t.geometry "the_geom", limit: {:srid=>4269, :type=>"multi_line_string"}
    t.index ["countyfp"], name: "idx_tiger_edges_countyfp"
    t.index ["the_geom"], name: "idx_tiger_edges_the_geom_gist", using: :gist
    t.index ["tlid"], name: "idx_edges_tlid"
    t.check_constraint "geometrytype(the_geom) = 'MULTILINESTRING'::text OR the_geom IS NULL", name: "enforce_geotype_the_geom"
    t.check_constraint "st_ndims(the_geom) = 2", name: "enforce_dims_the_geom"
    t.check_constraint "st_srid(the_geom) = 4269", name: "enforce_srid_the_geom"
  end

  create_table "faces", primary_key: "gid", id: :serial, force: :cascade do |t|
    t.decimal "tfid", precision: 10
    t.string "statefp00", limit: 2
    t.string "countyfp00", limit: 3
    t.string "tractce00", limit: 6
    t.string "blkgrpce00", limit: 1
    t.string "blockce00", limit: 4
    t.string "cousubfp00", limit: 5
    t.string "submcdfp00", limit: 5
    t.string "conctyfp00", limit: 5
    t.string "placefp00", limit: 5
    t.string "aiannhfp00", limit: 5
    t.string "aiannhce00", limit: 4
    t.string "comptyp00", limit: 1
    t.string "trsubfp00", limit: 5
    t.string "trsubce00", limit: 3
    t.string "anrcfp00", limit: 5
    t.string "elsdlea00", limit: 5
    t.string "scsdlea00", limit: 5
    t.string "unsdlea00", limit: 5
    t.string "uace00", limit: 5
    t.string "cd108fp", limit: 2
    t.string "sldust00", limit: 3
    t.string "sldlst00", limit: 3
    t.string "vtdst00", limit: 6
    t.string "zcta5ce00", limit: 5
    t.string "tazce00", limit: 6
    t.string "ugace00", limit: 5
    t.string "puma5ce00", limit: 5
    t.string "statefp", limit: 2
    t.string "countyfp", limit: 3
    t.string "tractce", limit: 6
    t.string "blkgrpce", limit: 1
    t.string "blockce", limit: 4
    t.string "cousubfp", limit: 5
    t.string "submcdfp", limit: 5
    t.string "conctyfp", limit: 5
    t.string "placefp", limit: 5
    t.string "aiannhfp", limit: 5
    t.string "aiannhce", limit: 4
    t.string "comptyp", limit: 1
    t.string "trsubfp", limit: 5
    t.string "trsubce", limit: 3
    t.string "anrcfp", limit: 5
    t.string "ttractce", limit: 6
    t.string "tblkgpce", limit: 1
    t.string "elsdlea", limit: 5
    t.string "scsdlea", limit: 5
    t.string "unsdlea", limit: 5
    t.string "uace", limit: 5
    t.string "cd111fp", limit: 2
    t.string "sldust", limit: 3
    t.string "sldlst", limit: 3
    t.string "vtdst", limit: 6
    t.string "zcta5ce", limit: 5
    t.string "tazce", limit: 6
    t.string "ugace", limit: 5
    t.string "puma5ce", limit: 5
    t.string "csafp", limit: 3
    t.string "cbsafp", limit: 5
    t.string "metdivfp", limit: 5
    t.string "cnectafp", limit: 3
    t.string "nectafp", limit: 5
    t.string "nctadvfp", limit: 5
    t.string "lwflag", limit: 1
    t.string "offset", limit: 1
    t.float "atotal"
    t.string "intptlat", limit: 11
    t.string "intptlon", limit: 12
    t.geometry "the_geom", limit: {:srid=>4269, :type=>"multi_polygon"}
    t.string "tractce20", limit: 6
    t.string "blkgrpce20", limit: 1
    t.string "blockce20", limit: 4
    t.string "countyfp20", limit: 3
    t.string "statefp20", limit: 2
    t.index ["countyfp"], name: "idx_tiger_faces_countyfp"
    t.index ["tfid"], name: "idx_tiger_faces_tfid"
    t.index ["the_geom"], name: "tiger_faces_the_geom_gist", using: :gist
    t.check_constraint "geometrytype(the_geom) = 'MULTIPOLYGON'::text OR the_geom IS NULL", name: "enforce_geotype_the_geom"
    t.check_constraint "st_ndims(the_geom) = 2", name: "enforce_dims_the_geom"
    t.check_constraint "st_srid(the_geom) = 4269", name: "enforce_srid_the_geom"
  end

  create_table "featnames", primary_key: "gid", id: :serial, force: :cascade do |t|
    t.bigint "tlid"
    t.string "fullname", limit: 100
    t.string "name", limit: 100
    t.string "predirabrv", limit: 15
    t.string "pretypabrv", limit: 50
    t.string "prequalabr", limit: 15
    t.string "sufdirabrv", limit: 15
    t.string "suftypabrv", limit: 50
    t.string "sufqualabr", limit: 15
    t.string "predir", limit: 2
    t.string "pretyp", limit: 3
    t.string "prequal", limit: 2
    t.string "sufdir", limit: 2
    t.string "suftyp", limit: 3
    t.string "sufqual", limit: 2
    t.string "linearid", limit: 22
    t.string "mtfcc", limit: 5
    t.string "paflag", limit: 1
    t.string "statefp", limit: 2
    t.index "lower((name)::text)", name: "idx_tiger_featnames_lname"
    t.index "soundex((name)::text)", name: "idx_tiger_featnames_snd_name"
    t.index ["tlid", "statefp"], name: "idx_tiger_featnames_tlid_statefp"
  end

  create_table "geocode_settings", primary_key: "name", id: :text, force: :cascade do |t|
    t.text "setting"
    t.text "unit"
    t.text "category"
    t.text "short_desc"
  end

  create_table "geocode_settings_default", primary_key: "name", id: :text, force: :cascade do |t|
    t.text "setting"
    t.text "unit"
    t.text "category"
    t.text "short_desc"
  end

  create_table "loader_lookuptables", primary_key: "lookup_name", id: { type: :text, comment: "This is the table name to inherit from and suffix of resulting output table -- how the table will be named --  edges here would mean -- ma_edges , pa_edges etc. except in the case of national tables. national level tables have no prefix" }, force: :cascade do |t|
    t.integer "process_order", default: 1000, null: false
    t.text "table_name", comment: "suffix of the tables to load e.g.  edges would load all tables like *edges.dbf(shp)  -- so tl_2010_42129_edges.dbf .  "
    t.boolean "single_mode", default: true, null: false
    t.boolean "load", default: true, null: false, comment: "Whether or not to load the table.  For states and zcta5 (you may just want to download states10, zcta510 nationwide file manually) load your own into a single table that inherits from tiger.states, tiger.zcta5.  You'll get improved performance for some geocoding cases."
    t.boolean "level_county", default: false, null: false
    t.boolean "level_state", default: false, null: false
    t.boolean "level_nation", default: false, null: false, comment: "These are tables that contain all data for the whole US so there is just a single file"
    t.text "post_load_process"
    t.boolean "single_geom_mode", default: false
    t.string "insert_mode", limit: 1, default: "c", null: false
    t.text "pre_load_process"
    t.text "columns_exclude", comment: "List of columns to exclude as an array. This is excluded from both input table and output table and rest of columns remaining are assumed to be in same order in both tables. gid, geoid,cpi,suffix1ce are excluded if no columns are specified.", array: true
    t.text "website_root_override", comment: "Path to use for wget instead of that specified in year table.  Needed currently for zcta where they release that only for 2000 and 2010"
  end

  create_table "loader_platform", primary_key: "os", id: { type: :string, limit: 50 }, force: :cascade do |t|
    t.text "declare_sect"
    t.text "pgbin"
    t.text "wget"
    t.text "unzip_command"
    t.text "psql"
    t.text "path_sep"
    t.text "loader"
    t.text "environ_set_command"
    t.text "county_process_command"
  end

  create_table "loader_variables", primary_key: "tiger_year", id: { type: :string, limit: 4 }, force: :cascade do |t|
    t.text "website_root"
    t.text "staging_fold"
    t.text "data_schema"
    t.text "staging_schema"
  end

  create_table "pagc_gaz", id: :serial, force: :cascade do |t|
    t.integer "seq"
    t.text "word"
    t.text "stdword"
    t.integer "token"
    t.boolean "is_custom", default: true, null: false
  end

  create_table "pagc_lex", id: :serial, force: :cascade do |t|
    t.integer "seq"
    t.text "word"
    t.text "stdword"
    t.integer "token"
    t.boolean "is_custom", default: true, null: false
  end

  create_table "pagc_rules", id: :serial, force: :cascade do |t|
    t.text "rule"
    t.boolean "is_custom", default: true
  end

  create_table "place", primary_key: "plcidfp", id: { type: :string, limit: 7 }, force: :cascade do |t|
    t.serial "gid", null: false
    t.string "statefp", limit: 2
    t.string "placefp", limit: 5
    t.string "placens", limit: 8
    t.string "name", limit: 100
    t.string "namelsad", limit: 100
    t.string "lsad", limit: 2
    t.string "classfp", limit: 2
    t.string "cpi", limit: 1
    t.string "pcicbsa", limit: 1
    t.string "pcinecta", limit: 1
    t.string "mtfcc", limit: 5
    t.string "funcstat", limit: 1
    t.bigint "aland"
    t.bigint "awater"
    t.string "intptlat", limit: 11
    t.string "intptlon", limit: 12
    t.geometry "the_geom", limit: {:srid=>4269, :type=>"multi_polygon"}
    t.index ["the_geom"], name: "tiger_place_the_geom_gist", using: :gist
    t.check_constraint "geometrytype(the_geom) = 'MULTIPOLYGON'::text OR the_geom IS NULL", name: "enforce_geotype_the_geom"
    t.check_constraint "st_ndims(the_geom) = 2", name: "enforce_dims_the_geom"
    t.check_constraint "st_srid(the_geom) = 4269", name: "enforce_srid_the_geom"
    t.unique_constraint ["gid"], name: "uidx_tiger_place_gid"
  end

  create_table "place_lookup", primary_key: ["st_code", "pl_code"], force: :cascade do |t|
    t.integer "st_code", null: false
    t.string "state", limit: 2
    t.integer "pl_code", null: false
    t.string "name", limit: 90
    t.index "soundex((name)::text)", name: "place_lookup_name_idx"
    t.index ["state"], name: "place_lookup_state_idx"
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

  create_table "secondary_unit_lookup", primary_key: "name", id: { type: :string, limit: 20 }, force: :cascade do |t|
    t.string "abbrev", limit: 5
    t.index ["abbrev"], name: "secondary_unit_lookup_abbrev_idx"
  end

  create_table "state", primary_key: "statefp", id: { type: :string, limit: 2 }, force: :cascade do |t|
    t.serial "gid", null: false
    t.string "region", limit: 2
    t.string "division", limit: 2
    t.string "statens", limit: 8
    t.string "stusps", limit: 2, null: false
    t.string "name", limit: 100
    t.string "lsad", limit: 2
    t.string "mtfcc", limit: 5
    t.string "funcstat", limit: 1
    t.bigint "aland"
    t.bigint "awater"
    t.string "intptlat", limit: 11
    t.string "intptlon", limit: 12
    t.geometry "the_geom", limit: {:srid=>4269, :type=>"multi_polygon"}
    t.index ["the_geom"], name: "idx_tiger_state_the_geom_gist", using: :gist
    t.check_constraint "geometrytype(the_geom) = 'MULTIPOLYGON'::text OR the_geom IS NULL", name: "enforce_geotype_the_geom"
    t.check_constraint "st_ndims(the_geom) = 2", name: "enforce_dims_the_geom"
    t.check_constraint "st_srid(the_geom) = 4269", name: "enforce_srid_the_geom"
    t.unique_constraint ["gid"], name: "uidx_tiger_state_gid"
    t.unique_constraint ["stusps"], name: "uidx_tiger_state_stusps"
  end

  create_table "state_lookup", primary_key: "st_code", id: :integer, default: nil, force: :cascade do |t|
    t.string "name", limit: 40
    t.string "abbrev", limit: 3
    t.string "statefp", limit: 2

    t.unique_constraint ["abbrev"], name: "state_lookup_abbrev_key"
    t.unique_constraint ["name"], name: "state_lookup_name_key"
    t.unique_constraint ["statefp"], name: "state_lookup_statefp_key"
  end

  create_table "street_type_lookup", primary_key: "name", id: { type: :string, limit: 50 }, force: :cascade do |t|
    t.string "abbrev", limit: 50
    t.boolean "is_hw", default: false, null: false
    t.index ["abbrev"], name: "street_type_lookup_abbrev_idx"
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

  create_table "tabblock", primary_key: "tabblock_id", id: { type: :string, limit: 16 }, force: :cascade do |t|
    t.serial "gid", null: false
    t.string "statefp", limit: 2
    t.string "countyfp", limit: 3
    t.string "tractce", limit: 6
    t.string "blockce", limit: 4
    t.string "name", limit: 20
    t.string "mtfcc", limit: 5
    t.string "ur", limit: 1
    t.string "uace", limit: 5
    t.string "funcstat", limit: 1
    t.float "aland"
    t.float "awater"
    t.string "intptlat", limit: 11
    t.string "intptlon", limit: 12
    t.geometry "the_geom", limit: {:srid=>4269, :type=>"multi_polygon"}
    t.check_constraint "geometrytype(the_geom) = 'MULTIPOLYGON'::text OR the_geom IS NULL", name: "enforce_geotype_geom"
    t.check_constraint "st_ndims(the_geom) = 2", name: "enforce_dims_geom"
    t.check_constraint "st_srid(the_geom) = 4269", name: "enforce_srid_geom"
  end

  create_table "tabblock20", primary_key: "geoid", id: { type: :string, limit: 15 }, force: :cascade do |t|
    t.string "statefp", limit: 2
    t.string "countyfp", limit: 3
    t.string "tractce", limit: 6
    t.string "blockce", limit: 4
    t.string "name", limit: 10
    t.string "mtfcc", limit: 5
    t.string "ur", limit: 1
    t.string "uace", limit: 5
    t.string "uatype", limit: 1
    t.string "funcstat", limit: 1
    t.float "aland"
    t.float "awater"
    t.string "intptlat", limit: 11
    t.string "intptlon", limit: 12
    t.geometry "the_geom", limit: {:srid=>4269, :type=>"multi_polygon"}
    t.float "housing"
    t.float "pop"
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

  create_table "tract", primary_key: "tract_id", id: { type: :string, limit: 11 }, force: :cascade do |t|
    t.serial "gid", null: false
    t.string "statefp", limit: 2
    t.string "countyfp", limit: 3
    t.string "tractce", limit: 6
    t.string "name", limit: 7
    t.string "namelsad", limit: 20
    t.string "mtfcc", limit: 5
    t.string "funcstat", limit: 1
    t.float "aland"
    t.float "awater"
    t.string "intptlat", limit: 11
    t.string "intptlon", limit: 12
    t.geometry "the_geom", limit: {:srid=>4269, :type=>"multi_polygon"}
    t.check_constraint "geometrytype(the_geom) = 'MULTIPOLYGON'::text OR the_geom IS NULL", name: "enforce_geotype_geom"
    t.check_constraint "st_ndims(the_geom) = 2", name: "enforce_dims_geom"
    t.check_constraint "st_srid(the_geom) = 4269", name: "enforce_srid_geom"
  end

  create_table "user_access_areas", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "source", default: "subdistricts", null: false
    t.jsonb "subdistrict_ids", default: [], null: false
    t.geography "boundary", limit: {:srid=>4326, :type=>"multi_polygon", :geographic=>true}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["subdistrict_id"], name: "index_users_on_subdistrict_id"
    t.index ["username"], name: "index_users_on_username", unique: true
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
    t.index ["location"], name: "index_water_stations_on_location", using: :gist
    t.index ["station_id"], name: "index_water_stations_on_station_id", unique: true
  end

  create_table "zcta5", primary_key: ["zcta5ce", "statefp"], force: :cascade do |t|
    t.serial "gid", null: false
    t.string "statefp", limit: 2, null: false
    t.string "zcta5ce", limit: 5, null: false
    t.string "classfp", limit: 2
    t.string "mtfcc", limit: 5
    t.string "funcstat", limit: 1
    t.float "aland"
    t.float "awater"
    t.string "intptlat", limit: 11
    t.string "intptlon", limit: 12
    t.string "partflg", limit: 1
    t.geometry "the_geom", limit: {:srid=>4269, :type=>"multi_polygon"}

    t.check_constraint "geometrytype(the_geom) = 'MULTIPOLYGON'::text OR the_geom IS NULL", name: "enforce_geotype_the_geom"
    t.check_constraint "st_ndims(the_geom) = 2", name: "enforce_dims_the_geom"
    t.check_constraint "st_srid(the_geom) = 4269", name: "enforce_srid_the_geom"
    t.unique_constraint ["gid"], name: "uidx_tiger_zcta5_gid"
  end

  create_table "zip_lookup", primary_key: "zip", id: :integer, default: nil, force: :cascade do |t|
    t.integer "st_code"
    t.string "state", limit: 2
    t.integer "co_code"
    t.string "county", limit: 90
    t.integer "cs_code"
    t.string "cousub", limit: 90
    t.integer "pl_code"
    t.string "place", limit: 90
    t.integer "cnt"
  end

  create_table "zip_lookup_all", id: false, force: :cascade do |t|
    t.integer "zip"
    t.integer "st_code"
    t.string "state", limit: 2
    t.integer "co_code"
    t.string "county", limit: 90
    t.integer "cs_code"
    t.string "cousub", limit: 90
    t.integer "pl_code"
    t.string "place", limit: 90
    t.integer "cnt"
  end

  create_table "zip_lookup_base", primary_key: "zip", id: { type: :string, limit: 5 }, force: :cascade do |t|
    t.string "state", limit: 40
    t.string "county", limit: 90
    t.string "city", limit: 90
    t.string "statefp", limit: 2
  end

  create_table "zip_state", primary_key: ["zip", "stusps"], force: :cascade do |t|
    t.string "zip", limit: 5, null: false
    t.string "stusps", limit: 2, null: false
    t.string "statefp", limit: 2
  end

  create_table "zip_state_loc", primary_key: ["zip", "stusps", "place"], force: :cascade do |t|
    t.string "zip", limit: 5, null: false
    t.string "stusps", limit: 2, null: false
    t.string "statefp", limit: 2
    t.string "place", limit: 100, null: false
  end

  add_foreign_key "analysis_records", "subdistricts"
  add_foreign_key "analysis_records", "users"
  add_foreign_key "population_datasets", "subdistricts"
  add_foreign_key "population_datasets", "users"
  add_foreign_key "subdistricts", "provinces"
  add_foreign_key "user_access_areas", "users"
  add_foreign_key "users", "subdistricts"
end
