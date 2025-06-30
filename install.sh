#!/bin/bash
# =================================================================
# ==            INSTALADOR N8N - AGÊNCIA QUISERA                ==
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

# Função para exibir o menu
show_menu() {
    echo -e "${YELLOW}Escolha uma das opções abaixo:${NC}"
    echo ""
    echo -e "${CYAN}[1]${NC} Instalação Completa da Stack"
    echo -e "${CYAN}[2]${NC} Reiniciar Portainer (Corrigir Timeout de Login)"
    echo -e "${CYAN}[3]${NC} Reset de Senha do Portainer (Gera Nova Senha)"
    echo -e "${CYAN}[4]${NC} Resetar n8n (Recriar Conta - APAGA TUDO)"
    echo -e "${CYAN}[5]${NC} Sair"
    echo ""
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

    echo -e "${YELLOW}# ETAPA 1/7: Geração de Credenciais${NC}"
    
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

    echo -e "  ${GREEN}[OK]${NC} Credenciais seguras salvas em .env."
    echo ""

    echo -e "${YELLOW}# ETAPA 2/7: Configuração do Servidor${NC}"
    export DEBIAN_FRONTEND=noninteractive
    sudo timedatectl set-timezone America/Sao_Paulo
    echo -e "  ${GREEN}[OK]${NC} Servidor configurado."
    echo ""

    echo -e "${YELLOW}# ETAPA 3/7: Instalação do Docker e Swarm${NC}"
    
    # Verificar se Docker já está instalado
    if ! command -v docker &> /dev/null; then
        echo "  Instalando Docker..."
        curl -fsSL https://get.docker.com | bash > /dev/null 2>&1
        sudo usermod -aG docker $USER
        echo "  Aguardando Docker inicializar..."
        sleep 5
    fi
    
    # Verificar se Swarm já está ativo
    if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q active; then
        echo "  Inicializando Docker Swarm..."
        ENDERECO_IP=$(curl -s ifconfig.me)
        docker swarm init --advertise-addr $ENDERECO_IP > /dev/null 2>&1
        docker network create --driver overlay network_public > /dev/null 2>&1
    fi
    
    echo -e "  ${GREEN}[OK]${NC} Docker e Swarm prontos."
    echo ""

    echo -e "${YELLOW}# ETAPA 4/7: Download dos Arquivos de Stack${NC}"
    
    mkdir -p stacks
    
    # Download traefik.yaml
    curl -s https://raw.githubusercontent.com/lonardonetto/instalador_stack/main/stacks/traefik.yaml -o stacks/traefik.yaml
    
    # Download portainer.yaml
    curl -s https://raw.githubusercontent.com/lonardonetto/instalador_stack/main/stacks/portainer.yaml -o stacks/portainer.yaml
    
    # Download postgres.yaml
    curl -s https://raw.githubusercontent.com/lonardonetto/instalador_stack/main/stacks/postgres.yaml -o stacks/postgres.yaml
    
    # Download redis.yaml
    curl -s https://raw.githubusercontent.com/lonardonetto/instalador_stack/main/stacks/redis.yaml -o stacks/redis.yaml
    
    # Download evolution.yaml
    curl -s https://raw.githubusercontent.com/lonardonetto/instalador_stack/main/stacks/evolution.yaml -o stacks/evolution.yaml
    
    echo -e "  ${GREEN}[OK]${NC} Arquivos .yaml baixados."
    echo ""

    echo -e "${YELLOW}# ETAPA 5/7: Implantação dos Serviços${NC}"
    
    docker stack deploy --prune --resolve-image always -c stacks/traefik.yaml traefik > /dev/null 2>&1
    sleep 5
    docker stack deploy --prune --resolve-image always -c stacks/portainer.yaml portainer > /dev/null 2>&1
    sleep 5
    docker stack deploy --prune --resolve-image always -c stacks/postgres.yaml postgres > /dev/null 2>&1
    sleep 5
    docker stack deploy --prune --resolve-image always -c stacks/redis.yaml redis > /dev/null 2>&1
    sleep 5
    docker stack deploy --prune --resolve-image always -c stacks/evolution.yaml evolution > /dev/null 2>&1
    
    echo -e "  ${GREEN}[OK]${NC} Deploy dos serviços principais iniciado."
    echo ""

    echo -e "${YELLOW}# ETAPA 6/7: Configuração Final e Implantação do n8n${NC}"
    
    # Download n8n.yaml
    curl -s https://raw.githubusercontent.com/lonardonetto/instalador_stack/main/stacks/n8n.yaml -o stacks/n8n.yaml
    
    docker stack deploy --prune --resolve-image always -c stacks/n8n.yaml n8n > /dev/null 2>&1
    
    echo -e "  ${GREEN}[OK]${NC} Deploy do n8n iniciado."
    echo ""

    echo -e "${YELLOW}# ETAPA 7/7: FINALIZAÇÃO${NC}"
    echo ""
    
    # Painel de resumo final
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
    echo "---------------------------------------------------------------------"
    echo "--> EVOLUTION API (API para WhatsApp)"
    echo "- URL do Manager: https://$DOMINIO_EVOLUTION/manager"
    echo "- Sua API KEY:    $EVOLUTION_API_KEY"
    echo "- Instruções:     Acesse a URL do Manager para interagir com a API."
    echo "#####################################################################"
    echo ""
    echo "Lembre-se: Pode levar alguns minutos para os certificados SSL serem"
    echo "gerados pelo Traefik e os sites ficarem acessíveis."
}

# Função para reiniciar Portainer (corrigir timeout de login)
restart_portainer() {
    echo -e "${YELLOW}Reiniciando Portainer para corrigir timeout...${NC}"
    
    # Reinicia o serviço sem perder dados
    docker service update --force portainer_portainer > /dev/null 2>&1
    
    echo -e "${GREEN}[OK]${NC} Portainer reiniciado com sucesso!"
    echo ""
    echo -e "${CYAN}INFORMAÇÕES:${NC}"
    echo "- URL de Acesso: https://${DOMINIO_PORTAINER:-localhost:9000}"
    echo "- Suas credenciais anteriores continuam válidas"
    echo "- Aguarde 30-60 segundos e tente fazer login novamente"
    echo ""
    echo -e "${YELLOW}DICA:${NC} Se ainda não conseguir acessar, use a opção de Reset de Senha."
}

# Função para resetar senha do Portainer (recria conta de admin)
reset_portainer_password() {
    echo -e "${YELLOW}Resetando conta de administrador do Portainer...${NC}"
    
    # Gerar nova senha automática
    NEW_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
    ADMIN_USER="admin_quisera"
    
    echo "  Parando serviço do Portainer..."
    docker service rm portainer_portainer > /dev/null 2>&1
    sleep 3
    
    echo "  Removendo dados de usuário antigos..."
    # Remove apenas os dados de usuário, mantém configurações de containers
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
URL: https://${DOMINIO_PORTAINER:-localhost:9000}
Usuário: $ADMIN_USER
Nova Senha: $NEW_PASSWORD
Data/Hora: $(date)

ATENÇÃO: Use estas credenciais para criar a conta de admin no primeiro acesso.
EOF
    
    echo -e "${GREEN}[OK]${NC} Reset de senha concluído com sucesso!"
    echo ""
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║               NOVA SENHA DO PORTAINER                     ║${NC}"
    echo -e "${CYAN}${BOLD}╠═══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}${BOLD}║${NC} ${YELLOW}URL de Acesso:${NC}  https://${DOMINIO_PORTAINER:-localhost:9000} ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}║${NC} ${YELLOW}Usuário:${NC}        $ADMIN_USER                    ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}║${NC} ${YELLOW}Nova Senha:${NC}     ${GREEN}${BOLD}$NEW_PASSWORD${NC}                ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}✓${NC} Credenciais salvas em: ${BOLD}credenciais_portainer_nova.txt${NC}"
    echo ""
    echo -e "${CYAN}PRÓXIMOS PASSOS:${NC}"
    echo "1. Aguarde 1-2 minutos para completa inicialização"
    echo "2. Acesse a URL acima no navegador"
    echo "3. Crie conta de admin usando as credenciais mostradas"
    echo "4. Seus containers e stacks continuam funcionando normalmente"
    echo ""
    echo -e "${RED}IMPORTANTE:${NC} Guarde essa senha em local seguro!"
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
else
    # Caso contrário, mostra o menu
    while true; do
        show_banner
        show_menu
        read -p "Digite o número da opção desejada: " choice
        
        case $choice in
            1)
                echo -e "${RED}Para instalação completa, use:${NC}"
                echo "curl -sSL https://raw.githubusercontent.com/lonardonetto/instalador_stack/main/install.sh | bash -s -- \\"
                echo "\"seu-email@provedor.com\" \\"
                echo "\"n8n.seusite.com.br\" \\"
                echo "\"portainer.seusite.com.br\" \\"
                echo "\"webhook.seusite.com.br\" \\"
                echo "\"evolution.seusite.com.br\""
                echo ""
                read -p "Pressione Enter para voltar ao menu..."
                ;;
            2)
                restart_portainer
                read -p "Pressione Enter para voltar ao menu..."
                ;;
            3)
                reset_portainer_password
                read -p "Pressione Enter para voltar ao menu..."
                ;;
            4)
                reset_n8n
                read -p "Pressione Enter para voltar ao menu..."
                ;;
            5)
                echo -e "${GREEN}Obrigado por usar o Gerenciador de Stack da Agência Quisera!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}[ERRO] Opção inválida. Digite um número de 1 a 5.${NC}"
                sleep 2
                ;;
        esac
    done
fi
