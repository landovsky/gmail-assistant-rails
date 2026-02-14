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

ActiveRecord::Schema[8.1].define(version: 2026_02_14_231227) do
  create_schema "tiger"
  create_schema "topology"

  # These are extensions that must be enabled in order to support this database
  enable_extension "fuzzystrmatch"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "postgis"
  enable_extension "tiger.postgis_tiger_geocoder"
  enable_extension "topology.postgis_topology"

  create_table "public.agent_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error"
    t.text "final_message"
    t.text "gmail_thread_id", null: false
    t.integer "iterations", default: 0
    t.text "profile", null: false
    t.text "status", default: "running", null: false
    t.text "tool_calls_log", default: "[]"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["gmail_thread_id"], name: "index_agent_runs_on_gmail_thread_id"
    t.index ["status"], name: "index_agent_runs_on_status"
    t.index ["user_id"], name: "index_agent_runs_on_user_id"
    t.check_constraint "status = ANY (ARRAY['running'::text, 'completed'::text, 'error'::text, 'max_iterations'::text])", name: "check_status"
  end

  create_table "public.email_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "detail"
    t.text "draft_id"
    t.text "event_type", null: false
    t.text "gmail_thread_id", null: false
    t.text "label_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["event_type"], name: "index_email_events_on_event_type"
    t.index ["user_id", "gmail_thread_id"], name: "index_email_events_on_user_id_and_gmail_thread_id"
    t.index ["user_id"], name: "index_email_events_on_user_id"
    t.check_constraint "event_type = ANY (ARRAY['classified'::text, 'label_added'::text, 'label_removed'::text, 'draft_created'::text, 'draft_trashed'::text, 'draft_reworked'::text, 'sent_detected'::text, 'archived'::text, 'rework_limit_reached'::text, 'waiting_retriaged'::text, 'error'::text])", name: "check_event_type"
  end

  create_table "public.emails", force: :cascade do |t|
    t.datetime "acted_at"
    t.text "classification", null: false
    t.text "confidence", default: "medium"
    t.datetime "created_at", null: false
    t.text "detected_language", default: "cs"
    t.text "draft_id"
    t.datetime "drafted_at"
    t.text "gmail_message_id", null: false
    t.text "gmail_thread_id", null: false
    t.text "last_rework_instruction"
    t.integer "message_count", default: 1
    t.datetime "processed_at", default: -> { "CURRENT_TIMESTAMP" }
    t.text "reasoning"
    t.datetime "received_at"
    t.text "resolved_style", default: "business"
    t.integer "rework_count", default: 0
    t.text "sender_email", null: false
    t.text "sender_name"
    t.text "snippet"
    t.text "status", default: "pending"
    t.text "subject"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.text "vendor_name"
    t.index ["gmail_thread_id"], name: "index_emails_on_gmail_thread_id"
    t.index ["user_id", "classification"], name: "index_emails_on_user_id_and_classification"
    t.index ["user_id", "gmail_thread_id"], name: "index_emails_on_user_id_and_gmail_thread_id", unique: true
    t.index ["user_id", "status"], name: "index_emails_on_user_id_and_status"
    t.index ["user_id"], name: "index_emails_on_user_id"
    t.check_constraint "classification = ANY (ARRAY['needs_response'::text, 'action_required'::text, 'payment_request'::text, 'fyi'::text, 'waiting'::text])", name: "check_classification"
    t.check_constraint "confidence = ANY (ARRAY['high'::text, 'medium'::text, 'low'::text])", name: "check_confidence"
    t.check_constraint "status = ANY (ARRAY['pending'::text, 'drafted'::text, 'rework_requested'::text, 'sent'::text, 'skipped'::text, 'archived'::text])", name: "check_status"
  end

  create_table "public.jobs", force: :cascade do |t|
    t.integer "attempts", default: 0
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.text "job_type", null: false
    t.integer "max_attempts", default: 3
    t.text "payload", default: "{}"
    t.datetime "started_at"
    t.text "status", default: "pending"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["status", "created_at"], name: "index_jobs_on_status_and_created_at"
    t.index ["user_id", "job_type"], name: "index_jobs_on_user_id_and_job_type"
    t.index ["user_id"], name: "index_jobs_on_user_id"
    t.check_constraint "job_type = ANY (ARRAY['sync'::text, 'classify'::text, 'draft'::text, 'cleanup'::text, 'rework'::text, 'manual_draft'::text, 'agent_process'::text])", name: "check_job_type"
    t.check_constraint "status = ANY (ARRAY['pending'::text, 'running'::text, 'completed'::text, 'failed'::text])", name: "check_status"
  end

  create_table "public.llm_calls", force: :cascade do |t|
    t.text "call_type", null: false
    t.integer "completion_tokens", default: 0
    t.datetime "created_at", null: false
    t.text "error"
    t.text "gmail_thread_id"
    t.integer "latency_ms", default: 0
    t.text "model", null: false
    t.integer "prompt_tokens", default: 0
    t.text "response_text"
    t.text "system_prompt"
    t.integer "total_tokens", default: 0
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.text "user_message"
    t.index ["call_type"], name: "index_llm_calls_on_call_type"
    t.index ["created_at"], name: "index_llm_calls_on_created_at"
    t.index ["gmail_thread_id"], name: "index_llm_calls_on_gmail_thread_id"
    t.index ["user_id"], name: "index_llm_calls_on_user_id"
    t.check_constraint "call_type = ANY (ARRAY['classify'::text, 'draft'::text, 'rework'::text, 'context'::text, 'agent'::text])", name: "check_call_type"
  end

  create_table "public.spatial_ref_sys", primary_key: "srid", id: :integer, default: nil, force: :cascade do |t|
    t.string "auth_name", limit: 256
    t.integer "auth_srid"
    t.string "proj4text", limit: 2048
    t.string "srtext", limit: 2048
    t.check_constraint "srid > 0 AND srid <= 998999", name: "spatial_ref_sys_srid_check"
  end

  create_table "public.sync_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "last_history_id", default: "0", null: false
    t.datetime "last_sync_at", default: -> { "CURRENT_TIMESTAMP" }
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.datetime "watch_expiration"
    t.text "watch_resource_id"
    t.index ["user_id"], name: "index_sync_states_on_user_id", unique: true
  end

  create_table "public.user_labels", primary_key: ["user_id", "label_key"], force: :cascade do |t|
    t.text "gmail_label_id", null: false
    t.text "gmail_label_name", null: false
    t.text "label_key", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_user_labels_on_user_id"
  end

  create_table "public.user_settings", primary_key: ["user_id", "setting_key"], force: :cascade do |t|
    t.text "setting_key", null: false
    t.text "setting_value", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_user_settings_on_user_id"
  end

  create_table "public.users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "display_name"
    t.text "email", null: false
    t.boolean "is_active", default: true
    t.datetime "onboarded_at"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "public.agent_runs", "public.users"
  add_foreign_key "public.email_events", "public.users"
  add_foreign_key "public.emails", "public.users"
  add_foreign_key "public.jobs", "public.users"
  add_foreign_key "public.llm_calls", "public.users"
  add_foreign_key "public.sync_states", "public.users"
  add_foreign_key "public.user_labels", "public.users"
  add_foreign_key "public.user_settings", "public.users"

  create_table "tiger.addr", primary_key: "gid", id: :serial, force: :cascade do |t|
    t.string "arid", limit: 22
    t.integer "fromarmid"
    t.string "fromhn", limit: 12
    t.string "fromtyp", limit: 1
    t.string "mtfcc", limit: 5
    t.string "plus4", limit: 4
    t.string "side", limit: 1
    t.string "statefp", limit: 2
    t.bigint "tlid"
    t.integer "toarmid"
    t.string "tohn", limit: 12
    t.string "totyp", limit: 1
    t.string "zip", limit: 5
    t.index ["tlid", "statefp"], name: "idx_tiger_addr_tlid_statefp"
    t.index ["zip"], name: "idx_tiger_addr_zip"
  end

# Could not dump table "addrfeat" because of following StandardError
#   Unknown type 'public.geometry' for column 'the_geom'


# Could not dump table "bg" because of following StandardError
#   Unknown type 'public.geometry' for column 'the_geom'


# Could not dump table "county" because of following StandardError
#   Unknown type 'public.geometry' for column 'the_geom'


  create_table "tiger.county_lookup", primary_key: ["st_code", "co_code"], force: :cascade do |t|
    t.integer "co_code", null: false
    t.string "name", limit: 90
    t.integer "st_code", null: false
    t.string "state", limit: 2
    t.index "public.soundex((name)::text)", name: "county_lookup_name_idx"
    t.index ["state"], name: "county_lookup_state_idx"
  end

  create_table "tiger.countysub_lookup", primary_key: ["st_code", "co_code", "cs_code"], force: :cascade do |t|
    t.integer "co_code", null: false
    t.string "county", limit: 90
    t.integer "cs_code", null: false
    t.string "name", limit: 90
    t.integer "st_code", null: false
    t.string "state", limit: 2
    t.index "public.soundex((name)::text)", name: "countysub_lookup_name_idx"
    t.index ["state"], name: "countysub_lookup_state_idx"
  end

# Could not dump table "cousub" because of following StandardError
#   Unknown type 'public.geometry' for column 'the_geom'


  create_table "tiger.direction_lookup", primary_key: "name", id: { type: :string, limit: 20 }, force: :cascade do |t|
    t.string "abbrev", limit: 3
    t.index ["abbrev"], name: "direction_lookup_abbrev_idx"
  end

# Could not dump table "edges" because of following StandardError
#   Unknown type 'public.geometry' for column 'the_geom'


# Could not dump table "faces" because of following StandardError
#   Unknown type 'public.geometry' for column 'the_geom'


  create_table "tiger.featnames", primary_key: "gid", id: :serial, force: :cascade do |t|
    t.string "fullname", limit: 100
    t.string "linearid", limit: 22
    t.string "mtfcc", limit: 5
    t.string "name", limit: 100
    t.string "paflag", limit: 1
    t.string "predir", limit: 2
    t.string "predirabrv", limit: 15
    t.string "prequal", limit: 2
    t.string "prequalabr", limit: 15
    t.string "pretyp", limit: 3
    t.string "pretypabrv", limit: 50
    t.string "statefp", limit: 2
    t.string "sufdir", limit: 2
    t.string "sufdirabrv", limit: 15
    t.string "sufqual", limit: 2
    t.string "sufqualabr", limit: 15
    t.string "suftyp", limit: 3
    t.string "suftypabrv", limit: 50
    t.bigint "tlid"
    t.index "lower((name)::text)", name: "idx_tiger_featnames_lname"
    t.index "public.soundex((name)::text)", name: "idx_tiger_featnames_snd_name"
    t.index ["tlid", "statefp"], name: "idx_tiger_featnames_tlid_statefp"
  end

  create_table "tiger.geocode_settings", primary_key: "name", id: :text, force: :cascade do |t|
    t.text "category"
    t.text "setting"
    t.text "short_desc"
    t.text "unit"
  end

  create_table "tiger.geocode_settings_default", primary_key: "name", id: :text, force: :cascade do |t|
    t.text "category"
    t.text "setting"
    t.text "short_desc"
    t.text "unit"
  end

  create_table "tiger.loader_lookuptables", primary_key: "lookup_name", id: { type: :text, comment: "This is the table name to inherit from and suffix of resulting output table -- how the table will be named --  edges here would mean -- ma_edges , pa_edges etc. except in the case of national tables. national level tables have no prefix" }, force: :cascade do |t|
    t.text "columns_exclude", comment: "List of columns to exclude as an array. This is excluded from both input table and output table and rest of columns remaining are assumed to be in same order in both tables. gid, geoid,cpi,suffix1ce are excluded if no columns are specified.", array: true
    t.string "insert_mode", limit: 1, default: "c", null: false
    t.boolean "level_county", default: false, null: false
    t.boolean "level_nation", default: false, null: false, comment: "These are tables that contain all data for the whole US so there is just a single file"
    t.boolean "level_state", default: false, null: false
    t.boolean "load", default: true, null: false, comment: "Whether or not to load the table.  For states and zcta5 (you may just want to download states10, zcta510 nationwide file manually) load your own into a single table that inherits from tiger.states, tiger.zcta5.  You'll get improved performance for some geocoding cases."
    t.text "post_load_process"
    t.text "pre_load_process"
    t.integer "process_order", default: 1000, null: false
    t.boolean "single_geom_mode", default: false
    t.boolean "single_mode", default: true, null: false
    t.text "table_name", comment: "suffix of the tables to load e.g.  edges would load all tables like *edges.dbf(shp)  -- so tl_2010_42129_edges.dbf .  "
    t.text "website_root_override", comment: "Path to use for wget instead of that specified in year table.  Needed currently for zcta where they release that only for 2000 and 2010"
  end

  create_table "tiger.loader_platform", primary_key: "os", id: { type: :string, limit: 50 }, force: :cascade do |t|
    t.text "county_process_command"
    t.text "declare_sect"
    t.text "environ_set_command"
    t.text "loader"
    t.text "path_sep"
    t.text "pgbin"
    t.text "psql"
    t.text "unzip_command"
    t.text "wget"
  end

  create_table "tiger.loader_variables", primary_key: "tiger_year", id: { type: :string, limit: 4 }, force: :cascade do |t|
    t.text "data_schema"
    t.text "staging_fold"
    t.text "staging_schema"
    t.text "website_root"
  end

  create_table "tiger.pagc_gaz", id: :serial, force: :cascade do |t|
    t.boolean "is_custom", default: true, null: false
    t.integer "seq"
    t.text "stdword"
    t.integer "token"
    t.text "word"
  end

  create_table "tiger.pagc_lex", id: :serial, force: :cascade do |t|
    t.boolean "is_custom", default: true, null: false
    t.integer "seq"
    t.text "stdword"
    t.integer "token"
    t.text "word"
  end

  create_table "tiger.pagc_rules", id: :serial, force: :cascade do |t|
    t.boolean "is_custom", default: true
    t.text "rule"
  end

# Could not dump table "place" because of following StandardError
#   Unknown type 'public.geometry' for column 'the_geom'


  create_table "tiger.place_lookup", primary_key: ["st_code", "pl_code"], force: :cascade do |t|
    t.string "name", limit: 90
    t.integer "pl_code", null: false
    t.integer "st_code", null: false
    t.string "state", limit: 2
    t.index "public.soundex((name)::text)", name: "place_lookup_name_idx"
    t.index ["state"], name: "place_lookup_state_idx"
  end

  create_table "tiger.secondary_unit_lookup", primary_key: "name", id: { type: :string, limit: 20 }, force: :cascade do |t|
    t.string "abbrev", limit: 5
    t.index ["abbrev"], name: "secondary_unit_lookup_abbrev_idx"
  end

# Could not dump table "state" because of following StandardError
#   Unknown type 'public.geometry' for column 'the_geom'


  create_table "tiger.state_lookup", primary_key: "st_code", id: :integer, default: nil, force: :cascade do |t|
    t.string "abbrev", limit: 3
    t.string "name", limit: 40
    t.string "statefp", limit: 2

    t.unique_constraint ["abbrev"], name: "state_lookup_abbrev_key"
    t.unique_constraint ["name"], name: "state_lookup_name_key"
    t.unique_constraint ["statefp"], name: "state_lookup_statefp_key"
  end

  create_table "tiger.street_type_lookup", primary_key: "name", id: { type: :string, limit: 50 }, force: :cascade do |t|
    t.string "abbrev", limit: 50
    t.boolean "is_hw", default: false, null: false
    t.index ["abbrev"], name: "street_type_lookup_abbrev_idx"
  end

# Could not dump table "tabblock" because of following StandardError
#   Unknown type 'public.geometry' for column 'the_geom'


# Could not dump table "tabblock20" because of following StandardError
#   Unknown type 'public.geometry(MultiPolygon,4269)' for column 'the_geom'


# Could not dump table "tract" because of following StandardError
#   Unknown type 'public.geometry' for column 'the_geom'


# Could not dump table "zcta5" because of following StandardError
#   Unknown type 'public.geometry' for column 'the_geom'


  create_table "tiger.zip_lookup", primary_key: "zip", id: :integer, default: nil, force: :cascade do |t|
    t.integer "cnt"
    t.integer "co_code"
    t.string "county", limit: 90
    t.string "cousub", limit: 90
    t.integer "cs_code"
    t.integer "pl_code"
    t.string "place", limit: 90
    t.integer "st_code"
    t.string "state", limit: 2
  end

  create_table "tiger.zip_lookup_all", id: false, force: :cascade do |t|
    t.integer "cnt"
    t.integer "co_code"
    t.string "county", limit: 90
    t.string "cousub", limit: 90
    t.integer "cs_code"
    t.integer "pl_code"
    t.string "place", limit: 90
    t.integer "st_code"
    t.string "state", limit: 2
    t.integer "zip"
  end

  create_table "tiger.zip_lookup_base", primary_key: "zip", id: { type: :string, limit: 5 }, force: :cascade do |t|
    t.string "city", limit: 90
    t.string "county", limit: 90
    t.string "state", limit: 40
    t.string "statefp", limit: 2
  end

  create_table "tiger.zip_state", primary_key: ["zip", "stusps"], force: :cascade do |t|
    t.string "statefp", limit: 2
    t.string "stusps", limit: 2, null: false
    t.string "zip", limit: 5, null: false
  end

  create_table "tiger.zip_state_loc", primary_key: ["zip", "stusps", "place"], force: :cascade do |t|
    t.string "place", limit: 100, null: false
    t.string "statefp", limit: 2
    t.string "stusps", limit: 2, null: false
    t.string "zip", limit: 5, null: false
  end

  create_table "topology.layer", primary_key: ["topology_id", "layer_id"], force: :cascade do |t|
    t.integer "child_id"
    t.string "feature_column", null: false
    t.integer "feature_type", null: false
    t.integer "layer_id", null: false
    t.integer "level", default: 0, null: false
    t.string "schema_name", null: false
    t.string "table_name", null: false
    t.integer "topology_id", null: false

    t.unique_constraint ["schema_name", "table_name", "feature_column"], name: "layer_schema_name_table_name_feature_column_key"
  end

  create_table "topology.topology", id: :serial, force: :cascade do |t|
    t.boolean "hasz", default: false, null: false
    t.string "name", null: false
    t.float "precision", null: false
    t.integer "srid", null: false

    t.unique_constraint ["name"], name: "topology_name_key"
  end

  add_foreign_key "topology.layer", "topology.topology", name: "layer_topology_id_fkey"
end
