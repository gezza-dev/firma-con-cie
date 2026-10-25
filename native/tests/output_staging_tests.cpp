// SPDX-License-Identifier: BSD-3-Clause
// No middleware or card access: also run against a single-file document portal.
#include "visible_output.h"
#include <iostream>
#include <iterator>

namespace fs = std::filesystem;
static void require(bool value, const char* message) {
 if (!value) throw std::runtime_error(message);
}
static void write(const fs::path& path, const std::string& bytes) {
 std::ofstream out(path, std::ios::binary); out << bytes;
 require(out.good(), "fixture_write_failed");
}
static std::string read(const fs::path& path) {
 std::ifstream in(path, std::ios::binary);
 return {std::istreambuf_iterator<char>(in), {}};
}
int main(int argc, char** argv) {
 fs::path root;
 try {
  const bool portal = argc == 2;
  root = portal ? fs::path(argv[1]).parent_path() :
      fs::temp_directory_path() / ("cie-output-test-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
  if (!portal) fs::create_directory(root);
  const auto destination = portal ? fs::path(argv[1]) : root / "synthetic.pdf";
  require(!fs::exists(destination), "use_a_new_synthetic_destination");
  fs::path pending;
  {
   cie::OutputStaging staging(root, "pdf"); pending = staging.file;
   write(staging.file, "synthetic original");
   require(!staging.publish(destination), "new_file_publish_failed");
   require(read(destination) == "synthetic original", "wrong_new_file_bytes");
   write(staging.file, "must not replace");
   require(bool(staging.publish(destination)), "unconfirmed_replacement_allowed");
   require(read(destination) == "synthetic original", "existing_file_changed");
  }
  require(!fs::exists(pending), "staging_not_cleaned");
  {
   cie::OutputStaging staging(root, "pdf"); staging.prepareReplacement(destination);
   write(staging.file, "synthetic replacement"); write(destination, "concurrent edit");
   require(bool(staging.publish(destination, true)), "concurrent_edit_overwritten");
   require(read(destination) == "concurrent edit", "concurrent_edit_lost");
  }
  {
   cie::OutputStaging staging(root, "pdf"); staging.prepareReplacement(destination);
   write(staging.file, "synthetic replacement");
   require(!staging.publish(destination, true), "confirmed_replacement_failed");
   require(read(destination) == "synthetic replacement", "replacement_bytes_wrong");
  }
  // Aborting an operation must leave the chosen output unchanged.
  { cie::OutputStaging staging(root, "pdf"); write(staging.file, "aborted"); }
  require(read(destination) == "synthetic replacement", "aborted_output_published");
  require(std::distance(fs::directory_iterator(root), fs::directory_iterator{}) == 1, "temporary_files_leaked");
  if (!portal) fs::remove_all(root);
  std::cout << "OUTPUT_STAGING_TESTS_OK\n";
  return 0;
 } catch (const std::exception& error) {
  if (argc != 2 && !root.empty()) { std::error_code ec; fs::remove_all(root, ec); }
  std::cerr << error.what() << '\n'; return 1;
 }
}
