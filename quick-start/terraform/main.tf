# -----------------------------------------------------------------------------
# Hashistack + Fermyon Platform versions
# -----------------------------------------------------------------------------

locals {
  nomad_version    = "1.3.1"
  nomad_checksum   = "d16dcea9fdfab3846e749307e117e33a07f0d8678cf28cc088637055e34e5b37"

  consul_version   = "1.12.0"
  consul_checksum  = "109e2077236cae4560b2fa3dce7974ef58d6a7093d72494614d875e5c86e3b2c"

  vault_version    = "1.10.3"
  vault_checksum   = "c99aeefd30dbeb406bfbd7c80171242860747b3bf9fa377e7a9ec38531727f31"

  traefik_version  = "v2.6.6"
  traefik_checksum = "cf4afc3f4bff687fccf85cce1cb0f46b40c9f81c2637580eda189abfee0cf55b"

  bindle_version   = "v0.8.0"
  bindle_checksum  = "26f68ab5a03c7e6f0c8b83fb199ca77244c834f25247b9a62312eb7a89dba93c"

  spin_version     = "v0.2.0"
  spin_checksum    = "f5c25a7f754ef46dfc4b2361d6f34d40564768a60d7bc0d183dc26fe1bdcfae0"

  hippo_version    = "v0.11.0"
  hippo_checksum   = "d195fac576efe656e69678f5f78b2aa8fdb944f930b812532664aa042cd6df00"
}

# -----------------------------------------------------------------------------
# AMI using Canonical's Ubuntu AMD64 offering
# -----------------------------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# -----------------------------------------------------------------------------
# Default VPC
# -----------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

# -----------------------------------------------------------------------------
# Elastic IP to persist through instance restarts and serve as a known value
# for filling out DNS via chosen host, eg 44.194.137.14.sslip.io
# -----------------------------------------------------------------------------

resource "aws_eip" "lb" {
  vpc = true

  tags = {
    Name = "${var.instance_name}-eip"
  }
}

resource "aws_eip_association" "lb" {
  instance_id   = aws_instance.ec2.id
  allocation_id = aws_eip.lb.id

  depends_on = [
    aws_eip.lb,
    aws_instance.ec2
  ]
}

# -----------------------------------------------------------------------------
# EC2 config
# -----------------------------------------------------------------------------

resource "aws_instance" "ec2" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.ec2_ssh_key_pair.key_name

  provisioner "file" {
    source      = "${path.module}/ec2_assets/"
    destination = "/home/ubuntu"

    connection {
      host        = self.public_ip
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.ec2_ssh_key.private_key_pem
    }
  }

  user_data = templatefile("${path.module}/scripts/user-data.sh",
    {
      dns_zone         = "${aws_eip.lb.public_ip}.${var.dns_host}",
      letsencrypt_env  = var.letsencrypt_env,
      nomad_version    = local.nomad_version,
      nomad_checksum   = local.nomad_checksum,
      consul_version   = local.consul_version,
      consul_checksum  = local.consul_checksum,
      vault_version    = local.vault_version,
      vault_checksum   = local.vault_checksum,
      traefik_version  = local.traefik_version,
      traefik_checksum = local.traefik_checksum,
      bindle_version   = local.bindle_version,
      bindle_checksum  = local.bindle_checksum,
      spin_version     = local.spin_version,
      spin_checksum    = local.spin_checksum,
      hippo_version    = local.hippo_version,
      hippo_checksum   = local.hippo_checksum,
    }
  )

  vpc_security_group_ids = [aws_security_group.ec2.id]

  tags = {
    Name = var.instance_name
  }
}

# -----------------------------------------------------------------------------
# Security group/rules to specify allowed inbound/outbound addresses/ports
# -----------------------------------------------------------------------------

resource "aws_security_group" "ec2" {
  name_prefix = var.instance_name
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${var.instance_name}-security-group"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "allow_ssh_inbound" {
  count       = length(var.allowed_ssh_cidr_blocks) > 0 ? 1 : 0
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = var.allowed_ssh_cidr_blocks

  security_group_id = aws_security_group.ec2.id
}

resource "aws_security_group_rule" "allow_traefik_app_http_inbound" {
  count       = length(var.allowed_inbound_cidr_blocks) > 0 ? 1 : 0
  type        = "ingress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = aws_security_group.ec2.id
}

resource "aws_security_group_rule" "allow_traefik_app_https_inbound" {
  count       = length(var.allowed_inbound_cidr_blocks) > 0 ? 1 : 0
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = aws_security_group.ec2.id
}

resource "aws_security_group_rule" "allow_nomad_api_inbound" {
  count       = var.allow_inbound_http_nomad && length(var.allowed_inbound_cidr_blocks) > 0 ? 1 : 0
  type        = "ingress"
  from_port   = 4646
  to_port     = 4646
  protocol    = "tcp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = aws_security_group.ec2.id
}

resource "aws_security_group_rule" "allow_consul_api_inbound" {
  count       = var.allow_inbound_http_consul && length(var.allowed_inbound_cidr_blocks) > 0 ? 1 : 0
  type        = "ingress"
  from_port   = 8500
  to_port     = 8500
  protocol    = "tcp"
  cidr_blocks = var.allowed_inbound_cidr_blocks

  security_group_id = aws_security_group.ec2.id
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = var.allow_outbound_cidr_blocks

  security_group_id = aws_security_group.ec2.id
}

# -----------------------------------------------------------------------------
# SSH keypair
# -----------------------------------------------------------------------------

resource "tls_private_key" "ec2_ssh_key" {
  algorithm   = "RSA"
  rsa_bits    = "4096"
}

resource "aws_key_pair" "ec2_ssh_key_pair" {
  key_name   = "${var.instance_name}_ssh_key_pair"
  public_key = tls_private_key.ec2_ssh_key.public_key_openssh
}
