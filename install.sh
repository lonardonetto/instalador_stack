#!/bin/bash
# =================================================================
# ==            INSTALADOR N8N - AGÊNCIA QUISERA                 ==
# =================================================================
#
# Autor: Agência Quisera
# Versao: 1.0 - Edição Robusta
#
# Este script realiza a instalação completa do n8n em modo swarm,
# com Traefik, Portainer, Postgres e Redis.

# --- Validação dos Parâmetros de Entrada ---
if [ "$#" -ne 4 ]; then
    echo "Erro: Uso incorreto. Forneça todos os parâmetros necessários."
    echo "Uso: $0 <seu-email> <n8n.dominio.com> <portainer.dominio.com> <webhook.dominio.com>"
    exit 1
fi

# --- Configurações Iniciais ---
export DEBIAN_FRONTEND=noninteractive
LOG_FILE="instalador_quisera.log"

SSL_EMAIL=$1
DOMINIO_N8N=$2
DOMINIO_PORTAINER=$3
WEBHOOK_N8N=$4

# Limpa o log antigo
> "$LOG_FILE"

echo "===================================================" | tee -a "$LOG_FILE"
echo "==  INICIANDO INSTALADOR - AGÊNCIA QUISERA   ==" | tee -a "$LOG_FILE"
echo "===================================================" | tee -a "$LOG_FILE"
echo "E-mail para SSL: $SSL_EMAIL" | tee -a "$LOG_FILE"
echo "Domínio n8n: $DOMINIO_N8N" | tee -a "$LOG_FILE"
echo "Domínio Portainer: $DOMINIO_PORTAINER" | tee -a "$LOG_FILE"
echo "Webhook n8n: $WEBHOOK_N8N" | tee -a "$LOG_FILE"
echo "---------------------------------------------------" | tee -a "$LOG_FILE"
echo "O progresso detalhado será salvo em '$LOG_FILE'"

# --- Geração de Credenciais e Arquivo .env ---
echo "Gerando credenciais seguras..." | tee -a "$LOG_FILE"
N8N_KEY=$(openssl rand -hex 16)
POSTGRES_PASSWORD=$(openssl rand -base64 12)

echo "Criando arquivo de configuração .env..." | tee -a "$LOG_FILE"
{
    echo "SSL_EMAIL=$SSL_EMAIL"
    echo "DOMINIO_N8N=$DOMINIO_N8N"
    echo "WEBHOOK_N8N=$WEBHOOK_N8N"
    echo "DOMINIO_PORTAINER=$DOMINIO_PORTAINER"
    echo "N8N_KEY=$N8N_KEY"
    echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD"
} > .env

# --- Configuração do Servidor ---
echo "Ajustando fuso horário para America/Sao_Paulo..." | tee -a "$LOG_FILE"
sudo timedatectl set-timezone America/Sao_Paulo >> "$LOG_FILE" 2>&1

echo "Atualizando pacotes do sistema (isso pode levar alguns minutos)..." | tee -a "$LOG_FILE"
{
    sudo apt-get update -y
    sudo apt-get upgrade -y
    sudo apt-get install -y apparmor-utils curl lsb-release ca-certificates apt-transport-https software-properties-common gnupg2
} >> "$LOG_FILE" 2>&1
echo "Pacotes atualizados com sucesso." | tee -a "$LOG_FILE"

echo "Alocando arquivo de swap de 4G..." | tee -a "$LOG_FILE"
if ! grep -q "/swapfile" /etc/fstab; then
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
    echo "Swap alocado com sucesso." | tee -a "$LOG_FILE"
else
    echo "Arquivo de swap já existe. Pulando etapa." | tee -a "$LOG_FILE"
fi

# --- Instalação e Configuração do Docker ---
if ! command -v docker &> /dev/null; then
    echo "Instalando Docker..." | tee -a "$LOG_FILE"
    curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1
    sudo usermod -aG docker "$USER"
    echo "Docker instalado. É recomendado sair e logar novamente para usar docker sem sudo." | tee -a "$LOG_FILE"
else
    echo "Docker já está instalado. Pulando etapa." | tee -a "$LOG_FILE"
fi

# --- Configuração do Docker Swarm ---
echo "Configurando Docker Swarm..." | tee -a "$LOG_FILE"
if ! docker info | grep -q "Swarm: active"; then
    # CORREÇÃO INTELIGENTE: Detecta o IP principal da máquina dinamicamente.
    endereco_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
    if [[ -z $endereco_ip ]]; then
        echo "ERRO: Não foi possível obter o endereço IP principal da máquina." | tee -a "$LOG_FILE"
        exit 1
    fi
    echo "Iniciando Swarm no IP: $endereco_ip" | tee -a "$LOG_FILE"
    docker swarm init --advertise-addr "$endereco_ip" >> "$LOG_FILE" 2>&1
else
    echo "Docker Swarm já está ativo. Pulando inicialização." | tee -a "$LOG_FILE"
fi

# Cria a rede overlay se não existir
if ! docker network ls | grep -q "network_public"; then
    docker network create --driver=overlay network_public >> "$LOG_FILE" 2>&1
    echo "Rede 'network_public' do Swarm criada." | tee -a "$LOG_FILE"
else
    echo "Rede 'network_public' já existe. Pulando etapa." | tee -a "$LOG_FILE"
fi

# --- Implantação dos Stacks ---
# MELHORIA ARQUITETURAL: Presume que os arquivos .yaml estão em uma pasta local 'stacks'
# Isso torna o instalador autossuficiente e não dependente de uma URL externa.
STACKS_DIR="stacks"

if [ ! -d "$STACKS_DIR" ]; then
    echo "ERRO: O diretório '$STACKS_DIR' com os arquivos .yaml não foi encontrado." | tee -a "$LOG_FILE"
    echo "Por favor, crie o diretório e coloque os arquivos traefik.yaml, portainer.yaml, postgres.yaml e redis.yaml dentro dele."
    exit 1
fi

echo "Implantando stack do Traefik..." | tee -a "$LOG_FILE"
env SSL_EMAIL="$SSL_EMAIL" docker stack deploy --prune --resolve-image always -c "$STACKS_DIR/traefik.yaml" traefik >> "$LOG_FILE" 2>&1
echo "Traefik implantado." | tee -a "$LOG_FILE"

echo "Implantando stack do Portainer..." | tee -a "$LOG_FILE"
env DOMINIO_PORTAINER="$DOMINIO_PORTAINER" docker stack deploy --prune --resolve-image always -c "$STACKS_DIR/portainer.yaml" portainer >> "$LOG_FILE" 2>&1
echo "Portainer implantado." | tee -a "$LOG_FILE"

echo "Implantando stack do Postgres..." | tee -a "$LOG_FILE"
env POSTGRES_PASSWORD="$POSTGRES_PASSWORD" docker stack deploy --prune --resolve-image always -c "$STACKS_DIR/postgres.yaml" postgres >> "$LOG_FILE" 2>&1
echo "Postgres implantado." | tee -a "$LOG_FILE"

echo "Implantando stack do Redis..." | tee -a "$LOG_FILE"
docker stack deploy --prune --resolve-image always -c "$STACKS_DIR/redis.yaml" redis >> "$LOG_FILE" 2>&1
echo "Redis implantado." | tee -a "$LOG_FILE"

# --- Configuração do Banco de Dados para o n8n ---
echo "Aguardando o serviço do Postgres ficar pronto..." | tee -a "$LOG_FILE"
# CORREÇÃO INTELIGENTE: Espera ativamente pelo Postgres em vez de usar um 'sleep' fixo.
retries=30
until docker exec "$(docker ps --filter name=postgres_postgres -q)" pg_isready -U postgres > /dev/null 2>&1 || [ $retries -eq 0 ]; do
    echo "Aguardando Postgres... ($retries tentativas restantes)" | tee -a "$LOG_FILE"
    retries=$((retries - 1))
    sleep 5
done

if [ $retries -eq 0 ]; then
    echo "ERRO: O container do Postgres não ficou pronto a tempo." | tee -a "$LOG_FILE"
    exit 1
fi

echo "Postgres está pronto. Criando banco de dados 'n8n'..." | tee -a "$LOG_FILE"
postgres_container_name=$(docker ps --filter "name=postgres_postgres" --format "{{.Names}}")
docker exec "$postgres_container_name" psql -U postgres -d postgres -c "CREATE DATABASE n8n;" < /dev/null >> "$LOG_FILE" 2>&1
echo "Banco de dados 'n8n' criado." | tee -a "$LOG_FILE"

# --- Implantação do n8n ---
echo "Implantando stack do n8n..." | tee -a "$LOG_FILE"
env DOMINIO_N8N="$DOMINIO_N8N" WEBHOOK_N8N="$WEBHOOK_N8N" POSTGRES_PASSWORD="$POSTGRES_PASSWORD" N8N_KEY="$N8N_KEY" docker stack deploy --prune --resolve-image always -c "$STACKS_DIR/n8n.yaml" n8n >> "$LOG_FILE" 2>&1
echo "n8n implantado com sucesso!" | tee -a "$LOG_FILE"

# --- Finalização ---
echo "===================================================" | tee -a "$LOG_FILE"
echo "==   INSTALAÇÃO CONCLUÍDA COM SUCESSO!   ==" | tee -a "$LOG_FILE"
echo "===================================================" | tee -a "$LOG_FILE"
echo ""
echo "Acessos disponíveis em breve (aguarde a propagação do DNS e geração do SSL):"
echo "  - Portainer: https://$DOMINIO_PORTAINER"
echo "  - n8n: https://$DOMINIO_N8N"
echo ""
echo "Um log detalhado da instalação foi salvo em: $LOG_FILE"
echo "Feche esta janela do terminal. A instalação continuará em background."
