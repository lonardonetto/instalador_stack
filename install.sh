#!/bin/bash
# =================================================================
# ==            INSTALADOR STACK - AGÊNCIA QUISERA             ==
# =================================================================

# Cores para terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Função para exibir o banner
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "    _    ____  _____ _   _  ____ ___    _      ___  _   _ ___  _____ ____      _    "
    echo "   / \\  / ___|| ____| \\ | |/ ___|_ _|  / \\    / _ \\| | | |_ _|/ ____|  _ \\    / \\   "
    echo "  / _ \\ | |  _|  _| |  \\| | |    | |  / _ \\  | | | | | | || | \\__ \\| |_) |  / _ \\  "
    echo " / ___ \\| |_| | |___| |\\  | |___ | | / ___ \\ | |_| | |_| || | ___) |  _ <  / ___ \\ "
    echo "/_/   \\_\\\\____|_____|_| \\_|\\____|___/_/   \\_\\ \\__\\_\\\\___/|___|____/|_| \\_\\/_/   \\_\\"
    echo -e "${NC}"
    echo -e "${BLUE}=================================================================${NC}"
    echo -e "${BLUE}==           GERENCIADOR DE STACK - AGÊNCIA QUISERA            ==${NC}"
    echo -e "${BLUE}=================================================================${NC}"
    echo ""
}

# Função para verificar se um serviço está rodando
check_service_health() {
    local service_name=$1
    local max_attempts=30
    local attempt=1
    
    echo "  Verificando status do $service_name..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker service ls --filter name=$service_name --format "{{.Replicas}}" | grep -q "1/1"; then
            echo -e "  ${GREEN}[OK]${NC} $service_name está rodando corretamente."
            return 0
        fi
        echo "  Tentativa $attempt/$max_attempts - Aguardando $service_name..."
        sleep 10
        ((attempt++))
    done
    
    echo -e "  ${RED}[ERRO]${NC} $service_name não iniciou corretamente após $((max_attempts * 10)) segundos."
    echo "  Logs do serviço:"
    docker service logs $service_name --tail 20
    return 1
}

# Função para verificar conectividade de rede
check_network_connectivity() {
    echo "  Verificando conectividade de rede..."
    
    if ! ping -c 1 google.com &> /dev/null; then
        echo -e "  ${RED}[ERRO]${NC} Sem conectividade com a internet."
        return 1
    fi
    
    echo -e "  ${GREEN}[OK]${NC} Conectividade de rede confirmada."
    return 0
}

# Função para atualizar sistema Ubuntu
update_ubuntu_system() {
    echo -e "${YELLOW}# ETAPA 1/9: Atualizando Sistema Ubuntu 20.04${NC}"
    
    if ! check_network_connectivity; then
        return 1
    fi
    
    echo "  Atualizando lista de pacotes..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -qq > /dev/null 2>&1
    
    echo "  Instalando dependências básicas..."
    sudo apt-get install -y -qq \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common \
        ufw \
        unzip \
        wget > /dev/null 2>&1
    
    echo "  Atualizando sistema..."
    sudo apt-get upgrade -y -qq > /dev/null 2>&1
    
    echo "  Configurando timezone..."
    sudo timedatectl set-timezone America/Sao_Paulo
    
    echo -e "  ${GREEN}[OK]${NC} Sistema Ubuntu atualizado e configurado."
    echo ""
    return 0
}

# Função para instalar Docker
install_docker() {
    echo -e "${YELLOW}# ETAPA 2/9: Instalação do Docker${NC}"
    
    # Verificar se Docker já está instalado
    if command -v docker &> /dev/null; then
        echo "  Docker já está instalado. Verificando versão..."
        docker --version
        echo -e "  ${GREEN}[OK]${NC} Docker já configurado."
        echo ""
        return 0
    fi
    
    echo "  Removendo versões antigas do Docker..."
    sudo apt-get remove -y -qq docker docker-engine docker.io containerd runc > /dev/null 2>&1
    
    echo "  Adicionando repositório oficial do Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    echo "  Instalando Docker..."
    sudo apt-get update -qq > /dev/null 2>&1
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null 2>&1
    
    echo "  Configurando usuário no grupo docker..."
    sudo usermod -aG docker $USER
    
    echo "  Iniciando e habilitando Docker..."
    sudo systemctl start docker
    sudo systemctl enable docker
    
    echo "  Aguardando Docker inicializar..."
    sleep 10
    
    # Verificar se Docker está funcionando
    if ! docker --version &> /dev/null; then
        echo -e "  ${RED}[ERRO]${NC} Docker não foi instalado corretamente."
        return 1
    fi
    
    echo -e "  ${GREEN}[OK]${NC} Docker instalado e configurado com sucesso."
    echo ""
    return 0
}

# Função para configurar Docker Swarm
setup_docker_swarm() {
    echo -e "${YELLOW}# ETAPA 3/9: Configuração do Docker Swarm${NC}"
    
    # Verificar se Swarm já está ativo
    if docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q active; then
        echo "  Docker Swarm já está ativo."
        echo -e "  ${GREEN}[OK]${NC} Swarm já configurado."
        echo ""
        return 0
    fi
    
    echo "  Obtendo IP público do servidor..."
    ENDERECO_IP=$(curl -s ifconfig.me)
    
    if [ -z "$ENDERECO_IP" ]; then
        echo "  Não foi possível obter IP público. Usando IP local..."
        ENDERECO_IP=$(hostname -I | awk '{print $1}')
    fi
    
    echo "  IP detectado: $ENDERECO_IP"
    echo "  Inicializando Docker Swarm..."
    
    if ! docker swarm init --advertise-addr $ENDERECO_IP > /dev/null 2>&1; then
        echo -e "  ${RED}[ERRO]${NC} Falha ao inicializar Docker Swarm."
        return 1
    fi
    
    echo "  Criando rede overlay..."
    if ! docker network create --driver overlay network_public > /dev/null 2>&1; then
        echo "  Rede overlay já existe ou erro na criação."
    fi
    
    echo -e "  ${GREEN}[OK]${NC} Docker Swarm configurado com sucesso."
    echo ""
    return 0
}

# Função para criar arquivo do Traefik
create_traefik_config() {
    cat > stacks/traefik.yaml << 'EOF'
version: "3.8"

services:
  traefik:
    image: traefik:v3.0
    command:
      - --log.level=INFO
      - --accesslog=true
      - --api.dashboard=true
      - --api.insecure=true
      - --providers.docker=true
      - --providers.docker.swarmmode=true
      - --providers.docker.exposedbydefault=false
      - --providers.docker.network=network_public
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --certificatesresolvers.letsencryptresolver.acme.httpchallenge=true
      - --certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web
      - --certificatesresolvers.letsencryptresolver.acme.email=${SSL_EMAIL}
      - --certificatesresolvers.letsencryptresolver.acme.storage=/letsencrypt/acme.json
      - --global.checknewversion=false
      - --global.sendanonymoususage=false
    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_certificates:/letsencrypt
    networks:
      - network_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure

volumes:
  traefik_certificates:

networks:
  network_public:
    external: true
EOF
}

# Função para criar arquivo do Portainer
create_portainer_config() {
    cat > stacks/portainer.yaml << 'EOF'
version: "3.8"

services:
  agent:
    image: portainer/agent:2.19.4
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - network_public
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  portainer:
    image: portainer/portainer-ce:2.19.4
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_portainer_data:/data
    networks:
      - network_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - traefik.enable=true
        - traefik.http.routers.portainer.rule=Host(`${DOMINIO_PORTAINER}`)
        - traefik.http.routers.portainer.entrypoints=websecure
        - traefik.http.routers.portainer.tls.certresolver=letsencryptresolver
        - traefik.http.services.portainer.loadbalancer.server.port=9000

volumes:
  portainer_portainer_data:

networks:
  network_public:
    external: true
EOF
}

# Função para criar arquivo do PostgreSQL
create_postgres_config() {
    cat > stacks/postgres.yaml << 'EOF'
version: "3.8"

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: postgres
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_postgres_data:/var/lib/postgresql/data
    networks:
      - network_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 1G
          cpus: '0.5'
      restart_policy:
        condition: on-failure

volumes:
  postgres_postgres_data:

networks:
  network_public:
    external: true
EOF
}

# Função para criar arquivo do Redis
create_redis_config() {
    cat > stacks/redis.yaml << 'EOF'
version: "3.8"

services:
  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis_redis_data:/data
    networks:
      - network_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          memory: 512M
          cpus: '0.25'
      restart_policy:
        condition: on-failure

volumes:
  redis_redis_data:

networks:
  network_public:
    external: true
EOF
}

# Função para criar arquivo do N8N com as variáveis solicitadas
create_n8n_config() {
    cat > stacks/n8n.yaml << 'EOF'
version: "3.8"

services:
  n8n:
    image: n8nio/n8n:latest
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres_postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=postgres
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_HOST=${DOMINIO_N8N}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${WEBHOOK_N8N}
      - GENERIC_TIMEZONE=America/Sao_Paulo
      - N8N_ENCRYPTION_KEY=${N8N_KEY}
      - N8N_USER_MANAGEMENT_DISABLED=false
      - N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true
      - N8N_RUNNERS_ENABLED=true
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
    volumes:
      - n8n_n8n_data:/home/node/.n8n
    networks:
      - network_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - traefik.enable=true
        - traefik.http.routers.n8n.rule=Host(`${DOMINIO_N8N}`)
        - traefik.http.routers.n8n.entrypoints=websecure
        - traefik.http.routers.n8n.tls.certresolver=letsencryptresolver
        - traefik.http.services.n8n.loadbalancer.server.port=5678
      resources:
        limits:
          memory: 2G
          cpus: '1.0'
      restart_policy:
        condition: on-failure

volumes:
  n8n_n8n_data:

networks:
  network_public:
    external: true
EOF
}

# Função para criar arquivo do Evolution API
create_evolution_config() {
    cat > stacks/evolution.yaml << 'EOF'
version: "3.8"

services:
  evolution:
    image: davidsongomes/evolution-api:v2.1.1
    environment:
      - SERVER_URL=https://${DOMINIO_EVOLUTION}
      - CORS_ORIGIN=*
      - CORS_METHODS=GET,POST,PUT,DELETE
      - CORS_CREDENTIALS=true
      - LOG_LEVEL=ERROR
      - LOG_COLOR=true
      - LOG_BAILEYS=error
      - DEL_INSTANCE=false
      - PROVIDER_HOST=127.0.0.1
      - PROVIDER_PORT=5656
      - PROVIDER_PREFIX=evolution
      - QRCODE_LIMIT=30
      - AUTHENTICATION_TYPE=apikey
      - AUTHENTICATION_API_KEY=${EVOLUTION_API_KEY}
      - AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
      - WEBSOCKET_ENABLED=true
      - WEBSOCKET_GLOBAL_EVENTS=false
      - CONFIG_SESSION_PHONE_CLIENT=EvolutionAPI
      - CONFIG_SESSION_PHONE_NAME=Chrome
      - QRCODE_COLOR=#198754
      - DATABASE_ENABLED=true
      - DATABASE_CONNECTION_URI=postgresql://postgres:${POSTGRES_PASSWORD}@postgres_postgres:5432/postgres?schema=evolution
      - DATABASE_CONNECTION_CLIENT_NAME=evolution_exchange
      - REDIS_ENABLED=true
      - REDIS_URI=redis://redis_redis:6379
      - REDIS_PREFIX_KEY=evolution_v2
      - CACHE_REDIS_ENABLED=true
      - CACHE_REDIS_URI=redis://redis_redis:6379
      - CACHE_REDIS_PREFIX_KEY=evolution_cache
      - CACHE_REDIS_TTL=604800
      - CACHE_LOCAL_ENABLED=false
    volumes:
      - evolution_evolution_instances:/evolution/instances
      - evolution_evolution_store:/evolution/store
    networks:
      - network_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - traefik.enable=true
        - traefik.http.routers.evolution.rule=Host(`${DOMINIO_EVOLUTION}`)
        - traefik.http.routers.evolution.entrypoints=websecure
        - traefik.http.routers.evolution.tls.certresolver=letsencryptresolver
        - traefik.http.services.evolution.loadbalancer.server.port=8080
      resources:
        limits:
          memory: 1G
          cpus: '0.5'
      restart_policy:
        condition: on-failure

volumes:
  evolution_evolution_instances:
  evolution_evolution_store:

networks:
  network_public:
    external: true
EOF
}

# Função de instalação completa
install_complete_stack() {
    show_banner
    echo -e "${GREEN}${BOLD}INICIANDO INSTALAÇÃO COMPLETA DA STACK${NC}"
    echo ""
    
    # Validação dos parâmetros
    if [ "$#" -ne 5 ]; then
        echo -e "${RED}Erro: Parâmetros insuficientes para instalação completa.${NC}"
        echo "Uso: $0 <email> <dominio-n8n> <dominio-portainer> <webhook-n8n> <dominio-evolution>"
        exit 1
    fi

    SSL_EMAIL=$1
    DOMINIO_N8N=$2
    DOMINIO_PORTAINER=$3
    WEBHOOK_N8N=$4
    DOMINIO_EVOLUTION=$5

    echo -e "${YELLOW}# CONFIGURAÇÃO INICIAL: Geração de Credenciais${NC}"
    
    # Gerar credenciais
    N8N_KEY=$(openssl rand -hex 16)
    POSTGRES_PASSWORD=$(openssl rand -base64 12)
    EVOLUTION_API_KEY=$(openssl rand -hex 20)

    # Criar arquivo .env
    cat > .env << EOF
SSL_EMAIL=$SSL_EMAIL
DOMINIO_N8N=$DOMINIO_N8N
WEBHOOK_N8N=$WEBHOOK_N8N
DOMINIO_PORTAINER=$DOMINIO_PORTAINER
DOMINIO_EVOLUTION=$DOMINIO_EVOLUTION
N8N_KEY=$N8N_KEY
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
EVOLUTION_API_KEY=$EVOLUTION_API_KEY
EOF

    # Exportar variáveis para uso nos docker-compose
    export SSL_EMAIL DOMINIO_N8N WEBHOOK_N8N DOMINIO_PORTAINER DOMINIO_EVOLUTION N8N_KEY POSTGRES_PASSWORD EVOLUTION_API_KEY

    echo -e "  ${GREEN}[OK]${NC} Credenciais seguras geradas e configuradas."
    echo ""

    # Executar instalação em etapas ordenadas
    update_ubuntu_system || { echo -e "${RED}Erro na atualização do sistema${NC}"; exit 1; }
    install_docker || { echo -e "${RED}Erro na instalação do Docker${NC}"; exit 1; }
    setup_docker_swarm || { echo -e "${RED}Erro na configuração do Swarm${NC}"; exit 1; }
    
    echo -e "${YELLOW}# ETAPA 4/9: Criando diretório e arquivos de configuração${NC}"
    mkdir -p stacks
    echo -e "  ${GREEN}[OK]${NC} Diretório stacks criado."
    
    echo -e "${YELLOW}# ETAPA 5/9: Instalação do Traefik (Proxy Reverso)${NC}"
    create_traefik_config
    docker stack deploy --prune --resolve-image always -c stacks/traefik.yaml traefik
    check_service_health "traefik_traefik" || { echo -e "${RED}Erro na instalação do Traefik${NC}"; exit 1; }
    
    echo -e "${YELLOW}# ETAPA 6/9: Instalação do Portainer (Gerenciador Docker)${NC}"
    create_portainer_config
    docker stack deploy --prune --resolve-image always -c stacks/portainer.yaml portainer
    check_service_health "portainer_portainer" || { echo -e "${RED}Erro na instalação do Portainer${NC}"; exit 1; }
    
    echo -e "${YELLOW}# ETAPA 7/9: Instalação dos Bancos de Dados${NC}"
    create_postgres_config
    docker stack deploy --prune --resolve-image always -c stacks/postgres.yaml postgres
    check_service_health "postgres_postgres" || { echo -e "${RED}Erro na instalação do PostgreSQL${NC}"; exit 1; }
    
    create_redis_config
    docker stack deploy --prune --resolve-image always -c stacks/redis.yaml redis
    check_service_health "redis_redis" || { echo -e "${RED}Erro na instalação do Redis${NC}"; exit 1; }
    
    echo -e "${YELLOW}# ETAPA 8/9: Instalação do N8N (Automação)${NC}"
    create_n8n_config
    docker stack deploy --prune --resolve-image always -c stacks/n8n.yaml n8n
    check_service_health "n8n_n8n" || { echo -e "${RED}Erro na instalação do N8N${NC}"; exit 1; }
    
    echo -e "${YELLOW}# ETAPA 9/9: Instalação do Evolution API (WhatsApp)${NC}"
    create_evolution_config
    docker stack deploy --prune --resolve-image always -c stacks/evolution.yaml evolution
    check_service_health "evolution_evolution" || { echo -e "${RED}Erro na instalação do Evolution${NC}"; exit 1; }

    echo ""
    echo "#####################################################################"
    echo "#                                                                   #"
    echo "#      INSTALAÇÃO CONCLUÍDA - AGENCIA QUISERA - ACESSOS FINAIS      #"
    echo "#                                                                   #"
    echo "#####################################################################"
    echo "A sua stack de automação está pronta! Guarde estas informações."
    echo "---------------------------------------------------------------------"
    echo "--> PORTAINER (Gerenciador de Containers)"
    echo "- URL de Acesso: https://$DOMINIO_PORTAINER"
    echo "- Instruções:    No primeiro acesso, crie seu usuário administrador."
    echo "---------------------------------------------------------------------"
    echo "--> N8N (Plataforma de Automação)"
    echo "- URL de Acesso: https://$DOMINIO_N8N"
    echo "- Instruções:    No primeiro acesso, crie a conta do proprietário."
    echo "- Recursos:      Community packages, runners e permissions habilitados."
    echo "---------------------------------------------------------------------"
    echo "--> EVOLUTION API (API para WhatsApp)"
    echo "- URL do Manager: https://$DOMINIO_EVOLUTION/manager"
    echo "- Sua API KEY:    $EVOLUTION_API_KEY"
    echo "- Instruções:     Acesse a URL do Manager para interagir com a API."
    echo "#####################################################################"
    echo ""
    echo "IMPORTANTE:"
    echo "- Pode levar 5-10 minutos para os certificados SSL serem gerados"
    echo "- Todas as credenciais foram salvas no arquivo .env"
    echo "- Todos os serviços foram verificados e estão funcionando"
    echo ""
    echo "STATUS DOS SERVIÇOS:"
    docker service ls
}

# Função para exibir o menu
show_menu() {
    echo -e "${YELLOW}Escolha uma das opções abaixo:${NC}"
    echo ""
    echo -e "${CYAN}[1]${NC} Instalação Completa da Stack"
    echo -e "${CYAN}[2]${NC} Verificar Status dos Serviços"
    echo -e "${CYAN}[3]${NC} Reiniciar Portainer (Corrigir Timeout de Login)"
    echo -e "${CYAN}[4]${NC} Reset de Senha do Portainer (Gera Nova Senha)"
    echo -e "${CYAN}[5]${NC} Resetar n8n (Recriar Conta - APAGA TUDO)"
    echo -e "${CYAN}[6]${NC} Sair"
    echo ""
}

# Função para verificar status dos serviços
check_services_status() {
    echo -e "${YELLOW}Verificando status de todos os serviços...${NC}"
    echo ""
    
    echo "=== STATUS DOS SERVIÇOS ==="
    docker service ls
    echo ""
    
    echo "=== LOGS RECENTES ==="
    echo "Traefik:"
    docker service logs traefik_traefik --tail 5 2>/dev/null || echo "Serviço não encontrado"
    echo ""
    echo "Portainer:"
    docker service logs portainer_portainer --tail 5 2>/dev/null || echo "Serviço não encontrado"
    echo ""
    echo "N8N:"
    docker service logs n8n_n8n --tail 5 2>/dev/null || echo "Serviço não encontrado"
    echo ""
    echo "Evolution:"
    docker service logs evolution_evolution --tail 5 2>/dev/null || echo "Serviço não encontrado"
    echo ""
}

# Função para reiniciar Portainer (corrigir timeout de login)
restart_portainer() {
    echo -e "${YELLOW}Reiniciando Portainer para corrigir timeout...${NC}"
    
    # Tentar ler o domínio do arquivo .env
    if [ -f ".env" ]; then
        DOMINIO_PORTAINER=$(grep "DOMINIO_PORTAINER=" .env | cut -d'=' -f2)
    fi
    
    # Se não conseguiu ler do .env, usar localhost como fallback
    if [ -z "$DOMINIO_PORTAINER" ]; then
        DOMINIO_PORTAINER="localhost:9000"
    fi
    
    # Reinicia o serviço sem perder dados
    docker service update --force portainer_portainer > /dev/null 2>&1
    
    echo -e "${GREEN}[OK]${NC} Portainer reiniciado com sucesso!"
    echo ""
    echo -e "${CYAN}INFORMAÇÕES:${NC}"
    echo "- URL de Acesso: https://$DOMINIO_PORTAINER"
    echo "- Suas credenciais anteriores continuam válidas"
    echo "- Aguarde 30-60 segundos e tente fazer login novamente"
    echo ""
    echo -e "${YELLOW}DICA:${NC} Se ainda não conseguir acessar, use a opção de Reset de Senha."
}

# Função para resetar senha do Portainer
reset_portainer_password() {
    echo -e "${YELLOW}Resetando conta de administrador do Portainer...${NC}"
    
    # Tentar ler o domínio do arquivo .env
    if [ -f ".env" ]; then
        DOMINIO_PORTAINER=$(grep "DOMINIO_PORTAINER=" .env | cut -d'=' -f2)
    fi
    
    # Se não conseguiu ler do .env, perguntar ao usuário
    if [ -z "$DOMINIO_PORTAINER" ]; then
        echo ""
        echo -e "${CYAN}Não foi possível detectar automaticamente o domínio do Portainer.${NC}"
        echo -n "Por favor, digite o domínio do Portainer (ex: portainer.seusite.com.br): "
        read DOMINIO_PORTAINER
        
        if [ -z "$DOMINIO_PORTAINER" ]; then
            echo -e "${RED}Erro: Domínio não informado. Cancelando operação.${NC}"
            return 1
        fi
    fi
    
    # Gerar nova senha automática
    NEW_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
    ADMIN_USER="admin_quisera"
    
    echo "  Parando serviço do Portainer..."
    docker service rm portainer_portainer > /dev/null 2>&1
    sleep 3
    
    echo "  Removendo dados de usuário antigos..."
    docker run --rm -v portainer_portainer_data:/data alpine:latest \
        sh -c "rm -f /data/portainer.db /data/portainer.key" > /dev/null 2>&1
    sleep 2
    
    echo "  Recriando serviço do Portainer..."
    docker stack deploy --prune --resolve-image always -c stacks/portainer.yaml portainer > /dev/null 2>&1
    
    echo "  Aguardando inicialização..."
    sleep 10
    
    # Salvar credenciais em arquivo
    cat > credenciais_portainer_nova.txt << EOF
=== NOVA CONTA DE ADMINISTRADOR - PORTAINER ===
URL: https://$DOMINIO_PORTAINER
Usuário: $ADMIN_USER
Nova Senha: $NEW_PASSWORD
Data/Hora: $(date)

ATENÇÃO: Use estas credenciais para criar a conta de admin no primeiro acesso.
EOF
    
    echo -e "${GREEN}[OK]${NC} Reset de senha concluído com sucesso!"
    echo ""
    echo "################################################################"
    echo "#               NOVA SENHA DO PORTAINER                       #"
    echo "################################################################"
    echo "URL de Acesso:  https://$DOMINIO_PORTAINER"
    echo "Usuário:        $ADMIN_USER"
    echo "Nova Senha:     $NEW_PASSWORD"
    echo "################################################################"
    echo ""
    echo "Credenciais salvas em: credenciais_portainer_nova.txt"
    echo ""
    echo "PRÓXIMOS PASSOS:"
    echo "1. Aguarde 1-2 minutos para completa inicialização"
    echo "2. Acesse a URL acima no navegador"
    echo "3. Crie conta de admin usando as credenciais mostradas"
    echo "4. Seus containers e stacks continuam funcionando normalmente"
    echo ""
    echo "IMPORTANTE: Guarde essa senha em local seguro!"
}

# Função para resetar n8n
reset_n8n() {
    echo -e "${YELLOW}Resetando n8n (ATENÇÃO: Todos os workflows serão perdidos)...${NC}"
    docker service rm n8n_n8n > /dev/null 2>&1
    sleep 3
    docker volume rm n8n_n8n_data > /dev/null 2>&1
    docker stack deploy --prune --resolve-image always -c stacks/n8n.yaml n8n > /dev/null 2>&1
    echo -e "${GREEN}[OK]${NC} n8n resetado. Você pode criar uma nova conta de proprietário."
}

# Lógica principal
if [ "$#" -eq 5 ]; then
    # Se foram passados 5 parâmetros, executa instalação direta
    install_complete_stack "$@"
elif [ -t 0 ]; then
    # Se está sendo executado em terminal interativo, mostra o menu
    while true; do
        show_banner
        show_menu
        echo -n "Digite o número da opção desejada: "
        read choice
        
        case $choice in
            1)
                echo -e "${RED}Para instalação completa, use:${NC}"
                echo "bash instalador_quisera.sh \\"
                echo "\"seu-email@provedor.com\" \\"
                echo "\"n8n.seusite.com.br\" \\"
                echo "\"portainer.seusite.com.br\" \\"
                echo "\"webhook.seusite.com.br\" \\"
                echo "\"evolution.seusite.com.br\""
                echo ""
                echo -n "Pressione Enter para voltar ao menu..."
                read
                ;;
            2)
                check_services_status
                echo -n "Pressione Enter para voltar ao menu..."
                read
                ;;
            3)
                restart_portainer
                echo -n "Pressione Enter para voltar ao menu..."
                read
                ;;
            4)
                reset_portainer_password
                echo -n "Pressione Enter para voltar ao menu..."
                read
                ;;
            5)
                reset_n8n
                echo -n "Pressione Enter para voltar ao menu..."
                read
                ;;
            6)
                echo -e "${GREEN}Obrigado por usar o Gerenciador de Stack da Agência Quisera!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}[ERRO] Opção inválida. Digite um número de 1 a 6.${NC}"
                sleep 2
                ;;
        esac
    done
else
    echo -e "${RED}Erro: Este script deve ser executado interativamente ou com parâmetros.${NC}"
    echo "Para instalação completa use:"
    echo "bash instalador_quisera.sh \"email\" \"dominio-n8n\" \"dominio-portainer\" \"webhook\" \"dominio-evolution\""
    exit 1
fi
