#include <iostream>
#include <string>

static int print_help() {
  std::cout << "echo_guard_cli (scaffold)\n"
               "Usage:\n"
               "  echo_guard_cli --version\n";
  return 0;
}

int main(int argc, char** argv) {
  if (argc <= 1) {
    return print_help();
  }

  const std::string arg = argv[1];
  if (arg == "--version") {
    std::cout << "echo-guard 0.0.0 (scaffold)\n";
    return 0;
  }

  return print_help();
}

