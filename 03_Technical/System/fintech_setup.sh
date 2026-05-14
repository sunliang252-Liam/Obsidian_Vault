#!/bin/bash

# ============================================================

# fintech_system 环境一键安装脚本

# 适用：Ubuntu 22.04/24.04 全新裸机，VPN已通

# ============================================================

set -e  # 任何步骤报错即停止

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step() { echo -e "\n${BLUE}========== $1 ==========${NC}"; }

# ============================================================

# 第一层：系统基础

# ============================================================

step “第一层：系统基础”

sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git vim build-essential ca-certificates gnupg lsb-release net-tools htop unzip software-properties-common
log “系统基础工具安装完成”

# ============================================================

# 第二层：Docker

# ============================================================

step “第二层：Docker”

if command -v docker &>/dev/null; then
warn “Docker 已存在，跳过安装”
else
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
log "Docker 安装完成"
fi

sudo apt install -y docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker
log "Docker 服务已启动"

# ============================================================

# 第三层：PostgreSQL（Docker）

# ============================================================
step "第三层：PostgreSQL"

if docker ps -a --format '{{.Names}}' | grep -q "^fintech_pg$"; then
  warn "fintech_pg 容器已存在，跳过创建"
  docker start fintech_pg 2>/dev/null || true
else
  sudo mkdir -p /data/postgres
  sudo chown -R 999:999 /data/postgres
  sg docker -c "docker run -d \
    --name fintech_pg \
    --restart always \
    -e POSTGRES_USER=postgres \
    -e POSTGRES_PASSWORD=fintech123 \
    -e POSTGRES_DB=fintech_db \
    -p 5432:5432 \
    -v /data/postgres:/var/lib/postgresql/data \
    postgres:15"
  log "PostgreSQL 容器启动完成"
fi

echo "等待 PostgreSQL 就绪..."
for i in {1..15}; do
  if sg docker -c "docker exec fintech_pg pg_isready -U postgres" &>/dev/null; then
    log "PostgreSQL 已就绪"
    break
  fi
  sleep 2
done

# ============================================================

# 第四层：NVIDIA 驱动检查

# ============================================================

step “第四层：NVIDIA 驱动”

warn "本机无 NVIDIA GPU，跳过驱动安装"

# ============================================================

# 第五层：Miniconda + Python 环境

# ============================================================

step "第五层：Miniconda + Python"

CONDA_DIR="$HOME/miniconda3"

if [ -d "$CONDA_DIR" ]; then
warn "Miniconda 已存在，跳过安装"
else
wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
bash /tmp/miniconda.sh -b -p "$CONDA_DIR"
rm /tmp/miniconda.sh
log "Miniconda 安装完成"
fi

# 初始化 conda

"$CONDA_DIR/bin/conda" init bash
source "$CONDA_DIR/etc/profile.d/conda.sh"

# 创建 fintech 环境

if conda env list | grep -q "^fintech"; then
warn "fintech 环境已存在，跳过创建" 
else
conda create -n fintech python=3.11 -y
log "fintech 环境创建完成"
fi

# 激活并安装 Python 包

conda activate fintech

pip install --upgrade pip -q
pip install -q tushare akshare pandas sqlalchemy psycopg2-binary jupyterlab python-dotenv requests numpy ipykernel

# 注册 Jupyter kernel

python -m ipykernel install --user --name fintech --display-name "Python (fintech)"
log "Python 环境配置完成"

# ============================================================

# 第六层：Ollama + 本地模型

# ============================================================

step “第六层：Ollama”

if command -v ollama &>/dev/null; then
warn “Ollama 已存在，跳过安装”
else
curl -fsSL https://ollama.com/install.sh | sh
log “Ollama 安装完成”
fi

sudo systemctl enable ollama
sudo systemctl start ollama
sleep 3

log “拉取 qwen2.5:7b（需要几分钟）…”
ollama pull qwen2.5:7b

log “拉取 llama3.1:8b（需要几分钟）…”
ollama pull llama3.1:8b

log “本地模型拉取完成”


# ============================================================
# 第七层：Google Gemini API 支撑 (替换原 Claude Code)
# ============================================================

step "第七层：Gemini AI 引擎配置"

# 切换到 fintech 环境进行安装
source "$CONDA_DIR/etc/profile.d/conda.sh"
conda activate fintech

# 安装 Gemini 官方 SDK
pip install -q -U google-generativeai
log "Gemini Python SDK 安装完成"

# 检查 .env 是否存在，并引导配置 Gemini Key
if [ ! -f "$HOME/fintech_system/config/.env" ]; then
    cp "$HOME/fintech_system/config/.env.example" "$HOME/fintech_system/config/.env"
    warn "已根据模板创建 .env，请记得填入你的 GEMINI_API_KEY"
fi

# 移除不再需要的 Node.js 检查（保持系统精简）
log "系统已就绪：已配置为使用 Gemini API 驱动 Fintech Agent"


# ============================================================

# 创建项目目录结构

# ============================================================

step “创建项目目录结构”

step "创建项目目录结构"

mkdir -p "$HOME/fintech_system"/{data,notebooks,agents,config,logs,scripts}

cat > "$HOME/fintech_system/config/.env.example" << 'EOF'
# Tushare Token
TUSHARE_TOKEN=your_token_here

# PostgreSQL
DB_HOST=localhost
DB_PORT=5432
DB_NAME=fintech_db
DB_USER=postgres
DB_PASSWORD=fintech123

# Google Gemini API Key (替代原 Claude Key)
GEMINI_API_KEY=your_gemini_api_key_here

# Tavily API (可选，用于联网搜索)
TAVILY_API_KEY=your_key_here
EOF

log "项目目录结构创建完成：$HOME/fintech_system/"

# ============================================================

# 验收检查

# ============================================================

step "验收检查"

echo ""
PASS=0
FAIL=0

check() {
  local desc="$1"
  local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $desc"
    ((PASS++))
  else
    echo -e "  ${RED}✗${NC} $desc"
    ((FAIL++))
  fi
}

check "Docker 运行中"              "docker info"
check "PostgreSQL 容器运行"        "docker exec fintech_pg pg_isready -U postgres"
check "conda fintech 环境存在"     "conda env list | grep -q '^fintech '"
check "tushare 可导入"             "source $CONDA_DIR/etc/profile.d/conda.sh && conda activate fintech && python -c 'import tushare'"
check "akshare 可导入"             "source $CONDA_DIR/etc/profile.d/conda.sh && conda activate fintech && python -c 'import akshare'"
check "Ollama 运行中"              "ollama list"
check "qwen2.5:7b 已下载"          "ollama list | grep -q 'qwen2.5:7b'"
check "llama3.1:8b 已下载"         "ollama list | grep -q 'llama3.1:8b'"
check "Node.js 已安装"             "node -v"
check "Claude Code 已安装"         "claude --version"

echo ""
echo -e "${GREEN}通过: $PASS${NC}  ${RED}失败: $FAIL${NC}"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  安装完成！下一步：${NC}"
echo -e "${GREEN}  1. 复制 .env.example → .env 并填入 Token${NC}"
echo -e "${GREEN}  2. conda activate fintech${NC}"
echo -e "${GREEN}  3. jupyter lab --notebook-dir=$HOME/fintech_system/notebooks${NC}"
echo -e "${GREEN}  4. 写第一个 Tushare → PostgreSQL 管道${NC}"
echo -e "${GREEN}========================================${NC}"
