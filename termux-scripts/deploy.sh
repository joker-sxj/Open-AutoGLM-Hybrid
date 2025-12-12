#!/data/data/com.termux/files/usr/bin/bash
# Open-AutoGLM 混合方案 - Termux 一键部署脚本（修正版）
# 版本: 1.1.0

set -euo pipefail

PREFIX="/data/data/com.termux/files/usr"
export PATH="$PREFIX/bin:$PATH"
export PIP_DISABLE_PIP_VERSION_CHECK=1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

print_header() {
  echo ""
  echo "============================================================"
  echo "  Open-AutoGLM 混合方案 - 一键部署（Termux 修正版）"
  echo "  版本: 1.1.0"
  echo "============================================================"
  echo ""
}

ensure_termux() {
  if [ ! -d "/data/data/com.termux" ]; then
    print_error "此脚本必须在 Termux 中运行！"
    exit 1
  fi
}

check_network() {
  print_info "检查网络连接..."
  if curl -s https://mirrors.zju.edu.cn/termux/apt/termux-main/dists/stable/InRelease >/dev/null 2>&1; then
    print_success "网络连接正常"
  else
    print_error "网络连接失败（无法访问镜像/网络不通）。"
    exit 1
  fi
}

update_packages() {
  print_info "更新软件包列表..."
  pkg update -y
  print_success "软件包列表更新完成"
}

purge_all() {
  print_warning "开始彻底删除并重装：~/Open-AutoGLM、~/.autoglm、~/bin/autoglm"
  rm -rf ~/Open-AutoGLM ~/.autoglm ~/bin/autoglm
  sed -i '/source ~\/\.autoglm\/config\.sh/d' ~/.bashrc 2>/dev/null || true
  sed -i '/# AutoGLM 配置/d' ~/.bashrc 2>/dev/null || true
  print_success "清理完成"
}

install_system_dependencies() {
  print_info "安装必要系统依赖（含 Pillow 编译依赖、Rust 编译环境）..."

  pkg install -y python git curl wget \
    clang make pkg-config \
    rust \
    zlib libjpeg-turbo libpng freetype harfbuzz fribidi littlecms \
    libtiff libwebp openjpeg \
    openssl libffi

  print_success "系统依赖安装完成"
}

setup_venv() {
  print_info "配置 Python 虚拟环境（只在 venv 内使用 pip）..."
  mkdir -p ~/.autoglm

  if [ ! -d ~/.autoglm/venv ]; then
    python -m venv ~/.autoglm/venv
  fi

  # shellcheck disable=SC1090
  source ~/.autoglm/venv/bin/activate

  # 升级的是 venv 内 pip（Termux 允许）
  python -m pip install -U pip setuptools wheel

  print_success "虚拟环境就绪: ~/.autoglm/venv"
}

install_python_packages() {
  print_info "安装 Python 依赖包（venv）..."

  # 确保在 venv
  # shellcheck disable=SC1090
  source ~/.autoglm/venv/bin/activate

  # 这些是你脚本硬编码的依赖（可按需增减）
  python -m pip install --no-cache-dir pillow openai requests

  print_success "Python 依赖安装完成（venv）"
}

download_autoglm() {
  print_info "下载 Open-AutoGLM 项目..."
  cd ~

  if [ -d "Open-AutoGLM" ]; then
    print_warning "Open-AutoGLM 目录已存在，将直接删除重下（建议保证干净）"
    rm -rf Open-AutoGLM
  fi

  git clone https://github.com/zai-org/Open-AutoGLM.git
  print_success "Open-AutoGLM 下载完成"
}

install_autoglm() {
  print_info "安装 Open-AutoGLM（venv）..."
  cd ~/Open-AutoGLM

  # shellcheck disable=SC1090
  source ~/.autoglm/venv/bin/activate

  if [ -f "requirements.txt" ]; then
    python -m pip install --no-cache-dir -r requirements.txt
  fi

  python -m pip install --no-cache-dir -e .
  print_success "Open-AutoGLM 安装完成"
}

download_hybrid_scripts() {
  print_info "准备混合方案脚本目录..."
  mkdir -p ~/.autoglm

  cat > ~/.autoglm/phone_controller.py << 'PYTHON_EOF'
# 这个文件可后续替换为你的实际控制逻辑
pass
PYTHON_EOF

  print_success "混合方案脚本准备完成"
}

configure_grsai() {
  print_info "配置 GRS AI..."
  echo ""
  echo "请输入您的 GRS AI API Key:"
  read -r -p "API Key: " api_key

  if [ -z "${api_key:-}" ]; then
    print_warning "未输入 API Key，跳过配置"
    print_warning "可稍后手动配置: export PHONE_AGENT_API_KEY='your_key'"
    return
  fi

  cat > ~/.autoglm/config.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
export PHONE_AGENT_BASE_URL="https://api.grsai.com/v1"
export PHONE_AGENT_API_KEY="$api_key"
export PHONE_AGENT_MODEL="gpt-4-vision-preview"
export AUTOGLM_HELPER_URL="http://localhost:8080"
EOF

  if ! grep -q "source ~/.autoglm/config.sh" ~/.bashrc 2>/dev/null; then
    {
      echo ""
      echo "# AutoGLM 配置"
      echo "source ~/.autoglm/config.sh"
    } >> ~/.bashrc
  fi

  # shellcheck disable=SC1090
  source ~/.autoglm/config.sh

  print_success "GRS AI 配置完成"
}

create_launcher() {
  print_info "创建启动脚本 autoglm..."
  mkdir -p ~/bin

  cat > ~/bin/autoglm << 'LAUNCHER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e

# venv
source ~/.autoglm/venv/bin/activate

# 配置
if [ -f ~/.autoglm/config.sh ]; then
  source ~/.autoglm/config.sh
fi

cd ~/Open-AutoGLM
python -m phone_agent.cli
LAUNCHER_EOF

  chmod +x ~/bin/autoglm

  if ! grep -q 'export PATH=$PATH:~/bin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH=$PATH:~/bin' >> ~/.bashrc
  fi

  print_success "启动脚本创建完成：autoglm"
}

check_helper_app() {
  print_info "检查 AutoGLM Helper APP..."
  echo ""
  echo "请确保您已经:"
  echo "1. 安装了 AutoGLM Helper APK"
  echo "2. 开启了无障碍服务权限"
  echo ""

  read -r -p "是否已完成以上步骤? (y/n): " confirm
  if [ "$confirm" != "y" ]; then
    print_warning "请先完成以上步骤，然后重新运行部署脚本"
    exit 0
  fi

  print_info "测试 AutoGLM Helper 连接..."
  if curl -s http://localhost:8080/status >/dev/null 2>&1; then
    print_success "AutoGLM Helper 连接成功！"
  else
    print_warning "无法连接到 AutoGLM Helper（可稍后排查）"
  fi
}

show_completion() {
  print_success "部署完成！"
  echo ""
  echo "使用方法:"
  echo "  source ~/.bashrc"
  echo "  autoglm"
  echo ""
}

main() {
  print_header
  ensure_termux
  check_network

  read -r -p "是否彻底删除后重新安装? (y/n): " reset_confirm
  if [ "$reset_confirm" = "y" ]; then
    purge_all
  fi

  update_packages
  install_system_dependencies
  setup_venv
  install_python_packages
  download_autoglm
  install_autoglm
  download_hybrid_scripts
  configure_grsai
  create_launcher
  check_helper_app
  show_completion
}

main
