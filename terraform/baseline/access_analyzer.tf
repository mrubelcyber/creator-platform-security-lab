# External access analyzer (free). Unused/internal access analyzers are paid - not used.
resource "aws_accessanalyzer_analyzer" "external" {
  analyzer_name = local.analyzer_name
  type          = "ACCOUNT"
  tags          = { Name = local.analyzer_name }
}
