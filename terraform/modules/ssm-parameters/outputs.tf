output "current_image_parameter_name" {
  value = aws_ssm_parameter.current_image.name
}

output "current_image_parameter_arn" {
  value = aws_ssm_parameter.current_image.arn
}