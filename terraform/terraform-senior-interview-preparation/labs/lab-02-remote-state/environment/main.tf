# A deliberately trivial resource - the point of this configuration is to prove
# the remote backend (locking, encryption, versioning) works end to end, not to
# build anything elaborate.

resource "random_id" "marker" {
  byte_length = 4
}

resource "aws_ssm_parameter" "marker" {
  name  = "/${var.project_name}/marker"
  type  = "String"
  value = "created-via-remote-state-${random_id.marker.hex}"
}
