Rails.application.routes.draw do
  devise_for :users
  resources :users, except: :show
  resource :my_access_area, only: :update
  resource :data_layers, only: :show
  get "map", to: "dashboard#map", as: :map
  get "area_analysis", to: "dashboard#area_analysis", as: :area_analysis
  get "general_incidents", to: "dashboard#general_incidents", as: :general_incidents
  get "disasters", to: "dashboard#disasters", as: :disasters
  get "report/:token", to: "public_incident_reports#show", as: :public_incident_report
  post "report/:token", to: "public_incident_reports#create"
  get "incidents/notification", to: "incidents#notification", as: :incident_notification
  post "incidents", to: "incidents#create", as: :incidents
  patch "incidents/:id", to: "incidents#update", as: :incident
  delete "incidents/:id", to: "incidents#destroy"
  get "incidents/:id/assessment", to: "incidents#assessment", as: :assessment_incident
  post "incidents/:id/calculate_assessment", to: "incidents#calculate_assessment", as: :calculate_incident_assessment
  get "situation_assessment", to: "incidents#standalone_assessment", as: :situation_assessment
  post "situation_assessment/calculate", to: "incidents#calculate_assessment", as: :calculate_situation_assessment
  post "incidents/:id/progress", to: "incidents#add_progress", as: :incident_progress
  post "incidents/:id/assessments", to: "incidents#assess", as: :incident_assessments
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
    resources :versions, controller: "imported_dataset_versions", only: %i[show create] do
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
    resource :access_area, only: :show
    resources :places, only: :index do
      get :usage, on: :collection
    end
    resources :analysis_records, only: %i[index create]
  end
end
