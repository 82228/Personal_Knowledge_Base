#!/usr/bin/env sh

# 1. 确保脚本出错时终止
set -e

# 2. 构建项目
npm run docs:build

# 3. 进入构建输出目录
cd .vitepress/dist

# 4. 初始化 git 并推送到 GitHub Pages 分支
git init
git add -A
git commit -m 'deploy: update site'

# 5. 推送到 gh-pages 分支
git push -f git@github.com:82228/blog-demo.git main:gh-pages

# 6. 返回上级目录
cd -
