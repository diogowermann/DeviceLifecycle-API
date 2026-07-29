# Arquitetura e relação com DeviceLifecycle

## Relação entre os repositórios

`DeviceLifecycle-API` é um repositório separado e uma extensão opcional do
repositório `DeviceLifecycle`.

```text
Active Directory / Entra ID / Intune
                 |
                 v
        DeviceLifecycle
        - coleta os sinais
        - decide o ciclo de vida
        - gera CSV e logs
                 |
                 | arquivos locais, somente leitura
                 v
       DeviceLifecycle-API
       - autentica consumidores
       - publica CSV, JSON e log
                 |
                 v
 Dashboards / inventário / monitoramento / integrações
```

## Limites de responsabilidade

### DeviceLifecycle

- É a fonte autoritativa.
- Interage com AD, Entra ID, Intune e Microsoft Graph.
- Pode executar ações conforme `ReportOnly`, `Quarantine` ou `Enforce`.
- Mantém relatórios, logs e estado operacional.

### DeviceLifecycle-API

- Não altera arquivos do serviço principal.
- Não recebe caminhos arbitrários do cliente.
- Não executa scripts ou comandos do ciclo de vida.
- Não possui endpoint de escrita.
- Expõe apenas os caminhos definidos na configuração administrativa.

## Implantação recomendada

Instale a API no mesmo servidor em que os arquivos do `DeviceLifecycle` estão
armazenados. Outros servidores devem atuar somente como consumidores HTTP.
Restrinja a regra de firewall aos endereços IP desses consumidores.

A API não é requisito para o funcionamento do `DeviceLifecycle`. Se a extensão
for parada ou removida, a automação principal continua funcionando normalmente.
