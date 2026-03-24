#include "app/config.hpp"

#include <cstdlib>
#include <stdexcept>

namespace app {

static int parse_int(const char *value, int fallback) {
  if (!value || !*value) {
    return fallback;
  }
  char *end = nullptr;
  long n = std::strtol(value, &end, 10);
  if (end == value || *end != '\0' || n < 1 || n > 65535) {
    return fallback;
  }
  return static_cast<int>(n);
}

Config Config::from_env() {
  Config c;
  if (const char *p = std::getenv("PORT")) {
    c.port = parse_int(p, c.port);
  }
  if (const char *p = std::getenv("DB_PATH")) {
    c.db_path = p;
  }
  if (const char *p = std::getenv("BIND_ADDRESS")) {
    c.bind_address = p;
  }
  return c;
}

} // namespace app
