# Fixture: functions that make a plan non-deterministic, and a provisioner.
resource "fixture_thing" "functions" {
  a = timestamp()
  b = "${uuid()}"
  c = plantimestamp()
  d = templatestring("x", {})

  provisioner "local-exec" {
    command = "true"
  }
}
