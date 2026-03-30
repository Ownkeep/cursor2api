# ==== Stage 1: 构建阶段 (Builder) ====
FROM node:22-alpine AS builder

# 设置工作目录
WORKDIR /app

# 仅拷贝包配置并安装所有依赖项（利用 Docker 缓存层）
COPY package.json package-lock.json ./
RUN npm ci

# 拷贝项目源代码并执行 TypeScript 编译
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ==== Stage 2: 生产运行阶段 (Runner) ====
FROM node:22-alpine AS runner

WORKDIR /app

# 设置为生产环境
ENV NODE_ENV=production

# 增大 Node.js 堆内存上限，防止日志文件过大时加载 OOM（tesseract.js / js-tiktoken 初始化也有一定内存需求）
ENV NODE_OPTIONS="--max-old-space-size=4096"

# 出于安全考虑，避免使用 root 用户运行服务
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 cursor

# 拷贝包配置并仅安装生产环境依赖（极大减小镜像体积）
COPY package.json package-lock.json ./
RUN npm ci --omit=dev \
    && npm cache clean --force

# 从 builder 阶段拷贝编译后的产物
COPY --from=builder --chown=cursor:nodejs /app/dist ./dist

# 拷贝前端静态资源（日志查看器 Web UI）
COPY --chown=cursor:nodejs public ./public

# 创建日志目录并授权
RUN mkdir -p /app/logs && chown cursor:nodejs /app/logs

# 注意：config.yaml 不打包进镜像，通过 docker-compose volumes 挂载
# 如果未挂载，服务会使用内置默认值 + 环境变量

# 切换到非 root 用户
USER cursor

# 声明对外暴露的端口和持久化卷
EXPOSE 3010


# 启动服务
CMD ["npm", "start"]
