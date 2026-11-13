---
tags:
  - 索引
  - 剪藏
---

# ✂️ 剪藏说明

> 用 `defuddle` 抽网页正文 + `knap` 套模板，把外部文章存成带 frontmatter 的干净笔记。
> 本目录下的 `.base` 是剪藏池视图，可按来源站/日期筛。

## 一键剪藏

```powershell
& "D:\Workspace\Obsidian_Vault\03_Technical\Tools\clip.ps1" -Url "https://..."
```

或者直接跟 DSH 说：**「把这篇存进来：<链接>」**。

## 它做了什么

1. `defuddle parse <url> --md --json` → 抽出正文与元数据
2. 清理导航噪音（开头链接块、纯链接列表项、iframe/img 广告容器、尾部「热点推荐」板块）
3. 补 `url` / `created` 字段（defuddle 不返回 url）
4. `knap render 05_Templates/剪藏模板.md` → 套模板渲染
5. 落盘本目录，文件名 `YYYY-MM-DD 标题.md`

## 产出的 frontmatter

| 字段 | 含义 |
|---|---|
| `title` | 网页标题 |
| `created` | 剪藏日期 |
| `url` | 原文链接 |
| `domain` | 来源站 |
| `author` | 作者（可能为空） |
| `published` | 原文发布日（可能为空） |
| `tags` | 固定含 `剪藏` |

## 实测兼容性（2026-11-13）

| 站点 | 结果 |
|---|---|
| 腾讯新闻 `news.qq.com` | ✅ 干净，正文无残留 |
| 维基百科 `zh.wikipedia.org` | ✅ 干净 |
| 东方财富 `finance.eastmoney.com` | ⚠️ 正文完整，但残留少量站点模板文字（「小 中 大」「东方财富APP」「来源：Choice数据」） |
| 需登录的（公众号/雪球/知识星球） | ❌ 大概率失败 |
| 纯 JS 渲染的页面 | ❌ 抽不到正文 |

## 已知边界

- 中文财经门户的模板噪音只能靠通用规则压，做不到零残留；要彻底干净得给单站写规则
- `clip.ps1` 用的是 **UTF-8 BOM** 保存（Windows PowerShell 5.1 读无 BOM 脚本会按 GBK 解析导致乱码）
- 目标文件已存在时脚本会报错退出，不覆盖
