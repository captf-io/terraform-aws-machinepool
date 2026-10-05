# Fixture resource: file stem equals the local name.
resource "fixture_thing" "api_load_balancer" {
  for_each = toset(["a"])

  name = each.key
}
