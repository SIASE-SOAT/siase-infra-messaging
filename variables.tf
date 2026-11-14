variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente prod"
  type        = string

  validation {
    condition     = contains(["prod"], var.environment)
    error_message = "environment deve ser prod."
  }
}

variable "message_retention_seconds" {
  description = "Retenção das mensagens nas filas SQS"
  type        = number
  default     = 1209600 # 14 dias
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout padrão das filas (>= tempo máximo de processamento do consumer)"
  type        = number
  default     = 60
}

variable "max_receive_count" {
  description = "Tentativas antes de enviar para a DLQ"
  type        = number
  default     = 3
}
