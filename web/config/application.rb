require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Web
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # This app connects to an existing "warehouse" Postgres with many schemas.
    # Keep Rails-owned tables isolated in their own schema (defaults to `web`).
    rails_schema = ENV.fetch("RAILS_APP_SCHEMA", "web")

    # Only dump the Rails-owned schema to db/schema.rb (avoids dumping the whole DB).
    config.active_record.dump_schemas = rails_schema

    # Ensure Rails metadata tables also live in that schema (avoids colliding with
    # any other Rails apps using the same database).
    config.active_record.schema_migrations_table_name = "#{rails_schema}.schema_migrations"
    config.active_record.internal_metadata_table_name = "#{rails_schema}.ar_internal_metadata"

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Ensure custom app directories autoload/eager-load in all environments.
    config.autoload_paths << Rails.root.join("app/queries")
    config.autoload_paths << Rails.root.join("app/services")
    config.eager_load_paths << Rails.root.join("app/queries")
    config.eager_load_paths << Rails.root.join("app/services")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
