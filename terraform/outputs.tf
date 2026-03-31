output "api_endpoint" {
  value       = "${aws_api_gateway_stage.main.invoke_url}/tasks"
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  value       = aws_cognito_user_pool_client.client.id
}

output "create_task_queue_url" {

  value       = aws_sqs_queue.create_task_q.id
}

output "delete_task_queue_url" {
  value       = aws_sqs_queue.delete_task_q.id
}

# URL of các Dead Letter Queues 
output "create_task_dlq_url" {
  value       = aws_sqs_queue.create_task_dlq.id
}

output "delete_task_dlq_url" {
  value       = aws_sqs_queue.delete_task_dlq.id
}
