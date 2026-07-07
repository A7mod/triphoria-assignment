terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = var.aws_region
  access_key                  = "AKIAFAKEFAKEFAKEFAKE"
  secret_key                  = "fakeSecretKeyDoesNotNeedToBeRealAtAll123"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "network" {
  source = "../../modules/network"

  environment = var.environment
}

module "rds" {
  source = "../../modules/rds"

  environment             = var.environment
  vpc_id                  = module.network.vpc_id
  private_subnet_ids      = module.network.private_subnet_ids
  rds_sg_id               = module.network.rds_sg_id
  db_password             = var.db_password
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  backup_retention_period = 1
  deletion_protection     = false
  multi_az                = false
}

module "ecs" {
  source = "../../modules/ecs"

  environment        = var.environment
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  alb_sg_id          = module.network.alb_sg_id
  ecs_sg_id          = module.network.ecs_sg_id
  container_image    = "nginx:latest"
  container_port     = 80
  task_cpu           = "256"
  task_memory        = "512"
  desired_count      = 1
}
