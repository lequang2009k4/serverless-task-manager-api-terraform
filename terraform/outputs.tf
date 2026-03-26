# --- OUTPUTS ---

output "api_endpoint" {
  value       = "${aws_api_gateway_stage.main.invoke_url}/tasks"
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  value       = aws_cognito_user_pool_client.client.id
}

