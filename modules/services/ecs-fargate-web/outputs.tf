##
##  Load balancer
##
output "lb_dns_name" {
      value       = aws_lb.main.dns_name
      description = "The domain name of the load balancer"
}

output "lb_dns_zone_id" {
      value       = aws_lb.main.zone_id
      description = "The dns zone ID of load balancer"
}