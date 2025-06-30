#!/bin/bash
# =================================================================
# ==            INSTALADOR N8N - AGÊNCIA QUISERA                 ==
# =================================================================
#
# Autor: Agência Quisera
# Versao: 1.3 - Final com Acessos Detalhados
#
# Este script realiza a instalação completa do n8n e Evolution API
# em modo swarm, com todas as dependências e exibe um resumo final.

# --- Validação dos Parâmetros de Entrada ---
if [ "$#" -ne 5 ]; then
    echo "Erro: Uso incorreto. Forneça todos os parâmetros necessários."
    echo "Uso: $0 <email> <n8n.dominio> <portainer.dominio> <webhook.n8n> <evolution.dominio>"
    exit 1
fi

# --- Configurações Iniciais ---
export DEBIAN_FRONTEND=noninteractive
LOG_FILE="instalador_quisera.log"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SSL_EMAIL=$1
DOMINIO_N8N=$2
DOMINIO_PORTAINER=$3
WEBHOOK_N8N=$4
DOMINIO_EVOLUTION=$5

# Limpa o log antigo
> "$LOG_FILE"

echo "===================================================" | tee -a "$LOG_FILE"
echo "==  INICIANDO INSTALADOR - AGÊNCIA QUISERA   ==" | tee -a "$LOG_FILE"
echo "===================================================" | tee -a "$LOG_FILE"
echo "O progresso detalhado será salvo em '$LOG_FILE'"

# --- Geração de Credenciais e Arquivo .env ---
echo "Gerando credenciais seguras..." | tee -a "$LOG_FILE"
N8N_KEY=$(openssl rand -hex 16)
POSTGRES_PASSWORD=$(openssl rand -base64 12)
EVOLUTION_API_KEY=$(openssl rand -hex 20)
MONGO_ROOT_USERNAME="quisera"
MONGO_ROOT_PASSWORD=$(openssl rand -base64 12)

echo "Criando arquivo de configuração .env..." | tee -a "$LOG_FILE"
{
    echo "SSL_EMAIL=$SSL_EMAIL"
    echo "DOMINIO_N8N=$DOMINIO_N8N"
    echo "WEBHOOK_N8N=$WEBHOOK_N8N"
    echo "DOMINIO_PORTAINER=$DOMINIO_PORTAINER"
    echo "DOMINIO_EVOLUTION=$DOMINIO_EVOLUTION"
    echo "N8N_KEY=$N8N_KEY"
    echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD"
    echo "EVOLUTION_API_KEY=$EVOLUTION_API_KEY"
    echo "MONGO_ROOT_USERNAME=$MONGO_ROOT_USERNAME"
    echo "MONGO_ROOT_PASSWORD=$MONGO_ROOT_PASSWORD"
} > .env

# --- Configuração do Servidor ---
echo "Ajustando fuso horário para America/Sao_Paulo..." | tee -a "$LOG_FILE"
sudo timedatectl set-timezone America/Sao_Paulo >> "$LOG_FILE" 2>&1

echo "Atualizando pacotes do sistema..." | tee -a "$LOG_FILE"
{
    sudo apt-get update -y && sudo apt-get upgrade -y &&
    sudo apt-get install -y apparmor-utils curl lsb-release ca-certificates apt-transport-https software-properties-common gnupg2
} >> "$LOG_FILE" 2>&1

echo "Alocando arquivo de swap de 4G..." | tee -a "$LOG_FILE"
if ! grep -q "/swapfile" /etc/fstab; then
    sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile &&
    sudo mkswap /swapfile && sudo swapon /swapfile &&
    echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
fi

# --- Instalação e Configuração do Docker ---
if ! command -v docker &> /dev/null; then
    echo "Instalando Docker..." | tee -a "$LOG_FILE"
    curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1
    sudo usermod -aG docker "$USER"
fi

# --- Configuração do Docker Swarm ---
echo "Configurando Docker Swarm..." | tee -a "$LOG_FILE"
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    endereco_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
    docker swarm init --advertise-addr "$endereco_ip" >> "$LOG_FILE" 2>&1
fi
if ! docker network ls | grep -q "network_public"; then
    docker network create --driver=overlay network_public >> "$LOG_FILE" 2>&1
fi

# --- Implantação dos Stacks ---
STACKS_DIR="stacks"
REPO_BASE_URL="https://raw.githubusercontent.com/lonardonetto/instalador_stack/main/stacks"

echo "Baixando arquivos de configuração dos stacks..." | tee -a "$LOG_FILE"
mkdir -p "$STACKS_DIR"

curl -sSL "$REPO_BASE_URL/traefik.yaml" -o "$STACKS_DIR/traefik.yaml"
curl -sSL "$REPO_BASE_URL/portainer.yaml" -o "$STACKS_DIR/portainer.yaml"
curl -sSL "$REPO_BASE_URL/postgres.yaml" -o "$STACKS_DIR/postgres.yaml"
curl -sSL "$REPO_BASE_URL/redis.yaml" -o "$STACKS_DIR/redis.yaml"
curl -sSL "$REPO_BASE_URL/n8n.yaml" -o "$STACKS_DIR/n8n.yaml"
curl -sSL "$REPO_BASE_URL/evolution.yaml" -o "$STACKS_DIR/evolution.yaml"

echo "Implantando stacks..." | tee -a "$LOG_FILE"
env SSL_EMAIL="$SSL_EMAIL" docker stack deploy -c "$STACKS_DIR/traefik.yaml" traefik >> "$LOG_FILE" 2>&1
env DOMINIO_PORTAINER="$DOMINIO_PORTAINER" docker stack deploy -c "$STACKS_DIR/portainer.yaml" portainer >> "$LOG_FILE" 2>&1
env POSTGRES_PASSWORD="$POSTGRES_PASSWORD" docker stack deploy -c "$STACKS_DIR/postgres.yaml" postgres >> "$LOG_FILE" 2>&1
docker stack deploy -c "$STACKS_DIR/redis.yaml" redis >> "$LOG_FILE" 2>&1

echo "Implantando stack da Evolution API..." | tee -a "$LOG_FILE"
env DOMINIO_EVOLUTION="$DOMINIO_EVOLUTION" \
    EVOLUTION_API_KEY="$EVOLUTION_API_KEY" \
    MONGO_ROOT_USERNAME="$MONGO_ROOT_USERNAME" \
    MONGO_ROOT_PASSWORD="$MONGO_ROOT_PASSWORD" \
    docker stack deploy -c "$STACKS_DIR/evolution.yaml" evolution >> "$LOG_FILE" 2>&1

# --- Configuração do Banco de Dados para o n8n ---
echo "Aguardando Postgres e criando banco de dados n8n..." | tee -a "$LOG_FILE"
retries=30
until docker exec "$(docker ps --filter name=postgres_postgres -q)" pg_isready -U postgres > /dev/null 2>&1 || [ $retries -eq 0 ]; do
    retries=$((retries - 1)); sleep 5;
done
docker exec "$(docker ps --filter "name=postgres_postgres" --format "{{.Names}}")" psql -U postgres -d postgres -c "CREATE DATABASE n8n;" < /dev/null >> "$LOG_FILE" 2>&1

# --- Implantação do n8n ---
echo "Implantando stack do n8n..." | tee -a "$LOG_FILE"
env DOMINIO_N8N="$DOMINIO_N8N" WEBHOOK_N8N="$WEBHOOK_N8N" POSTGRES_PASSWORD="$POSTGRES_PASSWORD" N8N_KEY="$N8N_KEY" docker stack deploy -c "$STACKS_DIR/n8n.yaml" n8n >> "$LOG_FILE" 2>&1

# --- Finalização ---
cat << EOF | tee -a "$LOG_FILE"

${GREEN}=================================================================${NC}
${GREEN}==            INSTALAÇÃO CONCLUÍDA COM SUCESSO!            ==${NC}
${GREEN}=================================================================${NC}

Seu ambiente de automação da Agência Quisera está pronto!
Salve estas informações em um local seguro.

${BLUE}--- Acessos e Credenciais ---${NC}

1.  ${BLUE}PORTAINER (Gerenciador de Containers)${NC}
    URL de Acesso:  https://${DOMINIO_PORTAINER}
    Usuário/Senha:  Você deverá criar seu usuário administrador
                    (ex: 'quisera_admin') e uma senha no primeiro acesso.
                    Este é o comportamento padrão e seguro do Portainer.

2.  ${BLUE}n8n (Plataforma de Automação)${NC}
    URL de Acesso:  https://${DOMINIO_N8N}
    Configuração:   No primeiro acesso, você precisará criar
                    uma conta de administrador para o n8n.

3.  ${BLUE}EVOLUTION API (API para WhatsApp)${NC}
    URL da API:     https://${DOMINIO_EVOLUTION}
    API KEY:        ${EVOLUTION_API_KEY}
    (Guarde esta chave, ela é necessária para todas as requisições)

${BLUE}--- PRIMEIROS PASSOS COM A EVOLUTION API ---${NC}

Para começar a usar o WhatsApp, você precisa criar uma 'instância'.
Use o comando abaixo, substituindo 'minha-instancia' pelo nome
que desejar para sua conexão:

curl --request POST \\
  --url https://${DOMINIO_EVOLUTION}/instance/create \\
  --header 'apikey: ${EVOLUTION_API_KEY}' \\
  --header 'Content-Type: application/json' \\
  --data '{
    "instanceName": "minha-instancia",
    "qrcode": true
  }'

Após executar o comando, acesse a URL abaixo para escanear o QR Code
com o seu celular e conectar o WhatsApp:
https://${DOMINIO_EVOLUTION}/instance/connect/minha-instancia

-------------------------------------------------------------------
Lembre-se: Pode levar alguns minutos para os certificados SSL serem
gerados pelo Traefik e os sites ficarem acessíveis.
EOF
