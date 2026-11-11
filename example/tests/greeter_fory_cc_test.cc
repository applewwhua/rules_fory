// Smoke test for cc_fory_library: includes the generated headers by their
// workspace-relative path (protoc style, like "a/b/foo.pb.h") and round-trips
// a message through the Fory C++ runtime.

#include <cstdint>
#include <string>
#include <vector>

#include "example/interfaces/greeter/greeter.fory.h"
#include "example/interfaces/shared/shared.fory.h"

int main()
{
    example::greeter::Greeting greeting;
    greeting.set_text("hello");
    greeting.mutable_request()->set_name("fory");

    ::fory::Result<::std::vector<::uint8_t>, ::fory::Error> encoded = greeting.to_bytes();
    if (!encoded.ok())
    {
        return 1;
    }

    ::fory::Result<example::greeter::Greeting, ::fory::Error> decoded =
        example::greeter::Greeting::from_bytes(encoded.value());
    if (!decoded.ok())
    {
        return 1;
    }
    if (decoded.value().text() != "hello")
    {
        return 2;
    }
    if (!decoded.value().has_request() || decoded.value().request().name() != "fory")
    {
        return 3;
    }

    return 0;
}
