"""Round trip test of the generated Python bindings with the pyfory runtime."""

import unittest

from examples_address import Address
from examples_person import Person


class PythonRuntimeTest(unittest.TestCase):
    def test_round_trip(self):
        person = Person(
            name="Alice",
            age=30,
            emails=["alice@example.com"],
            address=Address(street="No.1 Fory Road", city="Hangzhou"),
        )

        data = person.to_bytes()
        self.assertIsInstance(data, bytes)
        self.assertGreater(len(data), 0)

        restored = Person.from_bytes(data)
        self.assertEqual(restored.name, person.name)
        self.assertEqual(restored.age, person.age)
        self.assertEqual(list(restored.emails), list(person.emails))
        self.assertEqual(restored.address.street, person.address.street)
        self.assertEqual(restored.address.city, person.address.city)


if __name__ == "__main__":
    unittest.main()
