#!/bin/bash
# =================================================================
# ==        GERENCIADOR DE STACK - AGÊNCIA QUISERA               ==
# =================================================================
#
# Autor: Agência Quisera
# Versao: 4.0 - Robusta e à Prova de Falhas
#
# Este script serve como um instalador e ferramenta de manutenção
# para a stack de automação, com uma interface limpa e confiável.

# --- Funções de Exibição Limpa ---
print_header() {
    echo ""
    echo "#####################################################################"
    echo "# $1"
    echo "#####################################################################"
}

print_step() {
    echo "--> $1"
}

# --- Funções de Gerenciamento ---
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "[ERRO] Docker não está instalado. Execute a Instalação Completa (opção 1) primeiro."
        exit 1
    fi
}

restart_portainer() {
    check_docker
    print_header "REINICIANDO O PORTAINER"
    print_step "Forçando a reinicialização do serviço para corrigir o timeout de login..."
    docker service update --force portainer_portainer > /dev/null
    echo "[OK] Portainer reiniciado. Aguarde um minuto e tente acessar a URL novamente."
}

reset_portainer_password() {
    check_docker
    print_header "RESET DE SENHA DO PORTAINER"
    print_step "1. Parando o serviço do Portainer..."
    docker service scale portainer_portainer=0 > /dev/null; sleep 10
    print_step "2. Executando a ferramenta de reset..."
    echo "--> COPIE A SENHA TEMPORÁRIA GERADA ABAIXO:"
    docker run --rm -v portainer_data:/data portainer/helper-password-reset
    print_step "3. Reiniciando o serviço do Portainer..."
    docker service scale portainer_portainer=1 > /dev/null; sleep 5
    echo "[OK] Processo concluído! Use a senha temporária para fazer login e criar uma nova."
}

reconfigure_n8n() {
    check_docker
    source .env 2>/dev/null || true
    print_header "RESET COMPLETO DO N8N"
    echo "!!! AVISO !!! Esta ação irá APAGAR COMPLETAMENTE OS DADOS DO N8N (workflows, etc)."
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
    echo "[OK] Reset do n8n concluído. Acesse a URL do n8n para criar uma nova conta."
}

full_install() {
    # 'set -e' garante que o script pare imediatamente se algum comando falhar.
    set -e

    print_header "INSTALAÇÃO COMPLETA - CONFIGURAÇÃO INTERATIVA"
    read -p "Digite o e-mail para o certificado SSL: " SSL_EMAIL
    read -p "Digite o domínio para o n8n (ex: n8n.meusite.com): " DOMINIO_N8N
    read -p "Digite o domínio para o Portainer (ex: portainer.meusite.com): " DOMINIO_PORTAINER
    read -p "Digite o domínio para os Webhooks do n8n (ex: webhook.meusite.com): " WEBHOOK_N8N
    read -p "Digite o domínio para a Evolution API (ex: evo.meusite.com): " DOMINIO_EVOLUTION
    if [[ -z "$SSL_EMAIL" || -z "$DOMINIO_N8N" ]]; then echo "[ERRO] Campos obrigatórios não preenchidos."; exit 1; fi
    
    LOG_FILE="instalador_quisera.log"; > "$LOG_FILE"
    
    print_header "ETAPA 1/7: Geração de Credenciais"
    N8N_KEY=$(openssl rand -hex 16); POSTGRES_PASSWORD=$(openssl rand -base64 12);
    EVOLUTION_API_KEY=$(openssl rand -hex 20); MONGO_ROOT_USERNAME="quisera";
    MONGO_ROOT_PASSWORD=$(openssl rand -base64 12);
    { echo "SSL_EMAIL=$SSL_EMAIL"; echo "DOMINIO_N8N=$DOMINIO_N8N"; echo "WEBHOOK_N8N=$WEBHOOK_N8N"; echo "DOMINIO_PORTAINER=$DOMINIO_PORTAINER"; echo "DOMINIO_EVOLUTION=$DOMINIO_EVOLUTION"; echo "N8N_KEY=$N8N_KEY"; echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD"; echo "EVOLUTION_API_KEY=$EVOLUTION_API_KEY"; echo "MONGO_ROOT_USERNAME=$MONGO_ROOT_USERNAME"; echo "MONGO_ROOT_PASSWORD=$MONGO_ROOT_PASSWORD"; } > .env
    echo "[OK] Credenciais seguras salvas em .env."
    
    print_header "ETAPA 2/7: Configuração do Servidor"
    { sudo timedatectl set-timezone America/Sao_Paulo; sudo apt-get update -y && sudo apt-get upgrade -y -qq; sudo apt-get install -y -qq apparmor-utils curl lsb-release ca-certificates apt-transport-https software-properties-common gnupg2; if ! grep -q "/swapfile" /etc/fstab; then sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab; fi; } >> "$LOG_FILE" 2>&1
    echo "[OK] Servidor configurado."
    
    print_header "ETAPA 3/7: Instalação do Docker e Swarm"
    if ! command -v docker &> /dev/null; then
        print_step "Docker não encontrado. Instalando..."
        curl -fsSL https://get.docker.com | bash
        sudo usermod -aG docker "$USER"
        echo "[AVISO] Pode ser necessário sair e logar novamente para o usuário '$USER' usar docker sem sudo."
    else
        print_step "Docker já está instalado."
    fi
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        endereco_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+'); docker swarm init --advertise-addr "$endereco_ip"
    fi
    if ! docker network ls | grep -q "network_public"; then
        docker network create --driver=overlay network_public
    fi
    echo "[OK] Docker e Swarm prontos."
    
    print_header "ETAPA 4/7: Download dos Arquivos de Stack"
    STACKS_DIR="stacks"; REPO_BASE_URL="https://raw.githubusercontent.com/lonardonetto/instalador_stack/main/stacks"; mkdir -p "$STACKS_DIR"
    { curl -sSL "$REPO_BASE_URL/traefik.yaml" -o "$STACKS_DIR/traefik.yaml"; curl -sSL "$REPO_BASE_URL/portainer.yaml" -o "$STACKS_DIR/portainer.yaml"; curl -sSL "$REPO_BASE_URL/postgres.yaml" -o "$STACKS_DIR/postgres.yaml"; curl -sSL "$REPO_BASE_URL/redis.yaml" -o "$STACKS_DIR/redis.yaml"; curl -sSL "$REPO_BASE_URL/n8n.yaml" -o "$STACKS_DIR/n8n.yaml"; curl -sSL "$REPO_BASE_URL/evolution.yaml" -o "$STACKS_DIR/evolution.yaml"; }
    echo "[OK] Arquivos .yaml baixados."

    print_header "ETAPA 5/7: Implantação dos Serviços"
    env SSL_EMAIL="$SSL_EMAIL" docker stack deploy -c "$STACKS_DIR/traefik.yaml" traefik
    env DOMINIO_PORTAINER="$DOMINIO_PORTAINER" docker stack deploy -c "$STACKS_DIR/portainer.yaml" portainer
    env POSTGRES_PASSWORD="$POSTGRES_PASSWORD" docker stack deploy -c "$STACKS_DIR/postgres.yaml" postgres
    docker stack deploy -c "$STACKS_DIR/redis.yaml" redis
    env DOMINIO_EVOLUTION="$DOMINIO_EVOLUTION" EVOLUTION_API_KEY="$EVOLUTION_API_KEY" MONGO_ROOT_USERNAME="$MONGO_ROOT_USERNAME" MONGO_ROOT_PASSWORD="$MONGO_ROOT_PASSWORD" docker stack deploy -c "$STACKS_DIR/evolution.yaml" evolution
    echo "[OK] Deploy dos serviços iniciado."
    
    print_header "ETAPA 6/7: Configuração Final do n8n"
    print_step "Aguardando serviços essenciais ficarem online (pode levar alguns minutos)..."
    sleep 60 # Aguarda os serviços subirem
    print_step "Criando banco de dados do n8n..."
    docker exec "$(docker ps --filter "name=postgres_postgres" -q)" psql -U postgres -d postgres -c "CREATE DATABASE n8n;" < /dev/null
    print_step "Implantando n8n..."
    env DOMINIO_N8N="$DOMINIO_N8N" WEBHOOK_N8N="$WEBHOOK_N8N" POSTGRES_PASSWORD="$POSTGRES_PASSWORD" N8N_KEY="$N8N_KEY" docker stack deploy -c "$STACKS_DIR/n8n.yaml" n8n
    echo "[OK] Deploy do n8n iniciado."

    print_header "ETAPA 7/7: FINALIZAÇÃO"
    cat << EOF

#####################################################################
#                                                                   #
#        INSTALAÇÃO CONCLUÍDA - AGENCIA QUISERA - ACESSOS FINAIS      #
#                                                                   #
#####################################################################
A sua stack de automação está pronta! Guarde estas informações.
---------------------------------------------------------------------
--> PORTAINER (Gerenciador de Containers)
- URL de Acesso: https://${DOMINIO_PORTAINER}
- Instruções:    No primeiro acesso, crie seu usuário administrador.
---------------------------------------------------------------------
--> N8N (Plataforma de Automação)
- URL de Acesso: https://${DOMINIO_N8N}
- Instruções:    No primeiro acesso, crie a conta do proprietário.
---------------------------------------------------------------------
--> EVOLUTION API (API para WhatsApp)
- URL do Manager: https://${DOMINIO_EVOLUTION}/manager
- Sua API KEY:    ${EVOLUTION_API_KEY}
- Instruções:     Acesse a URL do Manager para interagir com a API.
#####################################################################
EOF
}

# --- MENU PRINCIPAL ---
main() {
    clear
    cat << "EOF"
                                   _    _
  ___ _ __   __ _ _ __ __ _ _   _  / \  | | __ _ ___ _ __
 / _ \ '_ \ / _` | '__/ _` | | | |/ _ \ | |/ _` / __| '_ \
|  __/ | | | (_| | | | (_| | |_| / ___ \| | (_| \__ \ |_) |
 \___|_| |_|\__, |_|  \__,_|\__, /_/   \_\_|\__,_|___/ .__/
            |___/          |___/                    |_|
=================================================================
==           GERENCIADOR DE STACK - AGÊNCIA QUISERA            ==
=================================================================
Escolha uma das opções abaixo:

[1] Instalação Completa da Stack
[2] Reiniciar Portainer (Corrigir Timeout de Login)
[3.0] Resetar Senha do Portainer
[4] Resetar n8n (Recriar Conta - APAGA TUDO)
[5] Sair
EOF
    echo ""
    read -p "Digite o número da opção desejada: " choice

    case $choice in
        1) full_install ;;
        2) restart_portainer ;;
        3) reset_portainer_password ;;
        4) reconfigure_n8n ;;
        5) echo "Saindo."; exit 0 ;;
        *) echo "[ERRO] Opção inválida."; exit 1 ;;
    esac
}

main "$@"
