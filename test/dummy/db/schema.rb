# frozen_string_literal: true

ActiveRecord::Schema[7.1].define do
  create_table :rails_lti_platforms, force: :cascade do |t|
    t.string :issuer,                     null: false
    t.string :client_id,                  null: false
    t.string :oidc_auth_url,              null: false
    t.string :jwks_url,                   null: false
    t.string :token_url,                  null: false
    t.string :registration_access_token
    t.string :registration_client_uri
    t.timestamps
  end
  add_index :rails_lti_platforms, [:issuer, :client_id], unique: true

  create_table :rails_lti_deployments, force: :cascade do |t|
    t.integer :platform_id, null: false
    t.string :client_id,     null: false
    t.string :deployment_id, null: false
    t.timestamps
  end
  add_index :rails_lti_deployments, [:platform_id, :deployment_id], unique: true
  add_foreign_key :rails_lti_deployments, :rails_lti_platforms, column: :platform_id

  create_table :rails_lti_nonces, force: :cascade do |t|
    t.string   :value,      null: false
    t.datetime :expires_at, null: false
    t.timestamps
  end
  add_index :rails_lti_nonces, :value, unique: true
  add_index :rails_lti_nonces, :expires_at
end
