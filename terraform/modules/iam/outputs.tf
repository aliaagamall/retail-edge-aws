output "ec2_role_arn" {
  value = aws_iam_role.ec2_app.arn
}

output "ec2_role_name" {
  value = aws_iam_role.ec2_app.name
}

output "ec2_instance_profile_name" {
  value = aws_iam_instance_profile.ec2_app.name
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}