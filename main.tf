# TODO shared backend
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

variable "name" { type = string }

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.name
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2a", "us-east-2b", "us-east-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_ipv6 = true

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 18.0"

  cluster_name                    = var.name
  cluster_version                 = "1.22"
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        { namespace = "default" },
      ]
    }
    kube-system = {
      name = "kube-system"
      selectors = [
        { namespace = "kube-system" },
      ]
    }
  }
}

resource "aws_iam_policy" "alb_policy" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = file("./alb_policy.json")
}

resource "aws_iam_role" "alb_role" {
  name = "AmazonEKSLoadBalancerControllerRole"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${module.eks.oidc_provider}"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "${module.eks.oidc_provider}:aud": "sts.amazonaws.com",
            "${module.eks.oidc_provider}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "alb_role_attachment" {
  role       = aws_iam_role.alb_role.name
  policy_arn = aws_iam_policy.alb_policy.arn
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "cluster-${module.eks.cluster_id}-db-access"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = -1
      to_port                  = -1
      protocol                 = -1
      source_security_group_id = module.eks.cluster_primary_security_group_id
    },
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = -1
      to_port     = -1
      protocol    = -1
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

module "db" {
  source  = "terraform-aws-modules/rds/aws"

  identifier = var.name

  family = "postgres14"
  engine            = "postgres"
  engine_version    = "14.2"
  instance_class    = "db.t3.micro"
  allocated_storage = 5

  db_name  = "infra"
  username = "infra"

  monitoring_interval = "30"
  monitoring_role_name = "RDSMonitoringRole"
  create_monitoring_role = true

  create_db_subnet_group = true
  subnet_ids = module.vpc.private_subnets
  vpc_security_group_ids = [module.security_group.security_group_id]

  deletion_protection = false
}
