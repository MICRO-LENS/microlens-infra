# IAM Group
resource "aws_iam_group" "microlens_group" {
  name = "microlens-group"
}

# Attach AdministratorAccess policy to the group
resource "aws_iam_group_policy_attachment" "admin_access" {
  group      = aws_iam_group.microlens_group.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# IAM User
resource "aws_iam_user" "jina" {
  name = "jina"
}

# Add user to the group
resource "aws_iam_user_group_membership" "jina_membership" {
  user   = aws_iam_user.jina.name
  groups = [aws_iam_group.microlens_group.name]
}

# IAM Access Key for the user
resource "aws_iam_access_key" "jina_key" {
  user = aws_iam_user.jina.name
}

# SSH Key Pair
resource "tls_private_key" "microlens_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "microlens" {
  key_name   = "microlens-key"
  public_key = tls_private_key.microlens_key.public_key_openssh
}

resource "local_file" "microlens_key_pem" {
  content  = tls_private_key.microlens_key.private_key_pem
  filename = "./microlens-key.pem"
}