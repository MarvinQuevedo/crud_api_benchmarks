#include "db/item_repository.hpp"

#include <sqlite3.h>

#include <nlohmann/json.hpp>

#include <cstring>
#include <stdexcept>

namespace db {

nlohmann::json item_to_json(const Item &item) {
  return nlohmann::json{
      {"id", item.id},
      {"name", item.name},
      {"description", item.description},
      {"quantity", item.quantity},
      {"created_at", item.created_at},
      {"updated_at", item.updated_at},
  };
}

namespace {

Item row_to_item(sqlite3_stmt *stmt) {
  Item it;
  it.id = sqlite3_column_int64(stmt, 0);
  const unsigned char *name = sqlite3_column_text(stmt, 1);
  const unsigned char *desc = sqlite3_column_text(stmt, 2);
  it.name = name ? reinterpret_cast<const char *>(name) : "";
  it.description = desc ? reinterpret_cast<const char *>(desc) : "";
  it.quantity = sqlite3_column_int(stmt, 3);
  const unsigned char *ca = sqlite3_column_text(stmt, 4);
  const unsigned char *ua = sqlite3_column_text(stmt, 5);
  it.created_at = ca ? reinterpret_cast<const char *>(ca) : "";
  it.updated_at = ua ? reinterpret_cast<const char *>(ua) : "";
  return it;
}

void bind_text_or_null(sqlite3_stmt *stmt, int idx, const std::string &s) {
  int rc = sqlite3_bind_text(stmt, idx, s.c_str(), static_cast<int>(s.size()), SQLITE_TRANSIENT);
  if (rc != SQLITE_OK) {
    throw std::runtime_error("sqlite bind text");
  }
}

} // namespace

std::vector<Item> ItemRepository::list(int limit, int offset) {
  if (limit < 1) {
    limit = 50;
  }
  if (limit > 500) {
    limit = 500;
  }
  if (offset < 0) {
    offset = 0;
  }

  sqlite3_stmt *stmt = nullptr;
  const char *sql =
      "SELECT id, name, description, quantity, created_at, updated_at "
      "FROM items ORDER BY id DESC LIMIT ? OFFSET ?;";
  int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
  if (rc != SQLITE_OK) {
    throw std::runtime_error(std::string("sqlite prepare list: ") + sqlite3_errmsg(db_));
  }

  sqlite3_bind_int(stmt, 1, limit);
  sqlite3_bind_int(stmt, 2, offset);

  std::vector<Item> out;
  while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
    out.push_back(row_to_item(stmt));
  }
  if (rc != SQLITE_DONE) {
    sqlite3_finalize(stmt);
    throw std::runtime_error(std::string("sqlite step list: ") + sqlite3_errmsg(db_));
  }
  sqlite3_finalize(stmt);
  return out;
}

std::optional<Item> ItemRepository::get_by_id(int64_t id) {
  sqlite3_stmt *stmt = nullptr;
  const char *sql =
      "SELECT id, name, description, quantity, created_at, updated_at FROM items WHERE id = ?;";
  int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
  if (rc != SQLITE_OK) {
    throw std::runtime_error(std::string("sqlite prepare get: ") + sqlite3_errmsg(db_));
  }
  sqlite3_bind_int64(stmt, 1, id);
  rc = sqlite3_step(stmt);
  if (rc == SQLITE_ROW) {
    Item it = row_to_item(stmt);
    sqlite3_finalize(stmt);
    return it;
  }
  sqlite3_finalize(stmt);
  return std::nullopt;
}

std::optional<Item> ItemRepository::create(const std::string &name, const std::string &description,
                                           int quantity) {
  sqlite3_stmt *stmt = nullptr;
  const char *sql = "INSERT INTO items (name, description, quantity) VALUES (?, ?, ?);";
  int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
  if (rc != SQLITE_OK) {
    throw std::runtime_error(std::string("sqlite prepare insert: ") + sqlite3_errmsg(db_));
  }
  bind_text_or_null(stmt, 1, name);
  bind_text_or_null(stmt, 2, description);
  sqlite3_bind_int(stmt, 3, quantity);
  rc = sqlite3_step(stmt);
  if (rc != SQLITE_DONE) {
    sqlite3_finalize(stmt);
    throw std::runtime_error(std::string("sqlite insert: ") + sqlite3_errmsg(db_));
  }
  sqlite3_finalize(stmt);

  int64_t new_id = sqlite3_last_insert_rowid(db_);
  return get_by_id(new_id);
}

bool ItemRepository::update(int64_t id, const std::string &name, const std::string &description,
                            int quantity) {
  sqlite3_stmt *stmt = nullptr;
  const char *sql =
      "UPDATE items SET name = ?, description = ?, quantity = ?, "
      "updated_at = datetime('now') WHERE id = ?;";
  int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
  if (rc != SQLITE_OK) {
    throw std::runtime_error(std::string("sqlite prepare update: ") + sqlite3_errmsg(db_));
  }
  bind_text_or_null(stmt, 1, name);
  bind_text_or_null(stmt, 2, description);
  sqlite3_bind_int(stmt, 3, quantity);
  sqlite3_bind_int64(stmt, 4, id);
  rc = sqlite3_step(stmt);
  sqlite3_finalize(stmt);
  if (rc != SQLITE_DONE) {
    throw std::runtime_error(std::string("sqlite update: ") + sqlite3_errmsg(db_));
  }
  return sqlite3_changes(db_) > 0;
}

bool ItemRepository::remove(int64_t id) {
  sqlite3_stmt *stmt = nullptr;
  const char *sql = "DELETE FROM items WHERE id = ?;";
  int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
  if (rc != SQLITE_OK) {
    throw std::runtime_error(std::string("sqlite prepare delete: ") + sqlite3_errmsg(db_));
  }
  sqlite3_bind_int64(stmt, 1, id);
  rc = sqlite3_step(stmt);
  sqlite3_finalize(stmt);
  if (rc != SQLITE_DONE) {
    throw std::runtime_error(std::string("sqlite delete: ") + sqlite3_errmsg(db_));
  }
  return sqlite3_changes(db_) > 0;
}

int64_t ItemRepository::count() {
  sqlite3_stmt *stmt = nullptr;
  const char *sql = "SELECT COUNT(*) FROM items;";
  int rc = sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr);
  if (rc != SQLITE_OK) {
    throw std::runtime_error(std::string("sqlite prepare count: ") + sqlite3_errmsg(db_));
  }
  rc = sqlite3_step(stmt);
  int64_t n = 0;
  if (rc == SQLITE_ROW) {
    n = sqlite3_column_int64(stmt, 0);
  }
  sqlite3_finalize(stmt);
  return n;
}

} // namespace db
