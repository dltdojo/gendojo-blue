# 資安評估報告 002 — Runner 以 DinD 緩解設計

評估日期：2025-08-27  
評估範圍：services/020-runner（compose.yaml、runner-config.yaml、Dockerfile、Dockerfile.runner100、dind-daemon.json、runner.sh）  
此版主題：改採 Docker-in-Docker（DinD）以取代掛載宿主 /var/run/docker.sock 的風險，並盤點新風險與對策。

## 一、現況摘要（相對於 001 的變更）
- 已移除「直接掛載宿主 Docker Socket」的設計，改為獨立的 DinD 服務：
  - services.dind 使用 docker:27-dind，並啟用 DOCKER_TLS_CERTDIR、healthcheck。
  - runner 以 DOCKER_HOST=tcp://docker:2376，DOCKER_TLS_VERIFY=1 與 DinD 互動；使用 dind-certs:ro 掛載 TLS 憑證。
- 加入私有 Registry（registry:2），runner 透過 runner-registry:5000 拉取/推送映像；DinD 以 dind-daemon.json 設定 insecure-registries=["runner-registry:5000"].
- runner-config.yaml 現況為 runner.insecure: true（對 Forgejo 的 TLS 驗證被略過）。
- dind 服務目前對宿主開放 2375/2376 兩個埠口（compose.yaml ports），2375 為非 TLS 預設口，存在額外風險。

結論：DinD 成功降低「runner 容器取得宿主 Docker 完整控制權」的重大風險，但同時引入「特權 DinD」、「對外暴露 Docker TCP 連線」與「私有 HTTP Registry」等新風險，需搭配加固。

## 二、威脅模型（高層次）
- 攻擊面 A：Runner 執行第三方 CI 任務（可能惡意腳本），嘗試橫向取得 Docker 控制權。
- 攻擊面 B：DinD Daemon 若對外暴露（2375/2376），被遠端惡意用戶直接控制。
- 攻擊面 C：私有 Registry 為 HTTP（以 insecure-registries 放行），遭竄改或中間人攻擊。
- 攻擊面 D：對 Forgejo 的 TLS 憑證驗證被略過（runner.insecure: true），存在釣魚或 MITM 風險。

## 三、控制與配置現況
- 隔離控制：
  - 使用 DinD 將 Docker daemon 與宿主隔離，runner 僅能操控 DinD 內的容器。
- 身分與存取：
  - DinD 以 privileged: true 執行（dind 必要條件，仍具高權限）。
  - runner 註冊 token 以環境變數提供（runner.sh 讀取 FORGEJO_RUNNER_TOKEN）。
- 通訊安全：
  - runner → DinD：啟用 TLS（DOCKER_TLS_VERIFY=1；/certs/client）。
  - DinD → Registry：允許 HTTP（insecure-registries: runner-registry:5000）。
  - runner → Forgejo：runner-config.yaml 設 insecure: true（跳過 TLS 驗證）。
- 健康檢查：
  - DinD 有 healthcheck（docker info）。runner 以 depends_on: service_healthy 等待。

## 四、風險與緩解建議（依優先順序）
1) 關閉對宿主的 Docker TCP 暴露（最高優先）
- 現況：dind 對外開放 2375（非 TLS）與 2376（TLS）。runner 已可透過內部網路別名 docker 存取 DinD，無需宿主埠口。
- 建議：移除 dind.ports 的 2375/2376 對外映射；若確需宿主使用，至少：
  - 移除 2375；僅保留 2376，且綁定 127.0.0.1（例："127.0.0.1:2376:2376"）。
  - 以防火牆或 Docker --iptables 規則限制來源。

2) 關閉 runner 對 Forgejo 的「跳過 TLS 驗證」
- 現況：runner-config.yaml 設定 runner.insecure: true。
- 建議：改為 false，並延用鏡像中已安裝的 CA（Dockerfile 已 COPY my-ca.crt 並 update-ca-certificates）。
- 效果：避免遭遇中間人或 DNS 污染時被導到偽站。

3) 限縮 Registry 的暴露面
- 現況：registry 以 ports: "5000:5000" 對外開放，DinD 允許 HTTP。
- 建議：
  - 若僅供本機推送：改為 "127.0.0.1:5000:5000"，避免外網可達。
  - 若需容器間通訊：容器內走 runner-registry:5000；避免透過宿主埠對外提供。
  - 視需求升級為 TLS（憑證由專用 CA 簽發）並移除 DinD 的 insecure-registries。

4) 特權 DinD 的風險抑制
- 現況：privileged: true（DinD 傳統需求）。
- 建議（擇一或並行）：
  - 研究「rootless dind」（docker:27-dind-rootless）或以 containerd/buildkit 模式替代傳統 DinD。
  - 在可行範圍內加上 seccomp、AppArmor/SELinux 與 read-only filesystem 等硬化參數（DinD 兼容性需驗證）。
  - 將 DinD 與其他服務分離網段，最小化可達面。

5) Runner 註冊 Token 的處理
- 現況：runner.sh 從環境變數讀取並用於註冊命令列。
- 風險：命令列與環境在特定情境可能外洩（歷史、日誌、/proc）。
- 建議：
  - 以 Compose secrets 或掛載只讀檔案提供 token；用後即刪除。
  - 最小可視範圍：避免把 token 寫入長駐容器環境；僅在一次性註冊容器內使用。

6) 建置鏈安全
- 現況：runner 會從私有 Registry 拉取 node22-runner100 等映像；DinD 允許不安全 Registry。
- 建議：
  - 對產製映像簽章（cosign/notary）與掃描（Trivy/Grype）。
  - 固定 base image tag（含 digest）避免漂移。

## 五、建議的最小變更（不影響現有流程）
- compose.yaml：
  - dind 服務移除 ports 2375/2376。
  - registry 服務改為 "127.0.0.1:5000:5000"（若仍需由宿主推送）。
- runner-config.yaml：
  - runner.insecure: false。
- 文件/作業：
  - 明確標註 DinD 與 Registry 僅供本機/內部用途；外部存取需走 TLS 與存取控制。

## 六、驗收要點（成功準則）
- runner 仍可透過 DOCKER_HOST=tcp://docker:2376 與 DinD 正常執行工作（未映射宿主埠）。
- runner 能成功與 Forgejo 完成 TLS 驗證（insecure: false）。
- 本機若需 push 映像，能透過 127.0.0.1:5000 正常推送；容器內部以 runner-registry:5000 通。
- 風險面：
  - 宿主未再暴露 Docker TCP；外部掃描無 2375/2376 開放。
  - DinD 僅對內可達；Registry 僅本機可達或以 TLS 對外。

## 七、後續 Roadmap（可選強化）
- 導入 rootless DinD 或替代方案（buildkitd-in-docker / containerd + nerdctl）。
- 導入映像簽章與掃描；在 CI 中設置 Gate。
- 以 Loki/Elastic 收集 DinD/runner 安全事件日誌，建立告警規則。
- 以 Terraform/Ansible 將上述硬化設定基礎建設化（IaC）。

---

評估人員：GitHub Copilot  
文件版本：002  
下次複審建議：2025-11-27 之前（或每次重大配置變更後）
