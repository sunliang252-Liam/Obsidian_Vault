# v2rayA 开机自启配置记录

**日期：** 2026-04-23  
**设备：** liam-sun@liamsun-H81M-S1（Ubuntu Desktop）

---

## 当前状态

| 项目 | 状态 |
|------|------|
| v2raya systemd 服务 | `enabled`（开机自启） |
| 运行状态 | `active (running)` |
| 代理模式 | 透明代理 / TUN 模式 |
| 环境变量（http_proxy 等） | 空（不需要） |

---

## 工作原理

v2rayA 以 **透明代理（TUN）模式** 运行，流量在内核层由 xray 直接接管，无需配置应用层环境变量（`http_proxy` / `https_proxy` / `ALL_PROXY`）。

```
开机
 └─ systemd 自动启动 v2raya.service
     └─ xray 加载 /etc/v2raya/config.json
         └─ 透明代理接管所有流量
             └─ 直接可用，无需手动操作
```

---

## 关键命令

```bash
# 查看服务是否开机自启
systemctl is-enabled v2raya

# 查看当前运行状态
systemctl status v2raya

# 手动启动 / 停止 / 重启
sudo systemctl start v2raya
sudo systemctl stop v2raya
sudo systemctl restart v2raya

# 禁用开机自启（如需）
sudo systemctl disable v2raya
```

---

## 进程结构

```
v2raya (主进程, PID: 2822)
 └─ xray run --config=/etc/v2raya/config.json
```

- **v2raya 二进制：** `/usr/bin/v2raya`  
- **xray 二进制：** `/usr/local/bin/xray`  
- **配置文件：** `/etc/v2raya/config.json`  
- **systemd 单元文件：** `/lib/systemd/system/v2raya.service`

---

## 故障排除

| 症状 | 排查命令 |
|------|----------|
| 无法访问外网 | `systemctl status v2raya` |
| 服务未启动 | `sudo systemctl start v2raya` |
| 重启后失效 | `systemctl is-enabled v2raya`，若为 `disabled` 则执行 `sudo systemctl enable v2raya` |

---

## 结论

**`fixproxy` 指令已无需使用。** 系统在 v2rayA 配置为 `enabled` 后，开机即可直接使用代理，全程无需手动干预。
