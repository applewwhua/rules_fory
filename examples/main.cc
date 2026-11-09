// Serializes and deserializes the schemas of this package with Apache Fory.
//
//   bazel run //examples:main_cc

#include <cstdint>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "examples_address.h"
#include "examples_person.h"

namespace {

std::string ToHex(const std::vector<std::uint8_t> &data) {
  std::ostringstream out;
  out << std::hex << std::setfill('0');
  for (std::uint8_t byte : data) {
    out << std::setw(2) << static_cast<int>(byte);
  }
  return out.str();
}

examples::Address MakeAddress() {
  examples::Address address;
  address.set_street("No.1 Fory Road");
  address.set_city("Hangzhou");
  return address;
}

examples::person::Person MakePerson() {
  examples::person::Person person;
  person.set_name("Alice");
  person.set_age(30);
  person.mutable_emails()->push_back("alice@example.com");
  person.mutable_emails()->push_back("alice@apache.org");
  person.set_address(MakeAddress());
  return person;
}

}  // namespace

int main() {
  const examples::person::Person person = MakePerson();
  std::cout << "person: name=" << person.name() << ", age=" << person.age()
            << ", address=" << person.address().street() << " / "
            << person.address().city() << "\n";

  auto encoded = person.to_bytes();
  if (!encoded.ok()) {
    std::cerr << "serialize failed: " << encoded.error().message() << "\n";
    return 1;
  }
  std::cout << "serialized " << encoded.value().size() << " bytes: "
            << ToHex(encoded.value()) << "\n";

  auto decoded = examples::person::Person::from_bytes(encoded.value());
  if (!decoded.ok()) {
    std::cerr << "deserialize failed: " << decoded.error().message() << "\n";
    return 1;
  }
  const examples::person::Person &restored = decoded.value();
  std::cout << "deserialized: name=" << restored.name()
            << ", age=" << restored.age() << ", emails=" << restored.emails().size()
            << ", city=" << restored.address().city() << "\n";

  if (!(restored == person)) {
    std::cerr << "round trip mismatch\n";
    return 1;
  }
  std::cout << "round trip ok\n";
  return 0;
}
