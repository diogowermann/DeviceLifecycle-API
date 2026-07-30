# Contrato HTTP da DeviceLifecycle-API

[English](../en/API.md) | [Português](API.md)

## Escopo

O DeviceLifecycle-API é uma extensão HTTP somente leitura do [DeviceLifecycle](https://github.com/diogowermann/DeviceLifecycle). Ele não consulta diretamente Active Directory, Microsoft Entra ID, Microsoft Intune ou Microsoft Graph e não executa ações de quarentena, restauração ou exclusão.

O DeviceLifecycle continua sendo o produtor autoritativo. A API somente publica o relatório CSV e o log mais recentes gerados por esse serviço.

Versão atual do contrato: `v1` (`1.0.0`).

## URL base

```text
http://SERVIDOR:8088/api/v1
```

A porta é configurável. HTTP simples deve ser usado somente em redes internas confiáveis. Use um reverse proxy HTTPS quando o tráfego atravessar uma rede não confiável ou roteada.

## Autenticação

Todos os endpoints de dados exigem:

```http
X-API-Key: SUA-CHAVE
```

`GET /health` não exige autenticação por padrão, mas pode ser protegido com:

```powershell
HealthRequiresAuthentication = $true
```

A chave deve possuir pelo menos 32 caracteres. O instalador gera 32 bytes aleatórios representados como 64 caracteres hexadecimais.

A API diferencia:

- `401 Unauthorized`: o cabeçalho não foi informado;
- `403 Forbidden`: a chave informada é inválida.

## Metadados comuns do serviço

Respostas JSON incluem a identidade do serviço:

```json
{
  "service": "DeviceLifecycle-API",
  "apiVersion": "1.0.0",
  "extensionOf": "DeviceLifecycle",
  "organizationName": "orgname",
  "readOnly": true
}
```

## Endpoints

### `GET /api/v1/health`

Retorna a disponibilidade do processo e das fontes de dados.

A autenticação é opcional e controlada por `HealthRequiresAuthentication`.

Exemplo de resposta:

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

`status: ok` indica que o processo da API está operacional. Verifique `reportAvailable` e `latestLogAvailable` separadamente antes de assumir que as fontes estão disponíveis.

### `GET /api/v1/metadata`

Retorna metadados do relatório atual e do log mais recente sem transferir o conteúdo dos arquivos.

Autenticação: obrigatória.

Exemplo de resposta:

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

Quando uma fonte estiver indisponível, sua propriedade correspondente pode ser `null`.

### `GET /api/v1/report.csv`

Retorna `DeviceLifecycle-Latest.csv` sem transformação.

Autenticação: obrigatória.

Content-Type:

```text
text/csv; charset=utf-8
```

Cabeçalhos adicionais:

- `Content-Disposition`;
- `X-File-Name`;
- `X-File-Size`;
- `X-File-Last-Modified-Utc`.

### `GET /api/v1/report`

Lê o CSV mais recente e o converte para JSON.

Autenticação: obrigatória.

Exemplo de resposta:

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

As propriedades dentro de `records` usam os cabeçalhos do CSV como nomes. Os valores permanecem como strings para preservar a representação da fonte.

A implementação aceita UTF-8 com ou sem byte-order mark.

### `GET /api/v1/log?lines=500`

Retorna as últimas linhas do arquivo `.log` mais recente em texto puro.

Autenticação: obrigatória.

Parâmetro de consulta:

| Parâmetro | Tipo | Padrão | Restrição |
|---|---|---:|---|
| `lines` | inteiro | `500` | Mínimo `1`; máximo configurado por `MaxLogLines` |

Valor padrão de `MaxLogLines`: `5000`.

Cabeçalhos adicionais:

- `X-Log-File`;
- `X-File-Size`;
- `X-File-Last-Modified-Utc`.

### `GET /api/v1/log/file`

Retorna o log mais recente completo em texto puro.

Autenticação: obrigatória.

Content-Type:

```text
text/plain; charset=utf-8
```

Cabeçalhos adicionais:

- `Content-Disposition`;
- `X-Log-File`;
- `X-File-Size`;
- `X-File-Last-Modified-Utc`.

## Respostas de erro

Erros utilizam o envelope de detalhe do FastAPI:

```json
{
  "detail": "Descrição do erro"
}
```

| Status | Situação |
|---:|---|
| `401` | O cabeçalho `X-API-Key` não foi enviado. |
| `403` | A API key é inválida. |
| `404` | O relatório, diretório de logs ou log mais recente não existe. |
| `422` | Um parâmetro é inválido ou o CSV não pode ser processado. |
| `503` | Não foi possível obter uma leitura estável do arquivo. |

Erros inesperados da aplicação retornam `500` e são registrados no log rotativo da API.

## Cabeçalhos comuns

Todas as respostas incluem:

- `Cache-Control: no-store`;
- `X-Content-Type-Options: nosniff`;
- `X-DeviceLifecycle-API-Version: 1.0.0`.

## Comportamento de leitura estável

Antes de retornar o conteúdo, a API compara tamanho e timestamp de modificação antes e depois da leitura. Se o arquivo mudar durante a operação, a leitura é repetida. Depois de esgotar as tentativas, a API retorna `503` em vez de expor um snapshot potencialmente inconsistente.

## Versionamento e compatibilidade

Mudanças incompatíveis devem utilizar um novo prefixo, como `/api/v2`.

Dentro da `v1`, novas propriedades podem ser adicionadas às respostas, mas propriedades existentes não devem ser removidas ou renomeadas. Consumidores devem ignorar propriedades desconhecidas.

## Recomendações para consumidores

- Armazene a API key em um secret store apropriado ou configuração protegida do serviço.
- Configure timeouts explícitos nas requisições.
- Verifique os códigos HTTP antes de processar o corpo.
- Use `/metadata` quando somente informações de atualização forem necessárias.
- Use `/report.csv` quando a representação original precisar ser preservada.
- Use `/report` quando o processamento direto em JSON for preferível.
- Não assuma que `health.status == "ok"` significa que relatório e log estão disponíveis.
- Rotacione a API key após suspeita de exposição e atualize imediatamente todos os consumidores.

<!-- IMAGE PLACEHOLDER: Adicionar exemplos sanitizados de requisições e respostas, removendo completamente a API key. Caminho sugerido: docs/assets/http-contract-examples.png -->
