# =============================================
# APPLICATION LOAD BALANCER FOR CASCADE
# =============================================

# ACM Certificate for HTTPS
resource "aws_acm_certificate" "cascade" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "cascade-cert"
  }
}

# Route53 validation record for ACM certificate
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cascade.domain_validation_options : dvo.domain_name => {
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
  zone_id         = var.hosted_zone_id
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "cascade" {
  certificate_arn         = aws_acm_certificate.cascade.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "cascade-alb-sg"
  description = "Security group for Cascade ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cascade-alb-sg"
  }
}

# Update ECS tasks security group to only allow traffic from ALB
resource "aws_security_group_rule" "ecs_from_alb" {
  type                     = "ingress"
  from_port                = 4000
  to_port                  = 4000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_tasks.id
  description              = "Allow traffic from ALB only"
}

# Application Load Balancer
resource "aws_lb" "cascade" {
  name               = "cascade-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.all.ids

  enable_deletion_protection = false
  enable_http2              = true

  tags = {
    Name = "cascade-alb"
  }
}

# Target Group for ECS tasks
resource "aws_lb_target_group" "cascade" {
  name        = "cascade-tg"
  port        = 4000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200-399"
  }

  deregistration_delay = 30

  tags = {
    Name = "cascade-tg"
  }
}

# HTTP Listener (redirect to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.cascade.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS Listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.cascade.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.cascade.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cascade.arn
  }
}

# Route53 A record pointing to ALB
resource "aws_route53_record" "cascade" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.cascade.dns_name
    zone_id                = aws_lb.cascade.zone_id
    evaluate_target_health = true
  }
}
