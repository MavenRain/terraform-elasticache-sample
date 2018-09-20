variable "subnets" {
  default = ["us-west-2a","us-west-2b","us-west-2c"]
}

provider "aws" {
  region = "us-west-2"
}

resource "aws_vpc" "oni" {
  cidr_block = "192.168.0.0/16"
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.oni.id}"
}

resource "aws_route" "internet_access" {
  route_table_id = "${aws_vpc.oni.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = "${aws_internet_gateway.default.id}"
}

resource "aws_security_group" "default" {
  vpc_id      = "${aws_vpc.oni.id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_subnet" "default" {
  count = "${length(var.subnets)}"
  availability_zone = "${element(var.subnets, count.index)}"
  cidr_block = "192.168.${count.index}.0/24"
  map_public_ip_on_launch = true
  vpc_id = "${aws_vpc.oni.id}"
}

resource "aws_elasticache_subnet_group" "default" {
  name       = "oni-cache-subnet"
  subnet_ids = ["${aws_subnet.default.*.id}"]
}

resource "aws_elasticache_replication_group" "default" {
  replication_group_id          = "oni-rep-group"
  replication_group_description = "Redis cluster for Hashicorp ElastiCache - Oni"

  node_type            = "cache.t2.micro"
  port                 = 6379

  snapshot_retention_limit = 5
  snapshot_window          = "00:00-05:00"

  subnet_group_name          = "${aws_elasticache_subnet_group.default.name}"
  automatic_failover_enabled = true

  cluster_mode {
    replicas_per_node_group = 1
    num_node_groups         = "3"
  }
}

data "aws_ami" "ubuntu-1604" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "ssh_host" {
  ami           = "${data.aws_ami.ubuntu-1604.id}"
  instance_type = "t3.nano"

  subnet_id              = "${element(aws_subnet.default.*.id,0)}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  user_data              = "${file("install.sh")}"
}

output "configuration_endpoint_address" {
  value = "${aws_elasticache_replication_group.default.configuration_endpoint_address}"
}

output "ssh_host" {
  value = "${aws_instance.ssh_host.public_ip}"
}