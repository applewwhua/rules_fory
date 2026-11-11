"""Smoke test for py_fory_library.

Generated modules mirror the .fdl paths and are imported by their dotted path,
like protobuf's *_pb2 modules; the cross-module reference to the shared message
is rewritten by foryc_wrapper.py.
"""

from example.interfaces.greeter import greeter_fory
from example.interfaces.shared import shared_fory


def main():
    request = shared_fory.SharedRequest(name="fory")
    greeting = greeter_fory.Greeting(text="hello", request=request)

    decoded = greeter_fory.Greeting.from_bytes(greeting.to_bytes())
    assert decoded.text == "hello"
    assert decoded.request.name == "fory"


if __name__ == "__main__":
    main()
