#!/bin/bash
# =================================================================
# ==        GERENCIADOR DE STACK - AGÊNCIA QUISERA               ==
# =================================================================
#
# Autor: Agência Quisera
# Versao: 3.2 - Menu Interativo e Robusto
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
print_header() { echo -e "\n${C_BLUE}${C_BOLD}# $1${C_RESET}"; }
print_step() { echo -e "${C_YELLOW}- $1${C_RESET}"; }
print_ok() { echo -e "  ${C_GREEN}[OK]${C_RESET} $1"; }
print_error() { echo -e "${C_RED}[ERRO]${C_RESET} $1"; }

# --- Funções de Gerenciamento ---
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker não está instalado. Execute a Instalação Completa (opção 1) primeiro."
        exit 1
    fi
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
    docker service scale portainer_portainer=0 > /dev/null; sleep 10
    print_step "2. Executando a ferramenta de reset..."
    echo -e "${C_YELLOW}--> COPIE A SENHA TEMPORÁRIA ABAIXO:${C_RESET}"
    docker run --rm -v portainer_data:/data portainer/helper-password-reset
    print_step "3. Reiniciando o serviço do Portainer..."
    docker service scale portainer_portainer=1 > /dev/null; sleep 5
    print_ok "Processo concluído! Use a senha temporária para fazer login e criar uma nova."
}

reconfigure_n8n() {
    check_docker
    source .env 2>/dev/null || true
    print_header "RESET COMPLETO DO N8N"
    echo -e "${C_RED}${C_BOLD}!!! AVISO !!! Esta ação irá APAGAR COMPLETAMENTE OS DADOS DO N8N.${C_RESET}"
    read -p "Digite 'SIM' em maiúsculas para confirmar: " confirmation
    if [ "$confirmation" != "SIM" ]; then
        echo "Operação cancelada."; exit 0
    fi
    print_step "1. Removendo stacks do n8n e Postgres..."
    docker stack rm n8n > /dev/null; docker stack rm postgres > /dev/null; sleep 20
    print_step "2. DELETINDO O VOLUME DO BANCO DE DADOS POSTGRES..."
    docker volume rm postgres_data > /dev/null
    print_step "3. Re-implantando Postgres e n8n..."
    env POSTGRES_PASSWORD="$POSTGRES_PASSWORD" docker stack deploy -c stacks/postgres.yaml postgres > /dev/null
    sleep 40 # Aguarda o Postgres
    docker exec "$(docker ps --filter "name=postgres_postgres" -q)" psql -U postgres -d postgres -c "CREATE DATABASE n8n;" > /dev/null
    env DOMINIO_N8N="$DOMINIO_N8N" WEBHOOK_N8N="$WEBHOOK_N8N" POSTGRES_PASSWORD="$POSTGRES_PASSWORD" N8N_KEY="$N8N_KEY" docker stack deploy -c stacks/n8n.yaml n8n > /dev/null
    print_ok "Reset do n8n concluído. Acesse a URL do n8n para criar uma nova conta."
}

full_install() {
    local SSL_EMAIL DOMINIO_N8N DOMINIO_PORTAINER WEBHOOK_N8N DOMINIO_EVOLUTION
    # Se 5 argumentos foram passados, usa-os. Senão, pede interativamente.
    if [ "$#" -eq 5 ]; then
        SSL_EMAIL=$1; DOMINIO_N8N=$2; DOMINIO_PORTAINER=$3; WEBHOOK_N8N=$4; DOMINIO_EVOLUTION=$5
    else
        print_header "INSTALAÇÃO - CONFIGURAÇÃO INTERATIVA"
        read -p "Digite o e-mail para o certificado SSL: " SSL_EMAIL
        read -p "Digite o domínio para o n8n (ex: n8n.meusite.com): " DOMINIO_N8N
        read -p "Digite o domínio para o Portainer (ex: portainer.meusite.com): " DOMINIO_PORTAINER
        read -p "Digite o domínio para os Webhooks do n8n (ex: webhook.meusite.com): " WEBHOOK_N8N
        read -p "Digite o domínio para a Evolution API (ex: evo.meusite.com): " DOMINIO_EVOLUTION
        if [[ -z "$SSL_EMAIL" || -z "$DOMINIO_N8N" ]]; then print_error "Campos obrigatórios não preenchidos."; exit 1; fi
    fi
    
    LOG_FILE="instalador_quisera.log"; > "$LOG_FILE"
    
    print_header "ETAPA 1/7: Geração de Credenciais"
    N8N_KEY=$(openssl rand -hex 16); POSTGRES_PASSWORD=$(openssl rand -base64 12);
    EVOLUTION_API_KEY=$(openssl rand -hex 20); MONGO_ROOT_USERNAME="quisera";
    MONGO_ROOT_PASSWORD=$(openssl rand -base64 12);
    { echo "SSL_EMAIL=$SSL_EMAIL"; echo "DOMINIO_N8N=$DOMINIO_N8N"; echo "WEBHOOK_N8N=$WEBHOOK_N8N"; echo "DOMINIO_PORTAINER=$DOMINIO_PORTAINER"; echo "DOMINIO_EVOLUTION=$DOMINIO_EVOLUTION"; echo "N8N_KEY=$N8N_KEY"; echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD"; echo "EVOLUTION_API_KEY=$EVOLUTION_API_KEY"; echo "MONGO_ROOT_USERNAME=$MONGO_ROOT_USERNAME"; echo "MONGO_ROOT_PASSWORD=$MONGO_ROOT_PASSWORD"; } > .env
    print_ok "Credenciais seguras salvas em .env."
    
    # ... (O resto da lógica de instalação continua igual)
    print_header "ETAPA 2/7: Configuração do Servidor"
    { sudo timedatectl set-timezone America/Sao_Paulo; sudo apt-get update -y && sudo apt-get upgrade -y -qq; sudo apt-get install -y -qq apparmor-utils curl lsb-release ca-certificates apt-transport-https software-properties-common gnupg2; if ! grep -q "/swapfile" /etc/fstab; then sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab; fi; } >> "$LOG_FILE" 2>&1
    print_ok "Servidor configurado."
    print_header "ETAPA 3/7: Instalação do Docker e Swarm"
    if ! command -v docker &> /dev/null; then curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1; sudo usermod -aG docker "$USER"; fi
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then endereco_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+'); docker swarm init --advertise-addr "$endereco_ip" >> "$LOG_FILE" 2>&1; fi
    if ! docker network ls | grep -q "network_public"; then docker network create --driver=overlay network_public >> "$LOG_FILE" 2>&1; fi
    print_ok "Docker e Swarm prontos."
    print_header "ETAPA 4/7: Download dos Arquivos de Stack"
    STACKS_DIR="stacks"; REPO_BASE_URL="https://raw.githubusercontent.com/lonardonetto/instalador_stack/main/stacks"; mkdir -p "$STACKS_DIR"
    { curl -sSL "$REPO_BASE_URL/traefik.yaml" -o "$STACKS_DIR/traefik.yaml"; curl -sSL "$REPO_BASE_URL/portainer.yaml" -o "$STACKS_DIR/portainer.yaml"; curl -sSL "$REPO_BASE_URL/postgres.yaml" -o "$STACKS_DIR/postgres.yaml"; curl -sSL "$REPO_BASE_URL/redis.yaml" -o "$STACKS_DIR/redis.yaml"; curl -sSL "$REPO_BASE_URL/n8n.yaml" -o "$STACKS_DIR/n8n.yaml"; curl -sSL "$REPO_BASE_URL/evolution.yaml" -o "$STACKS_DIR/evolution.yaml"; }
    print_ok "Arquivos .yaml baixados."
    print_header "ETAPA 5/7: Implantação dos Serviços"
    env SSL_EMAIL="$SSL_EMAIL" docker stack deploy -c "$STACKS_DIR/traefik.yaml" traefik >> "$LOG_FILE" 2>&1
    env DOMINIO_PORTAINER="$DOMINIO_PORTAINER" docker stack deploy -c "$STACKS_DIR/portainer.yaml" portainer >> "$LOG_FILE" 2>&1
    env POSTGRES_PASSWORD="$POSTGRES_PASSWORD" docker stack deploy -c "$STACKS_DIR/postgres.yaml" postgres >> "$LOG_FILE" 2>&1
    docker stack deploy -c "$STACKS_DIR/redis.yaml" redis >> "$LOG_FILE" 2>&1
    env DOMINIO_EVOLUTION="$DOMINIO_EVOLUTION" EVOLUTION_API_KEY="$EVOLUTION_API_KEY" MONGO_ROOT_USERNAME="$MONGO_ROOT_USERNAME" MONGO_ROOT_PASSWORD="$MONGO_ROOT_PASSWORD" docker stack deploy -c "$STACKS_DIR/evolution.yaml" evolution >> "$LOG_FILE" 2>&1
    print_ok "Deploy dos serviços principais iniciado."
    print_header "ETAPA 6/7: Configuração Final e Implantação do n8n"
    sleep 40 # Aguarda os serviços subirem
    docker exec "$(docker ps --filter "name=postgres_postgres" -q)" psql -U postgres -d postgres -c "CREATE DATABASE n8n;" < /dev/null >> "$LOG_FILE" 2>&1
    env DOMINIO_N8N="$DOMINIO_N8N" WEBHOOK_N8N="$WEBHOOK_N8N" POSTGRES_PASSWORD="$POSTGRES_PASSWORD" N8N_KEY="$N8N_KEY" docker stack deploy -c "$STACKS_DIR/n8n.yaml" n8n >> "$LOG_FILE" 2>&1
    print_ok "Deploy do n8n iniciado."
    print_header "ETAPA 7/7: FINALIZAÇÃO"

    cat << EOF

#####################################################################
#                                                                   #
#      ${C_GREEN}${C_BOLD}INSTALAÇÃO CONCLUÍDA - AGENCIA QUISERA - ACESSOS FINAIS${C_RESET}      #
#                                                                   #
#####################################################################
A sua stack de automação está pronta! Guarde estas informações.
---------------------------------------------------------------------
${C_CYAN}${C_BOLD}--> PORTAINER (Gerenciador de Containers)${C_RESET}
- ${C_BOLD}URL de Acesso:${C_RESET} https://${DOMINIO_PORTAINER}
- ${C_BOLD}Instruções:${C_RESET}    No primeiro acesso, crie seu usuário administrador.
---------------------------------------------------------------------
${C_CYAN}${C_BOLD}--> N8N (Plataforma de Automação)${C_RESET}
- ${C_BOLD}URL de Acesso:${C_RESET} https://${DOMINIO_N8N}
- ${C_BOLD}Instruções:${C_RESET}    No primeiro acesso, crie a conta do proprietário.
---------------------------------------------------------------------
${C_CYAN}${C_BOLD}--> EVOLUTION API (API para WhatsApp)${C_RESET}
- ${C_BOLD}URL do Manager:${C_RESET} https://${DOMINIO_EVOLUTION}/manager
- ${C_BOLD}Sua API KEY:${C_RESET}    ${EVOLUTION_API_KEY}
- ${C_BOLD}Instruções:${C_RESET}     Acesse a URL do Manager para interagir com a API.
#####################################################################
EOF
}

# --- CONTROLE DE FLUXO PRINCIPAL ---

# Se argumentos são passados, executa a instalação direta.
if [ "$#" -gt 0 ]; then
    full_install "$@"
    exit 0
fi

# Se o script é 'pipado' sem argumentos, mostra erro e instrução.
if ! [ -t 0 ]; then
    print_error "Este script é interativo e não pode ser executado com pipe sem parâmetros."
    echo "Para o menu de gerenciamento, use: bash <(curl -sSL [URL_DO_SCRIPT])"
    echo "Para instalar diretamente, use:   curl -sSL [URL_DO_SCRIPT] | bash -s -- <params...>"
    exit 1
fi

# Se nenhum argumento é passado e não é 'pipado', mostra o menu.
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
    1) full_install ;;
    2) restart_portainer ;;
    3) reset_portainer_password ;;
    4) reconfigure_n8n ;;
    5) echo "Saindo."; exit 0 ;;
    *) print_error "Opção inválida."; exit 1 ;;
esac
