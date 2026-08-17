module "networking" {
  source = "./modules/networking"

  project_name = var.project_name
  environment  = var.environment
  azs          = ["us-east-1a", "us-east-1b"]
}
