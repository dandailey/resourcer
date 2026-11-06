# frozen_string_literal: true

require "resourcer"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:accounts) { |t| t.string :name }

  create_table :companies do |t|
    t.string :name
    t.string :kind
    t.integer :account_id
  end

  create_table :orders do |t|
    t.integer :company_id
    t.integer :total
  end

  create_table(:events, id: false) { |t| t.string :label }
  create_table(:gadgets) { |t| t.integer :company_id }
end

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

def count_queries
  count = 0
  counter = ->(_name, _start, _finish, _id, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
  ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
  count
end
