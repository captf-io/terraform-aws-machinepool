# Fixture: blocks that never belong in a role.
module "child" {
  source = "./child"
}

check "health" {
}

moved {
  from = fixture_thing.a
  to   = fixture_thing.b
}

removed {
  from = fixture_thing.a
}

import {
  to = fixture_thing.a
  id = "a"
}

ephemeral "fixture_secret" "token" {
}
