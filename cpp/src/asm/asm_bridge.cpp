#include "app/config.hpp"
#include "http/server_app.hpp"

#include <iostream>
#include <string>

// Called from ARM64 assembly entry (asm/entry.s). Links the same C++ HTTP + SQLite
// stack as api_crud_server without duplicating route logic.
extern "C" int asm_crud_run(const char *bind_addr, int port, const char *db_path) {
  try {
    app::Config cfg;
    cfg.bind_address =
        (bind_addr && bind_addr[0]) ? std::string(bind_addr) : std::string("0.0.0.0");
    cfg.port = port;
    cfg.db_path = (db_path && db_path[0]) ? std::string(db_path) : std::string("data/app.db");
    return http_api::run(cfg);
  } catch (const std::exception &e) {
    std::cerr << "Fatal: " << e.what() << "\n";
    return 1;
  } catch (...) {
    return 1;
  }
}
