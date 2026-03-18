resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = toset(var.azs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[index(var.azs, each.key)]
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public-${each.key}"
  }
}

resource "aws_subnet" "private" {
  for_each = toset(var.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[index(var.azs, each.key)]
  availability_zone = each.key

  tags = {
    Name = "${var.name_prefix}-private-${each.key}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "nat" {
  name        = "${var.name_prefix}-nat-sg"
  description = "Security group for NAT instance"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 프라이빗 서브넷 노드들의 트래픽을 NAT 인스턴스가 포워딩하려면
  # VPC 내부에서 오는 모든 트래픽을 수신할 수 있어야 한다.
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-nat-sg"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "nat" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.nano"
  subnet_id                   = values(aws_subnet.public)[0].id
  associate_public_ip_address = true
  key_name                    = "microlens-key"
  source_dest_check           = false
  vpc_security_group_ids      = var.bastion_security_group_id != "" ? [var.bastion_security_group_id] : [aws_security_group.nat.id]

  # OS 레벨 NAT 설정: IP 포워딩 활성화 + iptables masquerade
  user_data = <<-EOF
    #!/bin/bash
    # set -e 제거: apt-get update가 EC2 첫 부팅 시 네트워크 준비 전에 실행되면
    # 실패하여 스크립트가 중단되고 netfilter-persistent save가 실행되지 않는다.
    # 대신 각 단계를 독립적으로 실행하고 apt는 재시도 루프로 처리한다.

    # sysctl.d 파일 방식은 Ubuntu 22.04에서 99-sysctl.conf(→/etc/sysctl.conf 심링크)가
    # 알파벳 순 로딩에서 나중에 덮어쓸 수 있어 불안정하다.
    # 대신 systemd 서비스로 ip_forward + iptables를 부팅마다 강제 적용한다.
    cat > /etc/systemd/system/nat-setup.service << 'UNIT'
    [Unit]
    Description=NAT ip_forward and iptables MASQUERADE
    After=network.target

    [Service]
    Type=oneshot
    # ip_forward 강제 적용 (sysctl.d 로딩 순서 문제 우회)
    ExecStart=/sbin/sysctl -w net.ipv4.ip_forward=1
    # MASQUERADE 규칙 중복 추가 방지: -C로 존재 확인 후 없을 때만 -A로 추가
    ExecStart=/bin/sh -c 'iptables -t nat -C POSTROUTING -o ens5 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE'
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable nat-setup
    systemctl start nat-setup

    # apt-get update: 첫 부팅 시 네트워크가 늦게 뜨는 경우를 대비해 재시도 루프 사용
    for i in 1 2 3 4 5; do
      DEBIAN_FRONTEND=noninteractive apt-get update -y && break
      sleep $((i * 10))
    done

    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    netfilter-persistent save
  EOF

  tags = {
    Name = "${var.name_prefix}-nat"
  }
}

resource "aws_eip" "nat" {
  instance = aws_instance.nat.id
  domain   = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat.primary_network_interface_id
  }

  tags = {
    Name = "${var.name_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
