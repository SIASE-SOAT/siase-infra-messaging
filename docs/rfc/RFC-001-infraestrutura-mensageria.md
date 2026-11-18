# RFC-001 — Infraestrutura de Mensageria do Saga Coreografado

**Status:** Aprovado
**Data:** 2026-11
**Repositório:** siase-infra-messaging

## Resumo

Define os recursos de infraestrutura de mensageria (SQS, DynamoDB, IAM) provisionados pelo Terraform para suportar o Saga Coreografado da Fase 4.

## Recursos Provisionados

### Filas SQS

| Recurso | Nome (prod) | Produtor | Consumidor |
|---|---|---|---|
| Fila principal | `siase-prod-billing-queue` | os-service | billing-service |
| DLQ | `siase-prod-billing-queue-dlq` | — | operação manual |
| Fila principal | `siase-prod-execution-queue` | os-service | execution-service |
| DLQ | `siase-prod-execution-queue-dlq` | — | operação manual |
| Fila principal | `siase-prod-os-eventos` | os-service | auditoria/monitoramento |
| DLQ | `siase-prod-os-eventos-dlq` | — | operação manual |
| Fila principal | `siase-prod-os-updates-queue` | billing-service, execution-service | os-service |
| DLQ | `siase-prod-os-updates-queue-dlq` | — | operação manual |

### Tabelas DynamoDB

| Tabela | Hash Key | Range Key | Uso |
|---|---|---|---|
| `siase-prod-execution-fila` | `osId` | — | Estado em tempo real da fila de execução |
| `siase-prod-os-eventos-historico` | `osId` | `timestampEvento` | Histórico de eventos das OS |

### Policies IAM (IRSA)

| Policy | Serviço | Permissões |
|---|---|---|
| `siase-prod-os-service-messaging` | os-service | SendMessage (billing, execution, os-eventos) + ReceiveMessage/DeleteMessage (os-updates) + DynamoDB (os-eventos-historico) |
| `siase-prod-billing-service-messaging` | billing-service | ReceiveMessage/DeleteMessage (billing) + SendMessage (os-updates) |
| `siase-prod-execution-service-messaging` | execution-service | ReceiveMessage/DeleteMessage (execution) + SendMessage (os-updates) + DynamoDB full (execution-fila) |

## Configurações das Filas

```hcl
visibility_timeout_seconds = 60   # maior que o tempo máximo de processamento
message_retention_seconds  = 1209600  # 14 dias
receive_wait_time_seconds  = 20   # long polling
max_receive_count          = 3    # tentativas antes de ir para DLQ
```

## Outputs Terraform

Após `terraform apply`, os outputs disponíveis são:

```bash
terraform output queue_urls          # URLs das filas → env vars dos serviços
terraform output dynamodb_table_names # Nomes das tabelas → env vars dos serviços
terraform output service_policy_arns  # ARNs das policies → anexar às roles IRSA
```

## Uso das Policies IRSA

Após o apply, anexar cada policy à service account correspondente no EKS:

```bash
aws iam attach-role-policy \
  --role-name <irsa-role-os-service> \
  --policy-arn <arn:aws:iam::ACCOUNT:policy/siase-prod-os-service-messaging>
```

## Ordem de Aplicação

1. `siase-infra-k8s` — cria o cluster EKS e o OIDC provider (necessário para IRSA)
2. `siase-infra-messaging` — cria filas, tabelas e policies
3. Serviços (`siase-os-service`, `siase-billing-service`, `siase-execution-service`) — consomem os outputs via env vars

## Considerações de Segurança

- Cada serviço tem acesso apenas às filas e tabelas que produz/consome (menor privilégio).
- Nenhum serviço tem acesso de escrita à fila que consome (apenas `ReceiveMessage` + `DeleteMessage`).
- Server-side encryption habilitado em todas as tabelas DynamoDB.
- Point-in-time recovery habilitado em `prod` para as tabelas DynamoDB.
