Rails.application.routes.draw do
  devise_for :users
  resources :users, except: :show
  resource :my_access_area, only: :update
  resource :data_layers, only: :show
  get "map", to: "dashboard#map", as: :map
  get "area_analysis", to: "dashboard#area_analysis", as: :area_analysis
  get "disasters", to: "dashboard#disasters", as: :disasters
  resources :population_imports, only: :create
  resources :population_datasets, only: :destroy
  resources :population_dashboards, only: :show
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
    resources :water_stations, only: :index
    resource :access_area, only: :show
    resources :places, only: :index do
      get :usage, on: :collection
    end
    resources :analysis_records, only: %i[index create]
  end
end
