# ADR-002 — DynamoDB para Estado de Fila e Histórico de Eventos

**Status:** Aceito
**Data:** 2026-11
**Repositório:** siase-infra-messaging

## Contexto

O Saga Coreografado requer dois tipos de armazenamento NoSQL:

1. **Estado em tempo real da fila de execução** — acesso por chave primária (`osId`), alta frequência de leitura/escrita pelos mecânicos.
2. **Histórico de eventos das OS** — append-only, consultado por `osId` com ordenação temporal.

## Decisão

Usar **Amazon DynamoDB** para ambas as tabelas, provisionadas com `PAY_PER_REQUEST`.

### Tabela `siase-prod-execution-fila`

| Atributo | Tipo | Papel |
|---|---|---|
| `osId` | String | Hash key (PK) |
| `status` | String | NA_FILA / EM_EXECUCAO / FINALIZADA / CANCELADA |
| `enfileiradoEm` | String | Timestamp ISO-8601 |
| `iniciadoEm` | String | Timestamp ISO-8601 |
| `finalizadoEm` | String | Timestamp ISO-8601 |

### Tabela `siase-prod-os-eventos-historico`

| Atributo | Tipo | Papel |
|---|---|---|
| `osId` | String | Hash key |
| `timestampEvento` | Number | Range key (ordenação temporal) |
| `statusAnterior` | String | Estado antes da transição |
| `statusNovo` | String | Estado após a transição |
| `origem` | String | Serviço que gerou o evento |

## Justificativa

- **PAY_PER_REQUEST**: sem provisionamento de capacidade — adequado para a carga variável do trabalho acadêmico.
- **Point-in-time recovery** habilitado em `prod`: proteção contra deleção acidental.
- **Server-side encryption** habilitado: criptografia em repouso sem custo adicional.
- **Acesso O(1) por chave**: padrão ideal para a fila de execução (lookup por `osId`).
- **Append-only para histórico**: DynamoDB é ideal para este padrão — sem updates, apenas inserts.

## Consequências

- **Positivo**: zero custo de cluster, escala automática, integração nativa com IAM/IRSA
- **Positivo**: cumpre o requisito de banco NoSQL por serviço (os-service e execution-service)
- **Negativo**: queries complexas não suportadas nativamente — mitigado pelo padrão de acesso por chave
