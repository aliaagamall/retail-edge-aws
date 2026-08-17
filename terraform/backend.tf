terraform {
  backend "s3" {
    bucket       = "retailedge-dev-tfstate"
    key          = "terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}