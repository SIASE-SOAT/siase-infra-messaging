# Diagramas — siase-infra-messaging

## 1. Topologia de Mensageria do Saga Coreografado

```
                    ┌─────────────────────────────────────────────────────┐
                    │              siase-infra-messaging                  │
                    │                                                     │
  ┌──────────────┐  │  ┌─────────────────────┐  ┌──────────────────────┐ │
  │  os-service  │──┼─►│ siase-prod-billing- │  │ siase-prod-billing-  │ │
  │              │  │  │ queue               │  │ queue-dlq            │ │
  │              │  │  └──────────┬──────────┘  └──────────────────────┘ │
  │              │  │             │ (maxReceiveCount=3)                   │
  │              │  │  ┌──────────▼──────────┐                           │
  │              │  │  │  billing-service    │                           │
  │              │  │  └─────────────────────┘                           │
  │              │  │                                                     │
  │              │  │  ┌─────────────────────┐  ┌──────────────────────┐ │
  │              │──┼─►│ siase-prod-execution│  │ siase-prod-execution-│ │
  │              │  │  │ -queue              │  │ queue-dlq            │ │
  │              │  │  └──────────┬──────────┘  └──────────────────────┘ │
  │              │  │             │                                       │
  │              │  │  ┌──────────▼──────────┐                           │
  │              │  │  │ execution-service   │                           │
  │              │  │  └─────────────────────┘                           │
  │              │  │                                                     │
  │              │  │  ┌─────────────────────┐  ┌──────────────────────┐ │
  │              │──┼─►│ siase-prod-os-      │  │ siase-prod-os-       │ │
  │              │  │  │ eventos             │  │ eventos-dlq          │ │
  │              │  │  └─────────────────────┘  └──────────────────────┘ │
  │              │  │                                                     │
  │              │  │  ┌─────────────────────┐  ┌──────────────────────┐ │
  │              │◄─┼──│ siase-prod-os-      │  │ siase-prod-os-       │ │
  └──────────────┘  │  │ updates-queue       │  │ updates-queue-dlq    │ │
         ▲          │  └──────────▲──────────┘  └──────────────────────┘ │
         │          │             │                                       │
         │          └─────────────┼───────────────────────────────────────┘
         │                        │
  ┌──────┴──────┐        ┌────────┴────────┐
  │  os-service │        │ billing-service │
  │  (consome)  │        │ execution-svc   │
  └─────────────┘        │ (produzem)      │
                         └─────────────────┘
```

## 2. Fluxo de Provisionamento Terraform

```
Operador          Terraform          AWS SQS          AWS DynamoDB       AWS IAM
    │                 │                  │                   │               │
    │ terraform init  │                  │                   │               │
    │────────────────►│                  │                   │               │
    │                 │                  │                   │               │
    │ terraform plan  │                  │                   │               │
    │ -var-file=      │                  │                   │               │
    │ prod.tfvars     │                  │                   │               │
    │────────────────►│                  │                   │               │
    │◄── plan output ─│                  │                   │               │
    │                 │                  │                   │               │
    │ terraform apply │                  │                   │               │
    │────────────────►│                  │                   │               │
    │                 │── cria 4 filas ──►│                   │               │
    │                 │── cria 4 DLQs ───►│                   │               │
    │                 │── configura DLQ ──►│                   │               │
    │                 │   redrive policy  │                   │               │
    │                 │── cria tabelas ───────────────────────►│               │
    │                 │   (execution-fila,│                   │               │
    │                 │    os-eventos-    │                   │               │
    │                 │    historico)     │                   │               │
    │                 │── cria policies ──────────────────────────────────────►│
    │                 │   (os-service,    │                   │               │
    │                 │    billing,       │                   │               │
    │                 │    execution)     │                   │               │
    │◄── outputs ─────│                  │                   │               │
    │  queue_urls     │                  │                   │               │
    │  table_names    │                  │                   │               │
    │  policy_arns    │                  │                   │               │
```

## 3. Fluxo de Mensagem com DLQ (Compensação Visível)

```
Produtor          SQS Fila Principal     Consumer          DLQ
    │                     │                  │               │
    │── SendMessage ──────►│                  │               │
    │                     │                  │               │
    │                     │── ReceiveMessage ►│               │
    │                     │                  │── processa    │
    │                     │                  │   (falha 1)   │
    │                     │◄── (não deleta) ──│               │
    │                     │                  │               │
    │                     │── ReceiveMessage ►│               │
    │                     │  (após visibility │               │
    │                     │   timeout 60s)    │               │
    │                     │                  │── processa    │
    │                     │                  │   (falha 2)   │
    │                     │◄── (não deleta) ──│               │
    │                     │                  │               │
    │                     │── ReceiveMessage ►│               │
    │                     │                  │── processa    │
    │                     │                  │   (falha 3)   │
    │                     │◄── (não deleta) ──│               │
    │                     │                  │               │
    │                     │── move para DLQ ─────────────────►│
    │                     │  (maxReceiveCount=3)              │
    │                     │                  │               │
    │                     │                  │  operação     │
    │                     │                  │  manual /     │
    │                     │                  │  reprocessa   │
```
