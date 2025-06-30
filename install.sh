#!/bin/bash
# =================================================================
# ==            INSTALADOR N8N - AGÊNCIA QUISERA                 ==
# =================================================================
#
# Autor: Agência Quisera
# Versao: 2.0 - Verificação de Status Online
#
# Este script instala a stack completa e verifica se cada serviço
# principal está online antes de continuar.

# --- FUNÇÃO DE VERIFICAÇÃO DE STATUS ---
wait_for_service() {
    local service_name=$1
    local service_friendly_name=$2
    local timeout_seconds=180 # 3 minutos

    echo -n "--> Verificando status do ${service_friendly_name}... "

    local end_time=$(( $(date +%s) + timeout_seconds ))
    while [ $(date +%s) -lt $end_time ]; do
        # Verifica se o serviço existe e obtém o status da réplica
        local replica_status=$(docker service ls --filter "name=${service_name}" --format "{{.Replicas}}")
        if [ -n "$replica_status" ]; then
            # O formato é "1/1"
            local running=$(echo "$replica_status" | cut -d'/' -f1)
            local expected=$(echo "$replica_status" | cut -d'/' -f2)
            # Verifica se as réplicas estão rodando e se o número esperado é maior que zero
            if [ "$running" -eq "$expected" ] && [ "$running" -gt 0 ]; then
                echo "Online. [OK]"
                return 0
            fi
        fi
        echo -n "."
        sleep 5
    done
    
    echo " [FALHA]"
    echo "ERRO: O serviço ${service_friendly_name} não ficou online a tempo."
    exit 1
}


# --- Validação dos Parâmetros de Entrada ---
if [ "$#" -ne 5 ]; then
    echo "Erro: Uso incorreto. Forneça todos os parâmetros necessários."
    echo "Uso: $0 <email> <n8n.dominio> <portainer.dominio> <webhook.n8n> <evolution.dominio>"
    exit 1
fi

# --- Configurações Iniciais ---
export DEBIAN_FRONTEND=noninteractive
LOG_FILE="instalador_quisera.log"
SSL_EMAIL=$1; DOMINIO_N8N=$2; DOMINIO_PORTAINER=$3; WEBHOOK_N8N=$4; DOMINIO_EVOLUTION=$5
> "$LOG_FILE"
echo "== INICIANDO INSTALADOR 2.0 - AGÊNCIA QUISERA ==" | tee -a "$LOG_FILE"

# --- Geração de Credenciais ---
echo "--> Gerando credenciais seguras..."
N8N_KEY=$(openssl rand -hex 16); POSTGRES_PASSWORD=$(openssl rand -base64 12);
EVOLUTION_API_KEY=$(openssl rand -hex 20); MONGO_ROOT_USERNAME="quisera";
MONGO_ROOT_PASSWORD=$(openssl rand -base64 12);
{
    echo "SSL_EMAIL=$SSL_EMAIL"; echo "DOMINIO_N8N=$DOMINIO_N8N"; echo "WEBHOOK_N8N=$WEBHOOK_N8N";
    echo "DOMINIO_PORTAINER=$DOMINIO_PORTAINER"; echo "DOMINIO_EVOLUTION=$DOMINIO_EVOLUTION";
    echo "N8N_KEY=$N8N_KEY"; echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD";
    echo "EVOLUTION_API_KEY=$EVOLUTION_API_KEY"; echo "MONGO_ROOT_USERNAME=$MONGO_ROOT_USERNAME";
    echo "MONGO_ROOT_PASSWORD=$MONGO_ROOT_PASSWORD";
} > .env
echo "Credenciais salvas em .env. [OK]"

# --- Configuração do Servidor ---
echo "--> Configurando servidor (fuso horário, pacotes, swap)..."
{
    sudo timedatectl set-timezone America/Sao_Paulo
    sudo apt-get update -y && sudo apt-get upgrade -y
    sudo apt-get install -y apparmor-utils curl lsb-release ca-certificates apt-transport-https software-properties-common gnupg2
    if ! grep -q "/swapfile" /etc/fstab; then
        sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
        sudo mkswap /swapfile && sudo swapon /swapfile
        echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
    fi
} >> "$LOG_FILE" 2>&1
echo "Configuração do servidor concluída. [OK]"

# --- Instalação do Docker e Swarm ---
echo "--> Configurando Docker e Swarm..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1
    sudo usermod -aG docker "$USER"
fi
wait_for_service "docker" "Docker Daemon" # Função especial para o docker
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    endereco_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
    docker swarm init --advertise-addr "$endereco_ip" >> "$LOG_FILE" 2>&1
fi
if ! docker network ls | grep -q "network_public"; then
    docker network create --driver=overlay network_public >> "$LOG_FILE" 2>&1
fi
echo "Docker e Swarm prontos. [OK]"

# --- Implantação dos Stacks ---
STACKS_DIR="stacks"
REPO_BASE_URL="https://raw.githubusercontent.com/lonardonetto/instalador_stack/main/stacks"
echo "--> Baixando arquivos de configuração (.yaml)..."
mkdir -p "$STACKS_DIR"
{
    curl -sSL "$REPO_BASE_URL/traefik.yaml" -o "$STACKS_DIR/traefik.yaml"
    curl -sSL "$REPO_BASE_URL/portainer.yaml" -o "$STACKS_DIR/portainer.yaml"
    curl -sSL "$REPO_BASE_URL/postgres.yaml" -o "$STACKS_DIR/postgres.yaml"
    curl -sSL "$REPO_BASE_URL/redis.yaml" -o "$STACKS_DIR/redis.yaml"
    curl -sSL "$REPO_BASE_URL/n8n.yaml" -o "$STACKS_DIR/n8n.yaml"
    curl -sSL "$REPO_BASE_URL/evolution.yaml" -o "$STACKS_DIR/evolution.yaml"
}
echo "Download concluído. [OK]"

echo "--> Implantando stacks e verificando status..."
env SSL_EMAIL="$SSL_EMAIL" docker stack deploy -c "$STACKS_DIR/traefik.yaml" traefik >> "$LOG_FILE" 2>&1
wait_for_service "traefik_traefik" "Traefik"

env DOMINIO_PORTAINER="$DOMINIO_PORTAINER" docker stack deploy -c "$STACKS_DIR/portainer.yaml" portainer >> "$LOG_FILE" 2>&1
wait_for_service "portainer_portainer" "Portainer"

env POSTGRES_PASSWORD="$POSTGRES_PASSWORD" docker stack deploy -c "$STACKS_DIR/postgres.yaml" postgres >> "$LOG_FILE" 2>&1
wait_for_service "postgres_postgres" "Postgres"

docker stack deploy -c "$STACKS_DIR/redis.yaml" redis >> "$LOG_FILE" 2>&1
wait_for_service "redis_redis" "Redis"

env DOMINIO_EVOLUTION="$DOMINIO_EVOLUTION" EVOLUTION_API_KEY="$EVOLUTION_API_KEY" MONGO_ROOT_USERNAME="$MONGO_ROOT_USERNAME" MONGO_ROOT_PASSWORD="$MONGO_ROOT_PASSWORD" docker stack deploy -c "$STACKS_DIR/evolution.yaml" evolution >> "$LOG_FILE" 2>&1
wait_for_service "evolution_mongo" "MongoDB (Evolution)"
wait_for_service "evolution_evolution" "Evolution API"

echo "--> Configurando banco de dados do n8n..."
docker exec "$(docker ps --filter "name=postgres_postgres" --format "{{.Names}}")" psql -U postgres -d postgres -c "CREATE DATABASE n8n;" < /dev/null >> "$LOG_FILE" 2>&1
echo "Banco de dados 'n8n' criado. [OK]"

echo "--> Implantando n8n..."
env DOMINIO_N8N="$DOMINIO_N8N" WEBHOOK_N8N="$WEBHOOK_N8N" POSTGRES_PASSWORD="$POSTGRES_PASSWORD" N8N_KEY="$N8N_KEY" docker stack deploy -c "$STACKS_DIR/n8n.yaml" n8n >> "$LOG_FILE" 2>&1
wait_for_service "n8n_n8n-worker" "n8n Worker"
wait_for_service "n8n_n8n-main" "n8n Main"

# --- Finalização ---
cat << EOF

#####################################################################
#                                                                   #
#         INSTALADOR 2.0 AGENCIA QUISERA - ACESSOS FINAIS           #
#                                                                   #
#####################################################################

A instalação foi concluída com sucesso. Guarde estas informações.
Pode levar alguns minutos para os sites ficarem 100% online.

---------------------------------------------------------------------
--> PORTAINER (Gerenciador de Containers)
---------------------------------------------------------------------
- URL de Acesso: https://${DOMINIO_PORTAINER}
- Instruções: No primeiro acesso, crie seu usuário administrador.
              (Sugestão de usuário: quisera_admin)

---------------------------------------------------------------------
--> N8N (Plataforma de Automação)
---------------------------------------------------------------------
- URL de Acesso: https://${DOMINIO_N8N}
- Instruções: No primeiro acesso, crie a conta do proprietário.

---------------------------------------------------------------------
--> EVOLUTION API (API para WhatsApp)
---------------------------------------------------------------------
- URL do Manager: https://${DOMINIO_EVOLUTION}/manager
- Sua API KEY:    ${EVOLUTION_API_KEY}
- Instruções:     Acesse a URL do Manager para ver a documentação
                  e interagir com a API. Use a API KEY acima para
                  criar sua primeira instância.

#####################################################################

EOF
