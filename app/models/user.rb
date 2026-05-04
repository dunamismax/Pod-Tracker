class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :decks, dependent: :destroy
  has_many :analysis_runs, dependent: :nullify
  has_many :pod_evaluations, dependent: :destroy
  has_many :audit_events, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
