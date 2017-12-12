require "active_support/testing/parallelization"

module ActiveRecord
  module TestDatabases
    ActiveSupport::Testing::Parallelization.after_fork_hook do |i|
      create_and_migrate i
    end

    def self.create_and_migrate(i)
      connection_spec = ActiveRecord::Base.configurations["test"]

      connection_spec["database"] += "-#{i}"
      ActiveRecord::Tasks::DatabaseTasks.create(connection_spec)
      ActiveRecord::Base.establish_connection(connection_spec)
      if ActiveRecord::Migrator.needs_migration?
        old, ENV["VERBOSE"] = ENV["VERBOSE"], "false"
        ActiveRecord::Tasks::DatabaseTasks.migrate
        ENV["VERBOSE"] = old
      end
    end
  end
end
