// Round trip test of the generated C++ bindings with the vendored Fory runtime.

#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#include "examples_fdl_address.h"
#include "examples_fdl_person.h"

namespace {

int Fail(const std::string &message) {
  std::fprintf(stderr, "%s\n", message.c_str());
  return 1;
}

}  // namespace

int main() {
  examples::fdl::Address address;
  address.set_street("No.1 Fory Road");
  address.set_city("Hangzhou");

  examples::fdl::person::Person person;
  person.set_name("Alice");
  person.set_age(30);
  person.mutable_emails()->push_back("alice@example.com");
  person.set_address(address);

  auto encoded = person.to_bytes();
  if (!encoded.ok()) {
    return Fail("serialize failed: " + encoded.error().message());
  }
  if (encoded.value().empty()) {
    return Fail("serialize produced an empty payload");
  }

  auto decoded = examples::fdl::person::Person::from_bytes(encoded.value());
  if (!decoded.ok()) {
    return Fail("deserialize failed: " + decoded.error().message());
  }

  const examples::fdl::person::Person &restored = decoded.value();
  if (!(restored == person)) {
    return Fail("round trip mismatch");
  }
  return 0;
}
