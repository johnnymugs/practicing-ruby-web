require 'bundler/capistrano'
require 'whenever/capistrano'

set :whenever_identifier, defer { application }

set :application, "practicing-ruby"
set :repository,  "git@github.com:elm-city-craftworks/practicing-ruby-web.git"

set :scm, :git
set :deploy_to, "/var/rapp/#{application}"

set :user, "git"
set :use_sudo, false

set :deploy_via, :remote_cache

set :branch, "master"
server "practicingruby.com", :app, :web, :db, :primary => true

namespace :deploy do
  task :restart, :roles => :app do
    run "touch #{current_path}/tmp/restart.txt"
  end
end

before 'deploy:update_code' do
  run "sudo god stop practicing_ruby_delayed_job"
end

after 'deploy:update_code' do
  { "database.yml"             => "config/database.yml",
    "secret_token.rb"          => "config/initializers/secret_token.rb",
    "mail_settings.rb"         => "config/initializers/mail_settings.rb",
    "mailchimp_settings.rb"    => "config/initializers/mailchimp_settings.rb",
    "omniauth.rb"              => "config/initializers/omniauth.rb",
    "cache_cooker_settings.rb" => "config/initializers/cache_cooker_settings.rb" }.
  each do |from, to|
    run "ln -nfs #{shared_path}/#{from} #{release_path}/#{to}"
  end
end

after "deploy", "deploy:migrate"
after "deploy", 'deploy:cleanup'

after 'deploy' do
  run  "sudo god load #{release_path}/config/delayed_job.god"
  run  "sudo god start practicing_ruby_delayed_job"
  run_rake "bake:articles"
end

load 'deploy/assets'

desc "Import articles from the server"
namespace :import do
  task :articles do
    file  = "#{application}.#{Time.now.strftime '%Y-%m-%d_%H:%M:%S'}.sql.bz2"
    remote_file = "#{current_path}/#{file}"
    remote_db   = remote_database_config

    run %{pg_dump --clean --no-owner --no-privileges -U#{remote_db['username']}
          -h#{remote_db['host']} -t articles #{remote_db['database']} | bzip2 > #{remote_file}} do |ch, stream, out|
      ch.send_data "#{remote_db['password']}\n" if out =~ /^Password:/
      puts out
    end

    rsync = "rsync #{user}@#{find_servers.first.host}:#{remote_file} tmp"
    puts `#{rsync}`

    local_db = database_config

    load_articles = "bzcat tmp/#{file} | psql -U#{local_db['username']} #{local_db['database']}"
    puts `#{load_articles}`

    run "rm #{remote_file}"
    `rm tmp/#{file}`

    `rake tmp:cache:clear`

    puts "  * Articles Imported"
  end
end

def database_config(db="development")
  YAML::load_file('config/database.yml')[db]
end

def remote_database_config(db="production")
  remote_config = capture("cat #{shared_path}/database.yml")
  YAML::load(remote_config)[db]
end

def run_rake(cmd, options={}, &block)
  command = "cd #{current_release} && /usr/bin/env bundle exec rake #{cmd} RAILS_ENV=#{rails_env}"
  run(command, options, &block)
end
