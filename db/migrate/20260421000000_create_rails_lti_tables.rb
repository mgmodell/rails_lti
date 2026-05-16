# frozen_string_literal: true

class CreateRailsLtiTables < ActiveRecord::Migration[7.0]
  def change
    # Platforms – one record per LTI platform (e.g. Canvas, Moodle)
    create_table :rails_lti_platforms do |t|
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

    # Deployments – a specific tool deployment within a platform
    create_table :rails_lti_deployments do |t|
      t.references :platform,
                   null: false,
                   foreign_key: { to_table: :rails_lti_platforms }
      t.string :client_id,     null: false
      t.string :deployment_id, null: false
      t.timestamps
    end
    add_index :rails_lti_deployments, [:platform_id, :deployment_id], unique: true

    # Nonces – used to prevent JWT replay attacks
    create_table :rails_lti_nonces do |t|
      t.string   :value,      null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :rails_lti_nonces, :value, unique: true
    add_index :rails_lti_nonces, :expires_at
  end
end
