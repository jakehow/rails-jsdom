Rails.application.routes.draw do
  root "pages#home"
  get "second", to: "pages#second"
  get "secret", to: "pages#secret"
  get "greeting", to: "pages#greeting"
  get "now", to: "pages#now"
  get "broken", to: "pages#broken"
  get "forms", to: "pages#forms"
  get "echo", to: "pages#echo"
  get "keys", to: "pages#keys"
  get "framed", to: "pages#framed"
  post "framed", to: "pages#save_step"
  get "styled", to: "pages#styled"
  put "body", to: "pages#body"
  resources :uploads, only: %i[new create]
  resources :messages, only: %i[index create]
  get "login", to: "sessions#new"
  post "login", to: "sessions#create"
  resources :items, only: %i[create destroy]
end
