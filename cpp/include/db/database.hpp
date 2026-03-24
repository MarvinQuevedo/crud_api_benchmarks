#pragma once

#include <memory>
#include <string>

struct sqlite3;

namespace db {

class Database {
public:
  explicit Database(std::string path);
  ~Database();

  Database(const Database &) = delete;
  Database &operator=(const Database &) = delete;
  Database(Database &&) noexcept;
  Database &operator=(Database &&) noexcept;

  sqlite3 *raw() const { return db_; }
  const std::string &path() const { return path_; }

private:
  sqlite3 *db_ = nullptr;
  std::string path_;
};

} // namespace db
