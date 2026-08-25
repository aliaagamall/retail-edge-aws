terraform {
  backend "s3" {
    bucket       = "retailedge-tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}