terraform {
  backend "s3" {
    bucket         = "retailedge-tfstate"
    key            = "retailedge/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "retailedge-tf-lock"
    encrypt        = true
  }
}
