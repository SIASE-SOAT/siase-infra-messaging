# siase-infra-messaging — Fase 4

Infraestrutura de mensageria do Saga Coreografado: filas SQS, tabelas DynamoDB e
policies IAM por microsserviço (para IRSA no EKS criado na Fase 3).

## Recursos criados

| Recurso | Nome (prod) | Uso |
|---|---|---|
| SQS | `siase-prod-billing-queue` | OS_CRIADA / OS_CANCELADA → billing-service |
| SQS | `siase-prod-execution-queue` | ORCAMENTO_APROVADO / OS_CANCELADA → execution-service |
| SQS | `siase-prod-os-eventos` | Eventos de domínio publicados pelo os-service |
| SQS | `siase-prod-os-updates-queue` | Atualizações de status → os-service |
| SQS | `*-dlq` | Dead-letter de cada fila (maxReceiveCount=3) |
| DynamoDB | `siase-prod-execution-fila` | Fila de execução em tempo real (hash key `osId`) |
| DynamoDB | `siase-prod-os-eventos-historico` | Histórico de eventos da OS (`osId` + `timestampEvento`) |
| IAM Policy | `siase-prod-<service>-messaging` | Menor privilégio por serviço (anexar à role IRSA) |

## Produtor/consumidor (RFC-001)

- **os-service**: produz em billing / execution / os-eventos; consome os-updates
- **billing-service**: consome billing; produz em os-updates
- **execution-service**: consome execution; produz em os-updates; usa `execution-fila`

## Uso

```bash
terraform init
terraform plan  -var-file=environments/prod.tfvars
terraform apply -var-file=environments/prod.tfvars
```

Depois, alimentar as env vars dos serviços com `terraform output queue_urls`
e `dynamodb_table_names`, e anexar cada policy (`service_policy_arns`) à role
IRSA da service account correspondente no EKS.

## Decisões

- **Long polling** (`receive_wait_time_seconds=20`) para reduzir custo/latência.
- **DLQ em todas as filas**: mensagem que falha 3x vai para a DLQ — essencial
  para demonstrar o rollback/compensação do Saga no vídeo.
- **DynamoDB PAY_PER_REQUEST**: suficiente para a carga do trabalho; sem
  provisionamento de capacidade.