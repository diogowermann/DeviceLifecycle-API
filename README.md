# DeviceLifecycle-API

API HTTP interna, somente leitura, para publicar o relatório CSV e os logs
gerados pelo repositório `DeviceLifecycle`.

> `DeviceLifecycle-API` é uma extensão opcional e mantida em repositório
> separado. Ela depende dos arquivos produzidos pelo `DeviceLifecycle`, mas o
> serviço principal não depende da API para executar inventário, quarentena ou
> exclusão de dispositivos.

A extensão pode ser consumida por dashboards, inventários, monitoramento,
rotinas de auditoria e outros serviços internos autorizados.

## Responsabilidade da extensão

A API lê somente:

- `Reports\DeviceLifecycle-Latest.csv`
- o arquivo `.log` mais recente em `Logs`

Ela não executa comandos no Active Directory, Entra ID, Intune ou Microsoft
Graph. Não existem endpoints de escrita.

## Estrutura do repositório

- `app\main.py`: aplicação FastAPI.
- `DeviceLifecycleApi.Config.psd1`: configuração administrativa e identidade da organização.
- `DeviceLifecycleApi.Helpers.psm1`: derivação dos caminhos e nomes por organização.
- `Install-DeviceLifecycleApi.ps1`: instalação e atualização.
- `Start-DeviceLifecycleApi.ps1`: inicialização pelo Agendador de Tarefas.
- `Test-DeviceLifecycleApi.ps1`: validação local completa.
- `Reset-DeviceLifecycleApiKey.ps1`: rotação da API key.
- `Uninstall-DeviceLifecycleApi.ps1`: remoção da extensão.
- `Examples\Query-DeviceLifecycleApi.ps1`: exemplo de consumo.
- `docs\API.md`: contrato HTTP detalhado.
- `docs\ARCHITECTURE.md`: relação com o repositório principal.

## Requisitos

- `DeviceLifecycle` instalado e executado ao menos uma vez.
- Windows Server com acesso local aos diretórios de relatórios e logs.
- Windows PowerShell 5.1.
- Python 3.10 ou superior instalado para todos os usuários.
- PowerShell elevado durante instalação, atualização ou remoção.
- Acesso à internet durante a instalação das dependências pelo PyPI.

## Configuração da organização

Use o mesmo valor de `OrganizationName` configurado no repositório principal.
Edite:

```text
DeviceLifecycleApi.Config.psd1
```

Exemplo:

```powershell
OrganizationName = 'orgname'
RemoteAddress = @(
    '192.168.1.20',
    '192.168.1.21'
)
```

A partir de `OrganizationName`, a extensão deriva:

- Dados de origem: `C:\ProgramData\{OrganizationName}\DeviceLifecycle`
- Instalação: `C:\Program Files\{OrganizationName}\DeviceLifecycle-API`
- Configuração: `C:\ProgramData\{OrganizationName}\DeviceLifecycleApi`
- Tarefa: `{OrganizationName} - Device Lifecycle API`
- Firewall: `{OrganizationName} - Device Lifecycle API`

Todos esses valores podem ser sobrescritos no arquivo de configuração.

## Instalação

Extraia a pasta `DeviceLifecycle-API` no servidor do `DeviceLifecycle`, edite o
arquivo de configuração e execute como administrador:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force

.\Install-DeviceLifecycleApi.ps1 -Force
```

Também é possível sobrescrever os IPs permitidos somente nessa execução:

```powershell
.\Install-DeviceLifecycleApi.ps1 `
    -RemoteAddress '192.168.1.20','192.168.1.21' `
    -Force
```

O instalador:

1. valida os arquivos gerados pelo `DeviceLifecycle`;
2. valida Python 3.10 ou superior;
3. cria o diretório de instalação;
4. cria um ambiente virtual Python;
5. instala FastAPI e Uvicorn;
6. gera uma API key aleatória de 64 caracteres hexadecimais;
7. grava a configuração de runtime fora do repositório;
8. cria uma tarefa agendada executada como `SYSTEM` na inicialização;
9. cria uma regra de firewall restrita aos IPs configurados;
10. inicia a API.

A API key exibida pelo instalador não deve ser versionada.

## Validação

```powershell
& 'C:\Program Files\orgname\DeviceLifecycle-API\Test-DeviceLifecycleApi.ps1'
```

O teste valida configuração, chave, relatório, logs, tarefa agendada e os
endpoints principais.

## Endpoints

| Método | Endpoint | Autenticação | Retorno |
|---|---|---|---|
| `GET` | `/api/v1/health` | Opcional | Estado da API e disponibilidade das fontes |
| `GET` | `/api/v1/metadata` | `X-API-Key` | Metadados do relatório e log |
| `GET` | `/api/v1/report.csv` | `X-API-Key` | CSV original, sem transformação |
| `GET` | `/api/v1/report` | `X-API-Key` | CSV convertido para JSON |
| `GET` | `/api/v1/log?lines=500` | `X-API-Key` | Últimas linhas do log em texto puro |
| `GET` | `/api/v1/log/file` | `X-API-Key` | Log completo em texto puro |

Contrato completo: [`docs/API.md`](docs/API.md).

## Exemplo de consumo em PowerShell

```powershell
$headers = @{
    'X-API-Key' = 'COLE-A-CHAVE-AQUI'
}

$csv = Invoke-WebRequest `
    -Uri 'http://cloud-sync:8088/api/v1/report.csv' `
    -Headers $headers `
    -UseBasicParsing

$csv.Content
```

JSON:

```powershell
$report = Invoke-RestMethod `
    -Uri 'http://cloud-sync:8088/api/v1/report' `
    -Headers $headers `
    -UseBasicParsing

$report.recordCount
$report.records
```

Log:

```powershell
$log = Invoke-WebRequest `
    -Uri 'http://cloud-sync:8088/api/v1/log?lines=200' `
    -Headers $headers `
    -UseBasicParsing

$log.Content
```

## Rotação da API key

```powershell
& 'C:\Program Files\orgname\DeviceLifecycle-API\Reset-DeviceLifecycleApiKey.ps1'
```

A tarefa é reiniciada automaticamente. Atualize todos os consumidores com a
nova chave.

## Configuração de runtime

O instalador gera:

```text
C:\ProgramData\{OrganizationName}\DeviceLifecycleApi\Api.Config.json
```

Esse arquivo é operacional e não deve substituir o
`DeviceLifecycleApi.Config.psd1` versionado no repositório.

Depois de alterar a configuração, reinstale com `-Force` ou reinicie a tarefa:

```powershell
Stop-ScheduledTask -TaskName 'orgname - Device Lifecycle API'
Start-ScheduledTask -TaskName 'orgname - Device Lifecycle API'
```

## Logs da API

```text
C:\ProgramData\{OrganizationName}\DeviceLifecycleApi\Logs\DeviceLifecycleApi.log
```

A rotação ocorre em 5 MB, com retenção de cinco arquivos anteriores. A API key
não é gravada nos logs.

## Segurança

- API somente leitura.
- API key obrigatória nos endpoints de dados.
- Comparação da chave em tempo constante.
- Regra de firewall limitada aos consumidores configurados.
- Swagger, ReDoc e schema OpenAPI desabilitados em runtime.
- Nenhum caminho de arquivo é fornecido pelo cliente.
- Leitura estável para evitar conteúdo parcial durante a atualização dos arquivos.
- `Cache-Control: no-store` em todas as respostas.
- Limite configurável para leitura das últimas linhas do log.

O transporte padrão é HTTP interno. Para redes não confiáveis, use reverse
proxy HTTPS.

## Desinstalação

Simulação:

```powershell
& 'C:\Program Files\orgname\DeviceLifecycle-API\Uninstall-DeviceLifecycleApi.ps1' -WhatIf
```

Remoção completa da extensão:

```powershell
& 'C:\Program Files\orgname\DeviceLifecycle-API\Uninstall-DeviceLifecycleApi.ps1' `
    -RemoveConfiguration `
    -RemoveApiKey
```

A desinstalação não remove o repositório principal nem os relatórios, logs ou
`state.json` do `DeviceLifecycle`.
