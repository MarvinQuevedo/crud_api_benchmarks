#pragma once

#include <string>

namespace app {

struct Config {
  int port = 18080;
  std::string db_path = "data/app.db";
  std::string bind_address = "0.0.0.0";

  static Config from_env();
};

} // namespace app
