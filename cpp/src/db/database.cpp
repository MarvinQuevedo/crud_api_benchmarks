#include "db/database.hpp"

#include <sqlite3.h>

#include <filesystem>
#include <stdexcept>
#include <utility>

namespace db {

namespace {

void exec_or_throw(sqlite3 *db, const char *sql) {
  char *err = nullptr;
  int rc = sqlite3_exec(db, sql, nullptr, nullptr, &err);
  if (rc != SQLITE_OK) {
    std::string msg = err ? err : sqlite3_errmsg(db);
    sqlite3_free(err);
    throw std::runtime_error("sqlite exec: " + msg);
  }
}

} // namespace

Database::Database(std::string path) : path_(std::move(path)) {
  namespace fs = std::filesystem;
  fs::path p(path_);
  if (p.has_parent_path()) {
    fs::create_directories(p.parent_path());
  }

  int rc = sqlite3_open_v2(
      path_.c_str(),
      &db_,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
      nullptr);
  if (rc != SQLITE_OK) {
    std::string msg = db_ ? sqlite3_errmsg(db_) : "sqlite3_open_v2 failed";
    if (db_) {
      sqlite3_close(db_);
      db_ = nullptr;
    }
    throw std::runtime_error("sqlite open: " + msg);
  }

  sqlite3_busy_timeout(db_, 5000);

  exec_or_throw(db_, R"SQL(
    PRAGMA foreign_keys = ON;
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_items_name ON items(name);
  )SQL");
}

Database::~Database() {
  if (db_) {
    sqlite3_close(db_);
    db_ = nullptr;
  }
}

Database::Database(Database &&other) noexcept : db_(other.db_), path_(std::move(other.path_)) {
  other.db_ = nullptr;
}

Database &Database::operator=(Database &&other) noexcept {
  if (this != &other) {
    if (db_) {
      sqlite3_close(db_);
    }
    db_ = other.db_;
    path_ = std::move(other.path_);
    other.db_ = nullptr;
  }
  return *this;
}

} // namespace db
