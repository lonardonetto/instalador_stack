#!/bin/bash
# =================================================================
# ==        GERENCIADOR DE STACK - AGÊNCIA QUISERA               ==
# =================================================================
#
# Autor: Agência Quisera
# Versao: 3.1 - Correção do Menu
#
# Este script serve como um instalador e ferramenta de manutenção
# para a stack de automação, com uma interface visualmente organizada.

# --- Definições de Cores e Estilos ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'

# --- Funções Auxiliares de Exibição ---
print_header() {
    echo -e "\n${C_BLUE}${C_BOLD}# $1${C_RESET}"
}

print_step() {
    echo -e "${C_YELLOW}- $1${C_RESET}"
}

print_ok() {
    echo -e "  ${C_GREEN}[OK]${C_RESET} $1"
}

print_error() {
    echo -e "${C_RED}[ERRO]${C_RESET} $1"
}

wait_for_service() {
    local service_name=$1
    local service_friendly_name=$2
    local timeout_seconds=180

    echo -en "${C_YELLOW}- Verificando status do ${service_friendly_name}... ${C_RESET}"

    local end_time=$(( $(date +%s) + timeout_seconds ))
    while [ $(date +%s) -lt $end_time ]; do
        local replica_status=$(docker service ls --filter "name=${service_name}" --format "{{.Replicas}}" 2>/dev/null)
        if [ -n "$replica_status" ]; then
            local running=$(echo "$replica_status" | cut -d'/' -f1)
            local expected=$(echo "$replica_status" | cut -d'/' -f2)
            if [ "$running" -eq "$expected" ] && [ "$running" -gt 0 ]; then
                echo -e "${C_GREEN}Online.${C_RESET}"
                return 0
            fi
        fi
        echo -n "."
        sleep 5
    done
    
    echo -e "${C_RED} [FALHA]${C_RESET}"
    print_error "O serviço ${service_friendly_name} não ficou online a tempo."
    exit 1
}

# --- Funções de Gerenciamento ---
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker não está instalado. Execute a Instalação Completa (opção 1) primeiro."
        exit 1
    fi
}

check_env_file() {
    if [ ! -f .env ]; then
        print_error "O arquivo de configuração '.env' não foi encontrado. Execute a Instalação Completa (opção 1) primeiro."
        exit 1
    fi
    source .env
}

restart_portainer() {
    check_docker
    print_header "REINICIANDO O PORTAINER"
    print_step "Forçando a reinicialização do serviço para corrigir o timeout de login..."
    docker service update --force portainer_portainer > /dev/null
    print_ok "Portainer reiniciado. Aguarde um minuto e tente acessar a URL novamente."
}

reset_portainer_password() {
    check_docker
    print_header "RESET DE SENHA DO PORTAINER"
    print_step "Este processo usará a ferramenta oficial do Portainer."
    print_step "1. Parando o serviço do Portainer..."
    docker service scale portainer_portainer=0 > /dev/null
    sleep 10
    print_step "2. Executando a ferramenta de reset..."
    echo -e "${C_YELLOW}--> COPIE A SENHA TEMPORÁRIA ABAIXO:${C_RESET}"
    docker run --rm -v portainer_data:/data portainer/helper-password-reset
    print_step "3. Reiniciando o serviço do Portainer..."
    docker service scale portainer_portainer=1 > /dev/null
    sleep 5
    print_ok "Processo concluído! Use a senha temporária para fazer login e criar uma nova."
}

reconfigure_n8n() {
    check_docker
    check_env_file
    print_header "RESET COMPLETO DO N8N"
    echo -e "${C_RED}${C_BOLD}!!!!!!!!!!!!!!!!!!!!!!!!!! AVISO IMPORTANTE !!!!!!!!!!!!!!!!!!!!!!!!!!${C_RESET}"
    echo -e "${C_RED}Esta ação irá APAGAR COMPLETAMENTE TODOS OS DADOS DO N8N (workflows, etc).${C_RESET}"
    read -p "Digite 'SIM' em maiúsculas para confirmar a exclusão de tudo: " confirmation
    if [ "$confirmation" != "SIM" ]; then
        echo "Operação cancelada."
        exit 0
    fi
    print_step "1. Removendo stacks do n8n e Postgres..."
    docker stack rm n8n > /dev/null; docker stack rm postgres > /dev/null; sleep 20
    print_step "2. DELETINDO O VOLUME DO BANCO DE DADOS POSTGRES..."
    docker volume rm postgres_data > /dev/null
    print_step "3. Re-implantando Postgres com uma base de dados limpa..."
    env POSTGRES_PASSWORD="$POSTGRES_PASSWORD" docker stack deploy -c stacks/postgres.yaml postgres > /dev/null
    wait_for_service "postgres_postgres" "Postgres"
    print_step "4. Criando novo banco de dados 'n8n'..."
    docker exec "$(docker ps --filter "name=postgres_postgres" -q)" psql -U postgres -d postgres -c "CREATE DATABASE n8n;" > /dev/null
    print_step "5. Re-implantando o n8n..."
    env DOMINIO_N8N="$DOMINIO_N8N" WEBHOOK_N8N="$WEBHOOK_N8N" POSTGRES_PASSWORD="$POSTGRES_PASSWORD" N8N_KEY="$N8N_KEY" docker stack deploy -c stacks/n8n.yaml n8n > /dev/null
    wait_for_service "n8n_n8n-main" "n8n"
    print_ok "Reset do n8n concluído. Acesse a URL do n8n para criar uma nova conta de dono."
}

full_install() {
    if [ "$#" -lt 5 ]; then
        print_error "Parâmetros de instalação faltando."
        echo "Uso: curl ... | bash -s -- <email> <n8n.dominio> <portainer.dominio> <webhook.n8n> <evolution.dominio>"
        exit 1
    fi
    shift # Remove o nome do script (ou o '1' do menu) dos parâmetros
    SSL_EMAIL=$1; DOMINIO_N8N=$2; DOMINIO_PORTAINER=$3; WEBHOOK_N8N=$4; DOMINIO_EVOLUTION=$5
    LOG_FILE="instalador_quisera.log"; > "$LOG_FILE"
    
    print_header "ETAPA 1/7: Geração de Credenciais"
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
    print_ok "Credenciais seguras salvas em .env."

    print_header "ETAPA 2/7: Configuração do Servidor"
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
    print_ok "Servidor configurado (fuso horário, pacotes, swap)."

    print_header "ETAPA 3/7: Instalação do Docker e Swarm"
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1; sudo usermod -aG docker "$USER"
    fi
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        endereco_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+'); docker swarm init --advertise-addr "$endereco_ip" >> "$LOG_FILE" 2>&1
    fi
    if ! docker network ls | grep -q "network_public"; then
        docker network create --driver=overlay network_public >> "$LOG_FILE" 2>&1
    fi
    print_ok "Docker e Swarm prontos."
    
    print_header "ETAPA 4/7: Download dos Arquivos de Stack"
    STACKS_DIR="stacks"; REPO_BASE_URL="https://raw.githubusercontent.com/lonardonetto/instalador_stack/main/stacks"; mkdir -p "$STACKS_DIR"
    {
        curl -sSL "$REPO_BASE_URL/traefik.yaml" -o "$STACKS_DIR/traefik.yaml"; curl -sSL "$REPO_BASE_URL/portainer.yaml" -o "$STACKS_DIR/portainer.yaml"
        curl -sSL "$REPO_BASE_URL/postgres.yaml" -o "$STACKS_DIR/postgres.yaml"; curl -sSL "$REPO_BASE_URL/redis.yaml" -o "$STACKS_DIR/redis.yaml"
        curl -sSL "$REPO_BASE_URL/n8n.yaml" -o "$STACKS_DIR/n8n.yaml"; curl -sSL "$REPO_BASE_URL/evolution.yaml" -o "$STACKS_DIR/evolution.yaml"
    }
    print_ok "Arquivos .yaml baixados com sucesso."
    
    print_header "ETAPA 5/7: Implantação dos Serviços Principais"
    env SSL_EMAIL="$SSL_EMAIL" docker stack deploy -c "$STACKS_DIR/traefik.yaml" traefik >> "$LOG_FILE" 2>&1
    wait_for_service "traefik_traefik" "Traefik"
    env DOMINIO_PORTAINER="$DOMINIO_PORTAINER" docker stack deploy -c "$STACKS_DIR/portainer.yaml" portainer >> "$LOG_FILE" 2>&1
    wait_for_service "portainer_portainer" "Portainer"
    env POSTGRES_PASSWORD="$POSTGRES_PASSWORD" docker stack deploy -c "$STACKS_DIR/postgres.yaml" postgres >> "$LOG_FILE" 2>&1
    wait_for_service "postgres_postgres" "Postgres"
    docker stack deploy -c "$STACKS_DIR/redis.yaml" redis >> "$LOG_FILE" 2>&1
    wait_for_service "redis_redis" "Redis"
    
    print_header "ETAPA 6/7: Implantação da Evolution API"
    env DOMINIO_EVOLUTION="$DOMINIO_EVOLUTION" EVOLUTION_API_KEY="$EVOLUTION_API_KEY" MONGO_ROOT_USERNAME="$MONGO_ROOT_USERNAME" MONGO_ROOT_PASSWORD="$MONGO_ROOT_PASSWORD" docker stack deploy -c "$STACKS_DIR/evolution.yaml" evolution >> "$LOG_FILE" 2>&1
    wait_for_service "evolution_mongo" "MongoDB (Evolution)"
    wait_for_service "evolution_evolution" "Evolution API"
    
    print_header "ETAPA 7/7: Implantação e Configuração Final do n8n"
    print_step "Criando banco de dados 'n8n'..."
    docker exec "$(docker ps --filter "name=postgres_postgres" --format "{{.Names}}")" psql -U postgres -d postgres -c "CREATE DATABASE n8n;" < /dev/null >> "$LOG_FILE" 2>&1
    print_ok "Banco de dados criado."
    print_step "Implantando serviços do n8n..."
    env DOMINIO_N8N="$DOMINIO_N8N" WEBHOOK_N8N="$WEBHOOK_N8N" POSTGRES_PASSWORD="$POSTGRES_PASSWORD" N8N_KEY="$N8N_KEY" docker stack deploy -c "$STACKS_DIR/n8n.yaml" n8n >> "$LOG_FILE" 2>&1
    wait_for_service "n8n_n8n-worker" "n8n Worker"
    wait_for_service "n8n_n8n-main" "n8n Main"

    # --- Finalização ---
    cat << EOF

#####################################################################
#                                                                   #
#      ${C_GREEN}${C_BOLD}INSTALAÇÃO CONCLUÍDA - AGENCIA QUISERA - ACESSOS FINAIS${C_RESET}      #
#                                                                   #
#####################################################################

A sua stack de automação está pronta! Guarde estas informações.

---------------------------------------------------------------------
${C_CYAN}${C_BOLD}--> PORTAINER (Gerenciador de Containers)${C_RESET}
---------------------------------------------------------------------
- ${C_BOLD}URL de Acesso:${C_RESET} https://${DOMINIO_PORTAINER}
- ${C_BOLD}Instruções:${C_RESET}    No primeiro acesso, crie seu usuário administrador.

---------------------------------------------------------------------
${C_CYAN}${C_BOLD}--> N8N (Plataforma de Automação)${C_RESET}
---------------------------------------------------------------------
- ${C_BOLD}URL de Acesso:${C_RESET} https://${DOMINIO_N8N}
- ${C_BOLD}Instruções:${C_RESET}    No primeiro acesso, crie a conta do proprietário.

---------------------------------------------------------------------
${C_CYAN}${C_BOLD}--> EVOLUTION API (API para WhatsApp)${C_RESET}
---------------------------------------------------------------------
- ${C_BOLD}URL do Manager:${C_RESET} https://${DOMINIO_EVOLUTION}/manager
- ${C_BOLD}Sua API KEY:${C_RESET}    ${EVOLUTION_API_KEY}
- ${C_BOLD}Instruções:${C_RESET}     Acesse a URL do Manager para interagir com a API
                  e use a API KEY acima para criar sua instância.

#####################################################################

EOF
}

# --- MENU PRINCIPAL ---
clear
cat << "EOF"
                                   _    _
  ___ _ __   __ _ _ __ __ _ _   _  / \  | | __ _ ___ _ __
 / _ \ '_ \ / _` | '__/ _` | | | |/ _ \ | |/ _` / __| '_ \
|  __/ | | | (_| | | | (_| | |_| / ___ \| | (_| \__ \ |_) |
 \___|_| |_|\__, |_|  \__,_|\__, /_/   \_\_|\__,_|___/ .__/
            |___/          |___/                    |_|
EOF
echo -e "${C_CYAN}=================================================${C_RESET}"
echo -e "${C_CYAN}==   ${C_BOLD}GERENCIADOR DE STACK - AGÊNCIA QUISERA${C_RESET}    ==${C_RESET}"
echo -e "${C_CYAN}=================================================${C_RESET}"
echo "Escolha uma das opções abaixo:"
echo ""
echo -e "${C_YELLOW}[1]${C_RESET} Instalação Completa da Stack"
echo -e "${C_YELLOW}[2]${C_RESET} Reiniciar Portainer ${C_CYAN}(Corrigir Timeout de Login)${C_RESET}"
echo -e "${C_YELLOW}[3]${C_RESET} Resetar Senha do Portainer"
echo -e "${C_YELLOW}[4]${C_RESET} Resetar n8n ${C_RED}(Recriar Conta - APAGA TUDO)${C_RESET}"
echo -e "${C_YELLOW}[5]${C_RESET} Sair"
echo ""
read -p "Digite o número da opção desejada: " choice

case $choice in
    1)
        # Os parâmetros para a instalação vêm da linha de comando
        full_install "$@"
        ;;
    2)
        restart_portainer
        ;;
    3)
        reset_portainer_password
        ;;
    4)
        reconfigure_n8n
        ;;
    5)
        echo "Saindo."
        exit 0
        ;;
    *)
        print_error "Opção inválida."
        exit 1
        ;;
esac
