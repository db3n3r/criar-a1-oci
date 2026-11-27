# criar-a1: pegar uma Ampere A1 na Oracle Cloud

A A1 do Always Free (até 2 OCPUs / 12 GB) costuma dar **"Out of host capacity"**. Este script tenta de novo sozinho até conseguir, e para assim que a instância existir.

- Tenta 2 OCPUs / 12 GB e, se não houver, 1 OCPU / 6 GB.
- Nunca cria duas: antes de cada ciclo confere se já existe uma instância com o mesmo nome.
- Se a API pedir para desacelerar (429), espera 15 minutos.
- Em qualquer outro erro (OCID errado, permissão, limite), para e mostra o erro no log.

Dica: contas convertidas para **Pay As You Go** costumam conseguir a A1 bem mais rápido. O uso dentro do limite gratuito continua sem custo, mas crie um **alerta de orçamento** antes.

## 1. Pré-requisitos

Rode numa máquina sempre ligada (por exemplo, uma E2.1.Micro gratuita).

```bash
sudo apt update && sudo apt -y install python3-pip pipx && pipx install oci-cli
oci setup config      # gera a API key; cole a chave pública no painel: My profile → API keys
```

## 2. Configurar

```bash
mkdir -p ~/criar-a1 && cd ~/criar-a1
# copie criar-a1.sh, a1.env.example e criar-a1.service para cá
cp a1.env.example a1.env && chmod +x criar-a1.sh
```

Comandos para achar os valores do `a1.env`:

```bash
# AD
oci iam availability-domain list --query 'data[].name'
# Subnets
oci network subnet list --compartment-id <COMPARTMENT_ID> --query 'data[].{nome:"display-name",id:id}' --output table
# Imagens Ubuntu ARM
oci compute image list --compartment-id <COMPARTMENT_ID> --operating-system "Canonical Ubuntu" \
  --shape VM.Standard.A1.Flex --query 'data[].{nome:"display-name",id:id}' --output table
```

## 3. Rodar

Teste rápido em primeiro plano (Ctrl+C para parar):

```bash
./criar-a1.sh
```

Como serviço, para continuar depois de fechar o SSH ou reiniciar:

```bash
sudo cp criar-a1.service /etc/systemd/system/
# ajuste User e os caminhos no .service se o usuário não for "ubuntu"
sudo systemctl daemon-reload && sudo systemctl enable --now criar-a1
tail -f ~/criar-a1/criar-a1.log
```

## 4. Depois de criar

```bash
sudo systemctl disable --now criar-a1
grep SUCESSO ~/criar-a1/criar-a1.log
```

- Libere a porta 22 para o seu IP na Security List ou NSG da subnet.
- Remova a API key do painel e apague `~/.oci` se não for mais usar a CLI.
- **Não passe de 2 OCPUs / 12 GB** nem de 200 GB de disco somando todas as instâncias, para continuar gratuito.
