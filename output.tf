# --- OUTPUTS ---

output "api_endpoint" {
  description = "URL của API Gateway"
  value       = "${aws_api_gateway_stage.main.invoke_url}/tasks"
}

output "cognito_user_pool_id" {
  description = "ID của User Pool để cấu hình Auth"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  description = "ID của App Client để đăng nhập từ Frontend/Postman"
  value       = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.tasks.name
}
