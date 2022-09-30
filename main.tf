data "aws_ami" "this" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-${var.ami_suffix}"]
  }
}

data "aws_route53_zone" "this" {
  name = var.domain
}

locals {
  name                    = module.name.name_prefix
  module_internal_version = module.name.change.latest
  public_dns              = aws_instance.this.public_dns
  site_name               = join(".", [local.name, var.domain])
  tags                    = merge(module.name.tags, { "Name" : local.site_name })

  user_data = templatefile("${path.module}/${var.template}-user-data.sh", {
    s3d_domain    = var.domain
    s3d_name      = local.name
    s3d_setup_ref = var.setup_ref
    s3d_user      = var.user
    s3d_version   = local.module_internal_version
    s3d_zone      = data.aws_route53_zone.this.zone_id
  })
}

module "name" {
  source = "git::https://github.com/s3d-club/terraform-external-data-name-tags?ref=v0.1.0"

  as_pre_prefix = true
  disable_date  = true
  name_prefix   = var.template
  name_segment  = var.setup_ref
  path          = path.module
  tags          = var.tags
}

module "sg_egress" {
  source = "git::https://github.com/s3d-club/terraform-aws-sg_egress_open?ref=v0.1.0"

  cidr        = var.cidrs
  cidr6       = var.cidr6s
  name_prefix = local.name
  tags        = local.tags
  vpc         = var.vpc_id
}

module "sg_ingress" {
  source = "git::https://github.com/s3d-club/terraform-aws-sg_ingress_ssh?ref=v0.1.0"

  cidr        = var.cidrs
  cidr6       = var.cidr6s
  name_prefix = local.name
  tags        = local.tags
  vpc         = var.vpc_id
}

resource "aws_instance" "this" {
  ami                         = coalesce(var.ami, data.aws_ami.this.id)
  associate_public_ip_address = true
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  tags                        = local.tags
  user_data                   = local.user_data
  user_data_replace_on_change = true

  vpc_security_group_ids = [
    module.sg_egress.security_group_id,
    module.sg_ingress.security_group_id,
  ]

  root_block_device {
    tags        = merge(local.tags, { "Name" : local.site_name })
    volume_size = var.volume_size
  }
}

resource "aws_route53_record" "this" {
  depends_on = [aws_instance.this]

  name    = local.name
  records = [coalesce(local.public_dns, "none")]
  ttl     = 60
  type    = "CNAME"
  zone_id = data.aws_route53_zone.this.zone_id
}