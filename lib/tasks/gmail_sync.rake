# frozen_string_literal: true

namespace :gmail do
  namespace :sync do
    desc "Perform sync for a specific user (usage: rake gmail:sync:user[user_id])"
    task :user, [:user_id] => :environment do |_t, args|
      user_id = args[:user_id]
      abort "Please provide a user_id" unless user_id

      user = User.find(user_id)
      puts "Starting sync for user #{user.id} (#{user.email})"

      Gmail::SyncEngine.new(user).sync!
      puts "Sync completed successfully"
    end

    desc "Sync all users"
    task all: :environment do
      count = 0
      User.find_each do |user|
        puts "Syncing user #{user.id} (#{user.email})"
        Gmail::SyncEngine.new(user).sync!
        count += 1
      end
      puts "Synced #{count} users"
    end

    desc "Enqueue sync jobs for all users (polling fallback)"
    task poll: :environment do
      SyncJob.sync_all_users
      puts "Sync jobs enqueued for all users"
    end
  end

  namespace :watch do
    desc "Setup Gmail watch for a specific user (usage: rake gmail:watch:setup[user_id])"
    task :setup, [:user_id] => :environment do |_t, args|
      user_id = args[:user_id]
      abort "Please provide a user_id" unless user_id

      user = User.find(user_id)
      puts "Setting up Gmail watch for user #{user.id} (#{user.email})"

      Gmail::WatchManager.new(user).setup_watch!
      puts "Watch setup completed successfully"
    end

    desc "Stop Gmail watch for a specific user (usage: rake gmail:watch:stop[user_id])"
    task :stop, [:user_id] => :environment do |_t, args|
      user_id = args[:user_id]
      abort "Please provide a user_id" unless user_id

      user = User.find(user_id)
      puts "Stopping Gmail watch for user #{user.id} (#{user.email})"

      Gmail::WatchManager.new(user).stop_watch!
      puts "Watch stopped successfully"
    end

    desc "Renew expiring watches for all users"
    task renew: :environment do
      puts "Renewing expiring watches..."
      Gmail::WatchManager.renew_expiring_watches
      puts "Watch renewal completed"
    end

    desc "Setup watches for all users"
    task setup_all: :environment do
      count = 0
      User.find_each do |user|
        puts "Setting up watch for user #{user.id} (#{user.email})"
        Gmail::WatchManager.new(user).setup_watch!
        count += 1
      end
      puts "Setup watches for #{count} users"
    end
  end
end
