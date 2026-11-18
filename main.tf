locals {
  prefix = "siase-${var.environment}"

  # Filas do Saga Coreografado (ver RFC-001 — Contratos de Eventos SQS)
  queues = {
    billing = {
      name        = "${local.prefix}-billing-queue"
      description = "Eventos OS_CRIADA / OS_CANCELADA consumidos pelo billing-service"
    }
    execution = {
      name        = "${local.prefix}-execution-queue"
      description = "Eventos ORCAMENTO_APROVADO / OS_CANCELADA consumidos pelo execution-service"
    }
    os-eventos = {
      name        = "${local.prefix}-os-eventos"
      description = "Eventos de dominio publicados pelo os-service"
    }
    os-updates = {
      name        = "${local.prefix}-os-updates-queue"
      description = "Eventos de atualizacao de status consumidos pelo os-service"
    }
  }

  # Tabelas DynamoDB
  dynamodb_tables = {
    execution-fila = {
      name         = "${local.prefix}-execution-fila"
      hash_key     = "osId"
      range_key    = null
      description  = "Estado da fila de execucao"
      billing_mode = "PAY_PER_REQUEST"
      attributes   = [{ name = "osId", type = "S" }]
    }
    os-eventos-historico = {
      name         = "${local.prefix}-os-eventos-historico"
      hash_key     = "osId"
      range_key    = "timestampEvento"
      description  = "Historico de eventos de dominio das ordens de servico"
      billing_mode = "PAY_PER_REQUEST"
      attributes = [
        { name = "osId", type = "S" },
        { name = "timestampEvento", type = "N" },
      ]
    }
  }
}

# ---------------------------------------------------------------------------
# SQS: uma fila principal + uma DLQ por canal do Saga
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "dlq" {
  for_each = local.queues

  name                      = "${each.value.name}-dlq"
  message_retention_seconds = var.message_retention_seconds

  tags = { Description = "DLQ de ${each.value.name}" }
}

resource "aws_sqs_queue" "main" {
  for_each = local.queues

  name                       = each.value.name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = 20 # long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = { Description = each.value.description }
}

# ---------------------------------------------------------------------------
# DynamoDB
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "tables" {
  for_each = local.dynamodb_tables

  name         = each.value.name
  billing_mode = each.value.billing_mode
  hash_key     = each.value.hash_key
  range_key    = each.value.range_key

  dynamic "attribute" {
    for_each = each.value.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  point_in_time_recovery {
    enabled = var.environment == "prod"
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Description = each.value.description }
}

# ---------------------------------------------------------------------------
# IAM: policies por serviço (para IRSA no EKS da Fase 3)
#
# Mapeamento produtor/consumidor (RFC-001):
#   os-service        produz em billing, execution, os-eventos; consome os-updates
#   billing-service   consome billing; produz em os-updates
#   execution-service consome execution; produz em os-updates
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "os_service" {
  statement {
    sid       = "SqsProduce"
    actions   = ["sqs:SendMessage"]
    resources = [
      aws_sqs_queue.main["billing"].arn,
      aws_sqs_queue.main["execution"].arn,
      aws_sqs_queue.main["os-eventos"].arn,
    ]
  }
  statement {
    sid       = "SqsConsume"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.main["os-updates"].arn]
  }
  statement {
    sid       = "DynamoHistorico"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
    resources = [aws_dynamodb_table.tables["os-eventos-historico"].arn]
  }
}

data "aws_iam_policy_document" "billing_service" {
  statement {
    sid       = "SqsConsume"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.main["billing"].arn]
  }
  statement {
    sid       = "SqsProduce"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.main["os-updates"].arn]
  }
}

data "aws_iam_policy_document" "execution_service" {
  statement {
    sid       = "SqsConsume"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.main["execution"].arn]
  }
  statement {
    sid       = "SqsProduce"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.main["os-updates"].arn]
  }
  statement {
    sid       = "DynamoFila"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:Scan"]
    resources = [aws_dynamodb_table.tables["execution-fila"].arn]
  }
}

resource "aws_iam_policy" "services" {
  for_each = {
    os-service        = data.aws_iam_policy_document.os_service.json
    billing-service   = data.aws_iam_policy_document.billing_service.json
    execution-service = data.aws_iam_policy_document.execution_service.json
  }

  name        = "${local.prefix}-${each.key}-messaging"
  description = "Acesso SQS/DynamoDB do ${each.key} (Fase 4)"
  policy      = each.value
}
