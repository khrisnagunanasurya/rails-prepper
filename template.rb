# frozen_string_literal: true

# Inspired from: https://raw.githubusercontent.com/excid3/jumpstart/master/template.rb

require "fileutils"
require "shellwords"

# Copied from: https://github.com/mattbrictson/rails-template
# Add this template directory to source_paths so that Thor actions like
# copy_file and template resolve against our source files. If this file was
# invoked remotely via HTTP, that means the files are not present locally.
# In that case, use `git clone` to download them to a local temporary dir.
def add_template_repository_to_source_path
  if __FILE__.match?(%r{\Ahttps?://})
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("rails-prepper-"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      "--quiet",
      "https://github.com/khrisnagunanasurya/rails-prepper.git",
      tempdir,
    ].map(&:shellescape).join(" ")

    if (branch = __FILE__[%r{rails-prepper/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def commit?
  @commit ||= yes? "Initial commit?"
end

def commit_to_git(message:, amend: false)
  return unless commit?

  git :init
  git add: "."
  # git commit will fail if user.email is not configured
  begin
    git commit: (amend ? "--amend" : "-m '#{message}'")
  rescue StandardError => e
    say e.message, :red
  end
end

def add_gems
  gem_group :development, :test do
    gem "bullet", "~> 6.1"
    gem "rspec-rails", "~> 5.0.0"
    gem "rswag-specs"
  end

  gem_group :development do
    gem "better_errors"
    gem "binding_of_caller"
    gem "brakeman", "~> 5.0"
    gem "pry-rails"
    gem "rubocop", require: false
    gem "rubocop-performance", require: false
    gem "rubocop-rails", require: false
    gem "rubocop-rspec", require: false
  end

  gem_group :test do
    gem "database_cleaner-active_record"
    gem "factory_bot_rails"
    gem "faker"
    gem "rspec-sidekiq" if sidekiq?
    gem "shoulda-matchers", "~> 5.0"
    gem "simplecov", require: false
    gem "timecop"
  end

  if api?
    gem "rswag-api"
    gem "rswag-ui"
  end

  if sidekiq?
    gem "sidekiq"
    gem "sidekiq-cron"
  end

  gem "activeadmin" if activeadmin?
  gem "devise", "~> 4.8", ">= 4.8.0" if devise?
  gem "paper_trail" if activeadmin? && devise?
end

def api?
  @api ||= yes? "Need API? (y/n)"
end

def activeadmin?
  @activeadmin ||= yes? "Install ActiveAdmin? (y/n)"
end

def devise?
  @devise ||= yes? "Install Devise? (y/n)"
end

def sidekiq?
  @sidekiq ||= yes? "Do you want to use sidekiq? (y/n)"
end

def activeadmin_setup
  # https://activeadmin.info/0-installation.html#setting-up-active-admin
  return unless activeadmin?

  options = ["--use_webpacker"]
  options.push "--skip-users" unless devise?

  generate "active_admin:install #{options.join ' '}"
end

def bullet_setup
  # https://github.com/flyerhzm/bullet
  generate "bullet:install"

  insert_into_file "spec/rails_helper.rb", after: "RSpec.configure do |config|\n" do
    <<-RUBY

      if Bullet.enable?
        config.before(:each) do
          Bullet.start_request
        end

        config.after(:each) do
          Bullet.perform_out_of_channel_notifications if Bullet.notification?
          Bullet.end_request
        end
      end

    RUBY
  end
end

def database_cleaner_setup
  # https://github.com/DatabaseCleaner/database_cleaner
  copy_file "spec/supports/database_cleaner.rb", force: true

  insert_into_file "spec/rails_helper.rb", "require 'spec/supports/database_cleaner'\n",
                   after: "require 'rspec/rails'\n"
end

def devise_setup
  # https://github.com/heartcombo/devise#starting-with-rails
  return unless devise?

  generate "devise:install"
  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: "development"
  generate "devise User"

  insert_into_file "config/routes.rb", "root to: 'home#index'\n\n", after: "Rails.application.routes.draw do\n"
  insert_into_file "app/views/layouts/application.html.erb", after: "<body>\n" do
    <<-HTML
      <p class="notice"><%= notice %></p>
      <p class="alert"><%= alert %></p>

    HTML
  end

  copy_file "config/initializers/devise.rb", force: true
end

def factory_bot_setup
  # https://github.com/thoughtbot/factory_bot_rails
  copy_file "spec/supports/factory_bot.rb", force: true

  insert_into_file "spec/rails_helper.rb", "require 'spec/supports/factory_bot'\n",
                   after: "require 'rspec/rails'\n"
end

def paper_trail_setup
  # https://github.com/paper-trail-gem/paper_trail
  generate "paper_trail:install [--with-changes]"

  initializer "paper_trail.rb", <<-RUBY

    PaperTrail.config.enabled = true
    PaperTrail.config.has_paper_trail_defaults = {
      on: %i[create update destroy]
    }
    PaperTrail.config.version_limit = 3

  RUBY

  insert_into_file "app/controllers/application_controller.rb",
                   after: "class ApplicationController < ActionController::Base\n" do
    <<-RUBY
      before_action :set_paper_trail_whodunnit

    RUBY
  end

  insert_into_file "spec/rails_helper.rb", "require 'paper_trail/frameworks/rspec'\n",
                   after: "require 'rspec/rails'\n"
end

def pry_rails_setup
  # https://github.com/rweng/pry-rails
  copy_file ".pryrc", force: true
end

def rubocop_setup
  # https://github.com/rubocop/rubocop

  copy_file ".rubocop.yml", force: true
end

def rspec_setup
  # https://github.com/rspec/rspec-rails
  run "rm -rf test"

  generate "rspec:install"
end

def rswag_setup
  # https://github.com/rswag/rswag#getting-started
  return unless api?

  generate "rswag:api:install"
  generate "rswag:ui:install"

  run "RAILS_ENV=test rails g rswag:specs:install"

  run "mv ./config/initializers/rswag-ui.rb ./config/initializers/rswag_ui.rb"
  copy_file "config/initializers/rswag_api.rb", force: true
end

def shoulda_matchers_setup
  # https://github.com/thoughtbot/shoulda-matchers#rspec
  copy_file "spec/supports/shoulda_matchers.rb", force: true

  insert_into_file "spec/rails_helper.rb", "require 'spec/supports/shoulda_matchers'\n",
                   after: "require 'rspec/rails'\n"
end

def simplecov_setup
  # https://github.com/simplecov-ruby/simplecov

  insert_into_file "spec/rails_helper.rb", before: "RSpec.configure do |config|\n" do
    <<-RUBY

      require 'simplecov'
      SimpleCov.start 'rails'

    RUBY
  end

  append_to_file ".gitignore", "\n/coverage/\n"
end

def set_application_name
  environment "config.application_name = Rails.application.class.module_parent_name"
  say "You can change application name inside: ./config/application.rb"
end

def run_setup
  run "spring stop"

  devise_setup
  activeadmin_setup
  rspec_setup
  rubocop_setup
  bullet_setup
  pry_rails_setup
  paper_trail_setup
  shoulda_matchers_setup
  rswag_setup
  factory_bot_setup
  database_cleaner_setup
  simplecov_setup

  copy_file "app/channels/application_cable/connection.rb", force: true
  copy_file "config/cable.yml", force: true
  copy_file "config/puma.rb", force: true
end

def clean_up
  run "rubocop --auto-correct --cache true --format fuubar"
end

def overview
  say
  say "ActiveAdmin installed!", :green if activeadmin?
  say "API tools installed!", :green if api?
  say "Devise installed!", :green if devise?
  say "Sidekiq installed!", :green if sidekiq?
  say
  say "rails-prepper app template successfully applied!", :blue
  say
  say "To get started with your new app:", :green
  say "  cd #{original_app_name}"
  say
  say "  # Update config/database.yml with your database credentials"
  say
  say "  rails db:create db:migrate"
  say "  rails g active_admin:install # Generate admin dashboards"
end

def generate_secret_key
  run "openssl rand -hex 64"
end

def env_setup

end

add_template_repository_to_source_path

activeadmin?
api?
devise?
sidekiq?

add_gems

after_bundle do
  set_application_name
  run_setup
  commit_to_git message: "Initial commit"
  clean_up
  overview
  commit_to_git message: nil, amend: true
end
