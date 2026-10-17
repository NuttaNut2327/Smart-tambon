Rails.application.routes.draw do
  devise_for :users
  resources :users, except: :show
  resource :my_access_area, only: :update
  resource :data_layers, only: :show
  get "data_layers/population_villages", to: "data_layers#population_villages", as: :population_villages
  post "data_layers/link_village_boundaries", to: "data_layers#link_village_boundaries", as: :link_village_boundaries
  post "data_layers/consumable_movements", to: "consumable_movements#create", as: :consumable_movements
  get "map", to: "dashboard#map", as: :map
  get "area_analysis", to: "dashboard#area_analysis", as: :area_analysis
  get "general_incidents", to: "dashboard#general_incidents", as: :general_incidents
  get "disasters", to: "dashboard#disasters", as: :disasters
  get "report/:token", to: "public_incident_reports#show", as: :public_incident_report
  post "report/:token", to: "public_incident_reports#create"
  get "report/:token/reverse_geocode", to: "public_incident_reports#reverse_geocode", as: :reverse_geocode_public_incident_report
  get "incidents/notification", to: "incidents#notification", as: :incident_notification
  post "incidents", to: "incidents#create", as: :incidents
  patch "incidents/:id", to: "incidents#update", as: :incident
  delete "incidents/:id", to: "incidents#destroy"
  get "incidents/:id/photos/:photo_id", to: "incidents#photo", as: :incident_photo
  get "incidents/:id/assessment", to: "incidents#assessment", as: :assessment_incident
  post "incidents/:id/calculate_assessment", to: "incidents#calculate_assessment", as: :calculate_incident_assessment
  get "situation_assessment", to: "incidents#standalone_assessment", as: :situation_assessment
  post "situation_assessment/calculate", to: "incidents#calculate_assessment", as: :calculate_situation_assessment
  post "incidents/:id/progress", to: "incidents#add_progress", as: :incident_progress
  post "incidents/:id/assessments", to: "incidents#assess", as: :incident_assessments
  patch "incidents/:id/plans/:version", to: "incidents#update_plan", as: :update_incident_plan
  patch "incidents/:id/activate_plan", to: "incidents#activate_plan", as: :activate_incident_plan
  patch "incidents/:id/acknowledge", to: "incidents#acknowledge", as: :acknowledge_incident
  patch "incidents/:id/promote_to_disaster", to: "incidents#promote_to_disaster", as: :promote_incident_to_disaster
  get "resource_rules", to: "dashboard#resource_rules", as: :resource_rules
  post "resource_rules", to: "resource_rules#create"
  patch "resource_rules/:id", to: "resource_rules#update", as: :resource_rule
  resources :population_imports, only: :create
  resources :population_datasets, only: :destroy
  resources :population_dashboards, only: :show
  resources :imported_datasets do
    resources :records, controller: "imported_dataset_records", only: %i[update destroy]
    resources :versions, controller: "imported_dataset_versions", only: %i[show create update] do
      post :checkpoint, on: :collection
      get :download, on: :member
      post :restore, on: :member
    end
  end
  resources :dataset_import_drafts, only: %i[create destroy] do
    post :manual, on: :collection
    member do
      post :validate
      get :preview
      post :finalize
    end
  end
  get "dataset_templates/:data_type", to: "data_layers#template", as: :dataset_template
  resources :place_imports, only: :create
  resources :cctv_cameras, except: :show
  resources :activities, except: :show do
    patch :acknowledge, on: :member
  end
  get "ai", to: "ai_assistant#index", as: :ai_assistant
  namespace :ai do
    resources :sessions, only: %i[index show create update destroy] do
      resources :messages, only: :create
    end
    resources :snippets, only: %i[index create update destroy] do
      member do
        post :run
        post :summarize
      end
    end
  end
  resource :notification_settings, only: %i[show update] do
    post :test_line
  end
  resources :notification_channels, except: :show do
    post :test, on: :member
    collection do
      post :telegram_chats
      get :signal_groups
    end
  end
  resources :notification_templates, except: :show
  get "notification_tests", to: "notification_tests#show", as: :notification_tests
  post "notification_tests", to: "notification_tests#create"
  post "webhooks/line", to: "webhooks/line#create", as: :line_webhook
  resources :ai_providers, except: :show do
    member do
      post :test
      patch :make_default
    end
  end
  get "settings", to: "settings#index", as: :settings
  resource :system_settings, only: %i[show update] do
    get :status
    get :logo
  end
  resource :organization_settings, only: %i[show update] do
    post :regenerate_public_link
    get "logo/:key", action: :logo, as: :logo
  end
  # News broadcasts (ข่าวประชาสัมพันธ์/เสียงตามสาย): programmes, generated episodes and public media links.
  resources :broadcast_programs, except: :show do
    post :run, on: :member
  end
  resources :broadcasts, only: %i[index show update destroy] do
    member do
      post :regenerate
      post :synthesize
      post :publish
      post :image
      get :audio
      get :status
    end
  end
  get "broadcast_media/:token", to: "broadcast_media#show", as: :broadcast_media
  resources :tts_providers, except: :show do
    member do
      post :test
      patch :make_default
    end
  end
  resources :announcements, except: :show do
    member do
      patch :toggle
      post :acknowledge
    end
  end
  resources :projects, except: :show do
    get "photos/:photo_id", action: :photo, on: :member, as: :photo
  end
  authenticated :user do
    root "dashboard#index", as: :authenticated_root
  end
  devise_scope :user do
    root to: "devise/sessions#new"
  end
  namespace :api do
    get "terrain_tiles/:z/:x/:y", to: "terrain_tiles#show", constraints: { z: /\d+/, x: /\d+/, y: /\d+/ }
    get "terrain_color_tiles/:z/:x/:y", to: "terrain_tiles#color", constraints: { z: /\d+/, x: /\d+/, y: /\d+/ }
    resources :provinces, only: %i[index show] do
      resources :districts, only: %i[index show]
      resources :subdistricts, only: :index
    end
    resources :subdistricts, only: :show do
      get :locate, on: :collection
      get :search, on: :collection
    end
    resources :dynamic_layers, only: :index
    resources :imported_datasets, only: %i[index show]
    resources :water_stations, only: :index
    resources :fire_hotspots, only: :index
    get "weather", to: "weather#show"
    resources :cctv_cameras, only: :index
    resources :activities, only: :index
    resources :projects, only: :index
    resources :pm25_readings, only: :create
    resources :water_level_readings, only: :create
    get "sensors", to: "sensors#index"
    get "sensors/:sensor_type/:sensor_id/readings", to: "sensors#readings", as: :sensor_readings
    resource :access_area, only: :show
    resources :places, only: :index do
      get :usage, on: :collection
    end
    resource :reverse_geocode, only: :show
    resources :analysis_records, only: %i[index create]
  end
end
