module Ralph
  class Base < ActiveRecord::Base
    self.abstract_class = true
    self.table_name_prefix = "ralph_"

    establish_connection(
      adapter: "sqlite3",
      database: "/Users/mattheworahood/RubymineProjects/ralph/db/ralph.sqlite3",
      pool: 5,
      timeout: 5000,
      flags: SQLite3::Constants::Open::READONLY
    )

    def readonly?
      true
    end
  end
end
