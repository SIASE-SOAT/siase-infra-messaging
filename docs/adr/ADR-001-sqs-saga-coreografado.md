# ADR-001 — SQS como Backbone do Saga Coreografado

**Status:** Aceito
**Data:** 2025-01
**Repositório:** siase-infra-messaging

## Contexto

A Fase 4 decompõe o monólito em três microsserviços independentes (os-service, billing-service, execution-service). É necessário um mecanismo de comunicação assíncrona que garanta desacoplamento, resiliência e rastreabilidade dos eventos do Saga.

## Decisão

Usar **Amazon SQS** como backbone de mensageria para o Saga Coreografado, com uma fila dedicada por canal de comunicação e uma DLQ (Dead Letter Queue) para cada fila principal.

### Topologia de filas

| Fila | Produtor | Consumidor |
|---|---|---|
| `siase-prod-billing-queue` | os-service | billing-service |
| `siase-prod-execution-queue` | os-service | execution-service |
| `siase-prod-os-eventos` | os-service | monitoramento/auditoria |
| `siase-prod-os-updates-queue` | billing-service, execution-service | os-service |

### Configurações

- **Long polling** (`receive_wait_time_seconds=20`): reduz custo e latência de polling vazio.
- **DLQ com `maxReceiveCount=3`**: mensagem que falha 3 vezes é movida para a DLQ, permitindo análise e reprocessamento manual sem perda de eventos.
- **Retenção de 14 dias**: janela suficiente para diagnóstico e reprocessamento.
- **Visibility timeout de 60s**: maior que o tempo máximo de processamento esperado por mensagem.

## Alternativas Consideradas

| Alternativa | Motivo da Rejeição |
|---|---|
| Amazon SNS + SQS (fan-out) | Complexidade desnecessária — cada evento tem um único consumidor |
| Amazon EventBridge | Custo adicional; latência maior; overkill para o volume do trabalho |
| Kafka (MSK) | Custo elevado de cluster; complexidade operacional desproporcional |
| RabbitMQ | Fora da AWS; requer gerenciamento de cluster |

## Consequências

- **Positivo**: desacoplamento total entre serviços — nenhum serviço conhece o endereço do outro
- **Positivo**: DLQ garante que falhas no Saga sejam visíveis e recuperáveis (essencial para demonstrar compensação)
- **Positivo**: IAM policies por serviço (princípio do menor privilégio) via IRSA no EKS
- **Negativo**: consistência eventual — o estado da OS só é atualizado após o consumo da fila
- **Mitigação**: DynamoDB registra todos os eventos para auditoria e rastreabilidade ponta a ponta
