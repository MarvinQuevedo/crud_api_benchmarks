#include "http/server_app.hpp"

#include <httplib.h>

#include "app/config.hpp"
#include "db/database.hpp"
#include "db/item_repository.hpp"

#include <nlohmann/json.hpp>

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

nlohmann::json err(const std::string &message, const std::string &code = "error") {
  return nlohmann::json{{"error", message}, {"code", code}};
}

int parse_query_int(const httplib::Request &req, const char *key, int fallback) {
  if (!req.has_param(key)) {
    return fallback;
  }
  try {
    return std::stoi(req.get_param_value(key));
  } catch (...) {
    return fallback;
  }
}

void send_json(httplib::Response &res, int status, const nlohmann::json &body) {
  res.status = status;
  res.set_content(body.dump(), "application/json; charset=utf-8");
}

} // namespace

namespace http_api {

int run(const app::Config &cfg) {
  db::Database database(cfg.db_path);
  db::ItemRepository items(database.raw());

  httplib::Server svr;

  svr.set_default_headers({{"Server", "api_crud_server/1.0"}});

  svr.Get("/health", [](const httplib::Request &, httplib::Response &res) {
    send_json(res, 200, nlohmann::json{{"status", "ok"}});
  });

  svr.Get("/api/items", [&](const httplib::Request &req, httplib::Response &res) {
    try {
      int limit = parse_query_int(req, "limit", 50);
      int offset = parse_query_int(req, "offset", 0);
      auto rows = items.list(limit, offset);
      nlohmann::json arr = nlohmann::json::array();
      for (const auto &row : rows) {
        arr.push_back(db::item_to_json(row));
      }
      nlohmann::json body{{"items", arr}, {"total", items.count()}};
      send_json(res, 200, body);
    } catch (const std::exception &e) {
      send_json(res, 500, err(e.what(), "internal"));
    }
  });

  svr.Get(R"(/api/items/(\d+))", [&](const httplib::Request &req, httplib::Response &res) {
    try {
      int64_t id = std::stoll(req.matches[1]);
      auto row = items.get_by_id(id);
      if (!row) {
        send_json(res, 404, err("not found", "not_found"));
        return;
      }
      send_json(res, 200, db::item_to_json(*row));
    } catch (const std::exception &e) {
      send_json(res, 500, err(e.what(), "internal"));
    }
  });

  svr.Post("/api/items", [&](const httplib::Request &req, httplib::Response &res) {
    try {
      auto j = nlohmann::json::parse(req.body.empty() ? "{}" : req.body);
      if (!j.contains("name") || !j["name"].is_string()) {
        send_json(res, 400, err("field 'name' (string) is required", "validation"));
        return;
      }
      std::string name = j["name"].get<std::string>();
      std::string description = j.value("description", std::string{});
      int quantity = j.value("quantity", 0);
      if (quantity < 0) {
        send_json(res, 400, err("quantity must be >= 0", "validation"));
        return;
      }
      auto created = items.create(name, description, quantity);
      if (!created) {
        send_json(res, 500, err("create failed", "internal"));
        return;
      }
      send_json(res, 201, db::item_to_json(*created));
    } catch (const nlohmann::json::exception &) {
      send_json(res, 400, err("invalid JSON body", "validation"));
    } catch (const std::exception &e) {
      send_json(res, 500, err(e.what(), "internal"));
    }
  });

  svr.Put(R"(/api/items/(\d+))", [&](const httplib::Request &req, httplib::Response &res) {
    try {
      int64_t id = std::stoll(req.matches[1]);
      auto j = nlohmann::json::parse(req.body.empty() ? "{}" : req.body);
      if (!j.contains("name") || !j["name"].is_string()) {
        send_json(res, 400, err("field 'name' (string) is required", "validation"));
        return;
      }
      std::string name = j["name"].get<std::string>();
      std::string description = j.value("description", std::string{});
      int quantity = j.value("quantity", 0);
      if (quantity < 0) {
        send_json(res, 400, err("quantity must be >= 0", "validation"));
        return;
      }
      if (!items.update(id, name, description, quantity)) {
        send_json(res, 404, err("not found", "not_found"));
        return;
      }
      auto row = items.get_by_id(id);
      send_json(res, 200, db::item_to_json(*row));
    } catch (const nlohmann::json::exception &) {
      send_json(res, 400, err("invalid JSON body", "validation"));
    } catch (const std::exception &e) {
      send_json(res, 500, err(e.what(), "internal"));
    }
  });

  svr.Delete(R"(/api/items/(\d+))", [&](const httplib::Request &req, httplib::Response &res) {
    try {
      int64_t id = std::stoll(req.matches[1]);
      if (!items.remove(id)) {
        send_json(res, 404, err("not found", "not_found"));
        return;
      }
      send_json(res, 200, nlohmann::json{{"deleted", true}, {"id", id}});
    } catch (const std::exception &e) {
      send_json(res, 500, err(e.what(), "internal"));
    }
  });

  std::cout << "Listening on http://" << cfg.bind_address << ":" << cfg.port << "\n";
  std::cout << "Database: " << cfg.db_path << "\n";

  if (!svr.listen(cfg.bind_address, cfg.port)) {
    std::cerr << "Failed to listen on " << cfg.bind_address << ":" << cfg.port
              << " (is the port already in use?)\n";
    return 1;
  }
  return 0;
}

} // namespace http_api
