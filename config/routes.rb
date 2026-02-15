Rails.application.routes.draw do
  # Root
  root "root#index"

  # Webhook
  namespace :webhook do
    post "gmail", to: "gmail#create"
  end

  # API
  namespace :api do
    get "health", to: "health#show"

    # Users
    resources :users, only: [ :index, :create ]
    get "users/:user_id/settings", to: "users#settings"
    put "users/:user_id/settings", to: "users#update_settings"
    get "users/:user_id/labels", to: "users#labels"
    get "users/:user_id/emails", to: "users#emails"

    # Sync & Reset
    post "sync", to: "sync#create"
    post "reset", to: "reset#create"

    # Auth
    post "auth/init", to: "auth#init"

    # Watch
    post "watch", to: "watch#create"
    get "watch/status", to: "watch#status"

    # Briefing
    get "briefing/:user_email", to: "briefing#show", constraints: { user_email: /[^\/]+/ }

    # Debug
    get "emails/:email_id/debug", to: "debug#email_debug"
    get "debug/emails", to: "debug#emails_list"
    post "emails/:email_id/reclassify", to: "debug#reclassify"
  end

  # Admin
  namespace :admin do
    resources :users, only: [ :index ]
    resources :emails, only: [ :index ]
    resources :email_events, only: [ :index ]
    resources :llm_calls, only: [ :index ]
    resources :jobs, only: [ :index ]
    resources :user_labels, only: [ :index ]
    resources :user_settings, only: [ :index ]
    resources :sync_states, only: [ :index ]
  end
end
