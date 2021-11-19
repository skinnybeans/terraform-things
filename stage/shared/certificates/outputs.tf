output "sorcerer_cert_arn" {
  value       = aws_acm_certificate.sorcerer_cert.arn
  description = "ARN of sorcererdecks domain certificate"
}