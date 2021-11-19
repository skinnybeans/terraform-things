terraform {
  backend "s3" {
    bucket = "terraform-state-skinnybeans"
    key = "stage/shared/certificates/terraform.tfstate"
    region = "ap-southeast-2"

    dynamodb_table = "terraform-locks-skinnybeans"
    encrypt = true
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

resource "aws_acm_certificate" "sorcerer_cert" {
  domain_name       = "sorcererdecks.com"
  validation_method = "DNS"

  subject_alternative_names = ["*.sorcererdecks.com"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation_records" {
  for_each = {
    for dvo in aws_acm_certificate.sorcerer_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = "Z2X1N05FLLYU8C"
}

resource "aws_acm_certificate_validation" "sorcerer_cert_validation" {
  certificate_arn         = aws_acm_certificate.sorcerer_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.validation_records : record.fqdn]
}