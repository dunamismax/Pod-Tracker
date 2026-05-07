Rails.application.routes.draw do
  resource :session
  resource :registration, only: %i[new create]
  resource :account, only: %i[show edit update]
  resource :account_deletion, only: %i[new destroy]
  resource :account_export, only: %i[create]
  resource :account_codex_account, only: %i[destroy] do
    post :refresh
    post :logout
  end
  resources :account_codex_logins, only: %i[new create show destroy] do
    post :poll, on: :member
  end
  resources :account_provider_links, only: %i[new create destroy]
  resources :decks, only: %i[index show new create destroy] do
    resource :ai_evaluation, only: :create, controller: "deck_ai_evaluations"
  end
  resource :collection, only: :show
  resources :collection_imports, only: %i[show create]
  resources :collection_cards, only: %i[create update destroy]
  resources :unresolved_entries, only: :update
  resources :matchup_notes
  resources :pods, only: %i[index show new create destroy] do
    resource :ai_evaluation, only: :create, controller: "pod_ai_evaluations"
    resource :share, only: %i[create destroy], controller: "pod_shares"
  end
  resources :game_nights, path: "sessions", only: %i[index show new create destroy] do
    post :seat_pods, on: :member
    patch :pod_results, on: :member
  end
  get "p/:token", to: "public_pods#show", as: :public_pod
  resources :passwords, param: :token

  get "email_verifications/:token", to: "email_verifications#show", as: :email_verification
  post "email_verifications", to: "email_verifications#create", as: :email_verifications

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  get "ready" => "health#readiness", as: :readiness_check

  # PWA: dynamic manifest + service worker rendered from app/views/pwa/.
  # The service worker scope is the site root, so the worker file is served from /.
  get "manifest.json" => "rails/pwa#manifest", as: :pwa_manifest, defaults: { format: :json }
  get "service-worker.js" => "rails/pwa#service_worker", as: :pwa_service_worker, defaults: { format: :js }

  # Public marketing surface — readable without an account.
  get "brackets", to: "public#brackets", as: :brackets
  get "brackets/game-changers", to: "public#game_changers", as: :game_changers
  get "brackets/pregame-template", to: "public#pregame_template", as: :pregame_template
  get "about", to: "public#about", as: :about
  get "privacy", to: "public#privacy", as: :privacy
  get "terms", to: "public#terms", as: :terms
  get "sitemap.xml", to: "public#sitemap", as: :sitemap, defaults: { format: :xml }

  # Authenticated app dashboard — root resolves to it for signed-in users via
  # PublicController#home, which renders the marketing landing for guests.
  get "app", to: "dashboard#show", as: :app_dashboard

  root "public#home"
end
