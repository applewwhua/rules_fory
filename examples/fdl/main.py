"""Serializes and deserializes the schemas of this package with Apache Fory.

    bazel run //examples/fdl:main_py
"""

from examples_fdl_address import Address
from examples_fdl_person import Person


def make_address() -> Address:
    return Address(street="No.1 Fory Road", city="Hangzhou")


def make_person() -> Person:
    return Person(
        name="Alice",
        age=30,
        emails=["alice@example.com", "alice@apache.org"],
        address=make_address(),
    )


def main() -> int:
    person = make_person()
    print(
        "person: name=%s, age=%s, address=%s / %s"
        % (person.name, person.age, person.address.street, person.address.city)
    )

    data = person.to_bytes()
    print("serialized %d bytes: %s" % (len(data), data.hex()))

    restored = Person.from_bytes(data)
    print(
        "deserialized: name=%s, age=%s, emails=%s, city=%s"
        % (
            restored.name,
            restored.age,
            restored.emails,
            restored.address.city,
        )
    )

    if (
        restored.name != person.name
        or restored.age != person.age
        or list(restored.emails) != list(person.emails)
        or restored.address.street != person.address.street
        or restored.address.city != person.address.city
    ):
        print("round trip mismatch")
        return 1

    print("round trip ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
