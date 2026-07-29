# Contrato HTTP da DeviceLifecycle-API

## Escopo

A `DeviceLifecycle-API` é uma extensão HTTP, somente leitura, do serviço
`DeviceLifecycle`. Ela não consulta diretamente Active Directory, Microsoft
Entra ID, Intune ou Microsoft Graph e não executa ações de quarentena,
restauração ou exclusão.

A fonte autoritativa continua sendo o repositório `DeviceLifecycle`. A API
somente publica o relatório CSV mais recente e o arquivo de log mais recente
produzidos por esse serviço.

Versão atual do contrato: `v1` (`1.0.0`).

## URL base

```text
http://SERVIDOR:8088/api/v1
```

A porta é configurável. O transporte padrão é HTTP para rede interna. Para
tráfego fora de uma rede confiável, publique o serviço atrás de HTTPS.

## Autenticação

Todos os endpoints de dados exigem o cabeçalho:

```http
X-API-Key: SUA-CHAVE
```

`GET /health` não exige autenticação por padrão, mas pode ser protegido com
`HealthRequiresAuthentication = $true`.

A chave deve ter pelo menos 32 caracteres. O instalador gera 32 bytes aleatórios
e os apresenta como 64 caracteres hexadecimais.

## Endpoints

### `GET /api/v1/health`

Retorna a disponibilidade do serviço e das fontes de dados.

Exemplo:

```json
{
  "service": "DeviceLifecycle-API",
  "apiVersion": "1.0.0",
  "extensionOf": "DeviceLifecycle",
  "organizationName": "orgname",
  "readOnly": true,
  "status": "ok",
  "serverTimeUtc": "2026-07-29T16:00:00+00:00",
  "reportAvailable": true,
  "latestLogAvailable": true,
  "latestLogName": "DeviceLifecycle-20260729-021500.log"
}
```

O status `ok` indica que o processo da API está operacional. Consulte
`reportAvailable` e `latestLogAvailable` separadamente para validar as fontes.

### `GET /api/v1/metadata`

Retorna metadados do relatório e do log mais recente, sem transferir seu
conteúdo.

```json
{
  "service": "DeviceLifecycle-API",
  "apiVersion": "1.0.0",
  "extensionOf": "DeviceLifecycle",
  "organizationName": "orgname",
  "readOnly": true,
  "report": {
    "fileName": "DeviceLifecycle-Latest.csv",
    "sizeBytes": 18234,
    "lastModifiedUtc": "2026-07-29T05:15:30+00:00"
  },
  "latestLog": {
    "fileName": "DeviceLifecycle-20260729-021500.log",
    "sizeBytes": 9451,
    "lastModifiedUtc": "2026-07-29T05:15:31+00:00"
  }
}
```

### `GET /api/v1/report.csv`

Retorna o arquivo `DeviceLifecycle-Latest.csv` sem transformação.

Content-Type:

```text
text/csv; charset=utf-8
```

Cabeçalhos adicionais:

- `X-File-Name`
- `X-File-Size`
- `X-File-Last-Modified-Utc`

### `GET /api/v1/report`

Converte o CSV mais recente em JSON.

```json
{
  "service": "DeviceLifecycle-API",
  "apiVersion": "1.0.0",
  "extensionOf": "DeviceLifecycle",
  "organizationName": "orgname",
  "readOnly": true,
  "fileName": "DeviceLifecycle-Latest.csv",
  "sizeBytes": 18234,
  "lastModifiedUtc": "2026-07-29T05:15:30+00:00",
  "recordCount": 128,
  "records": []
}
```

Os objetos de `records` usam os cabeçalhos do CSV como nomes de propriedade.
Os valores permanecem como strings para preservar o conteúdo original.

### `GET /api/v1/log?lines=500`

Retorna as últimas linhas do log mais recente como texto puro.

Parâmetros:

- `lines`: inteiro, mínimo `1`, padrão `500`.
- Limite máximo: valor de `MaxLogLines`, padrão `5000`.

Cabeçalhos adicionais:

- `X-Log-File`
- `X-File-Size`
- `X-File-Last-Modified-Utc`

### `GET /api/v1/log/file`

Retorna o conteúdo completo do log mais recente como texto puro.

## Respostas de erro

Os erros retornam JSON:

```json
{
  "detail": "Descrição do erro"
}
```

| Código | Situação |
|---|---|
| `401` | Cabeçalho `X-API-Key` ausente. |
| `403` | API key inválida. |
| `404` | Relatório, diretório de logs ou log inexistente. |
| `422` | Parâmetro inválido ou CSV não processável. |
| `503` | Não foi possível obter uma leitura estável do arquivo. |

## Cabeçalhos comuns

Todas as respostas incluem:

- `Cache-Control: no-store`
- `X-Content-Type-Options: nosniff`
- `X-DeviceLifecycle-API-Version: 1.0.0`

## Compatibilidade

Mudanças incompatíveis devem usar um novo prefixo, por exemplo `/api/v2`.
Campos adicionais podem ser incluídos em respostas da versão `v1` sem remover
ou renomear os campos existentes.
