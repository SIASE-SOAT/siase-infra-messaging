output "queue_urls" {
  description = "URLs das filas SQS — usar nas env vars dos serviços"
  value       = { for k, q in aws_sqs_queue.main : k => q.url }
}

output "queue_arns" {
  value = { for k, q in aws_sqs_queue.main : k => q.arn }
}

output "dlq_urls" {
  value = { for k, q in aws_sqs_queue.dlq : k => q.url }
}

output "dynamodb_table_names" {
  value = { for k, t in aws_dynamodb_table.tables : k => t.name }
}

output "service_policy_arns" {
  description = "ARNs das policies IAM por serviço — anexar à role IRSA de cada service account no EKS"
  value       = { for k, p in aws_iam_policy.services : k => p.arn }
}
