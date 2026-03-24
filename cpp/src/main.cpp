#include "app/config.hpp"
#include "http/server_app.hpp"

#include <iostream>

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  try {
    app::Config cfg = app::Config::from_env();
    return http_api::run(cfg);
  } catch (const std::exception &e) {
    std::cerr << "Fatal: " << e.what() << "\n";
    return 1;
  }
}
