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
  resources :decks, only: %i[index show new create destroy]
  resources :pods, only: %i[index show new create destroy] do
    resource :share, only: %i[create destroy], controller: "pod_shares"
  end
  get "p/:token", to: "public_pods#show", as: :public_pod
  resources :passwords, param: :token

  get "email_verifications/:token", to: "email_verifications#show", as: :email_verification
  post "email_verifications", to: "email_verifications#create", as: :email_verifications

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  get "ready" => "health#readiness", as: :readiness_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "dashboard#show"
end
