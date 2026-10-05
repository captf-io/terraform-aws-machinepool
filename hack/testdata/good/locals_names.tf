# Fixture locals. This comment may say timestamp() and uuid(): comments are
# not code. So may a trailing one.
locals {
  note = "plain" # never timestamp() or uuid()

  # A heredoc body may hold lines that look like top-level blocks.
  script = <<-EOT
resource "fixture_thing" "not_a_block" {
}
EOT
}

/*
resource "fixture_thing" "commented_out" {
*/
