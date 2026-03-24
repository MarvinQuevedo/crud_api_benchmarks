#pragma once

#include <nlohmann/json.hpp>

#include <optional>
#include <string>
#include <vector>

struct sqlite3;

namespace db {

struct Item {
  int64_t id = 0;
  std::string name;
  std::string description;
  int quantity = 0;
  std::string created_at;
  std::string updated_at;
};

nlohmann::json item_to_json(const Item &item);

class ItemRepository {
public:
  explicit ItemRepository(sqlite3 *db) : db_(db) {}

  std::vector<Item> list(int limit, int offset);
  std::optional<Item> get_by_id(int64_t id);
  std::optional<Item> create(const std::string &name, const std::string &description, int quantity);
  bool update(int64_t id, const std::string &name, const std::string &description, int quantity);
  bool remove(int64_t id);
  int64_t count();

private:
  sqlite3 *db_;
};

} // namespace db
