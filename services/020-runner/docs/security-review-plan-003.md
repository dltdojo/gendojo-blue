# 資安評估報告 003 — Rootless DinD、關閉對外端口與本機 Registry 綁定

評估日期：2025-08-27  
評估範圍：services/020-runner（compose.yaml、runner-config.yaml、Dockerfile、Dockerfile.runner100、dind-daemon.json、runner.sh）  
此版主題：延續 002，完成「關閉 DinD 對外暴露」、改用「rootless dind」並將 Registry 綁定本機；盤點殘餘風險與最小修補。

## 一、現況摘要（相對於 002 的變更）
- DinD 型態與暴露面
  - 採用 image: docker:27-dind-rootless（rootless 模式）。
  - 未對宿主映射任何 TCP 埠（無 2375/2376 對外暴露）。
  - DOCKER_TLS_CERTDIR=/certs，並掛載共享卷 dind-certs。
  - 健康檢查：docker info；runner 以 depends_on: service_healthy 等待。
- Runner 與 DinD 互動
  - runner 環境變數仍為 DOCKER_HOST=tcp://docker:2376、DOCKER_TLS_VERIFY=1、DOCKER_CERT_PATH=/certs/client。
  - 但 dind-rootless 預設僅以 unix:///run/user/1000/docker.sock 服務；compose 未顯式啟用 dockerd TCP 2376（可能造成連線失敗的「配置偏差」）。
- Registry
  - registry:2 已綁定 127.0.0.1:5000（僅本機可達），同時在 dind-daemon.json 仍允許 insecure-registries: ["runner-registry:5000"]（容器間 HTTP）。
- Runner 映像與使用者
  - Dockerfile 安裝 CA 後，已切回非 root 使用者（USER 1000:1000）。
- Runner 設定
  - runner-config.yaml: runner.insecure 仍為 true（跳過對 Forgejo TLS 憑證驗證）。
- Token 管理
  - runner.sh 仍以環境變數 FORGEJO_RUNNER_TOKEN 提供註冊 token。

結論：已落實「關閉 DinD 對外端口」與「本機綁定 Registry」，並引入 rootless dind 降低風險；惟存在「runner→dind 連線配置偏差」、「對 Forgejo 驗證仍被略過」與「token 管理」等待收斂。

## 二、威脅模型（高層次）
- A：CI 工作（不受信任腳本）試圖取得 Docker 控制權橫向移動。
- B：DinD 若錯誤打開 TCP 對外（配置漂移），可能被遠端控制。
- C：私有 Registry 使用 HTTP（容器間），遭竄改或中間人攻擊。
- D：runner 對 Forgejo 略過憑證驗證（insecure: true），遭釣魚或 MITM。
- E：註冊 token 以環境變數傳遞，可能於日誌/程序/記憶體殘留。

## 三、控制與配置現況
- 隔離
  - 以 DinD（rootless）取代掛載宿主 /var/run/docker.sock，降低主機控制權暴露。
- 權限
  - Dockerfile 最終以 USER 1000:1000 執行；DinD 服務設 privileged: true（常見但仍高權限；rootless 下可評估移除）。
- 通訊
  - runner→dind：runner 設定走 tcp://docker:2376 + TLS；dind 實際只開 unix socket（預設）。
  - dind→registry：允許 HTTP（insecure-registries: runner-registry:5000）。
  - runner→Forgejo：runner.insecure: true（略過 TLS 驗證）。
- 可用性
  - dind 定義 healthcheck；runner 以 depends_on: service_healthy 啟動。

## 四、風險與緩解建議（依優先順序）
1) 修正 runner→dind 連線「配置偏差」
- 現況：runner 期待 tcp://docker:2376，但 dind-rootless 預設只提供 unix socket。
- 影響：Runner Docker client 可能無法連上 Daemon，導致 Job 失敗；若誤為解法而打開 0.0.0.0:2376，會再度擴大攻擊面。
- 建議（擇一）：
  - A. 啟用 dind 的 TLS TCP 2376 但僅容器內可達（不對宿主映射），並確保只綁定 0.0.0.0/容器內 interface；持續使用 dind-certs。
  - B. 改為讓 runner 透過 volume 共享 dind 的 unix socket（/run/user/1000/docker.sock），避免 TCP 面；此為容器間共享，非宿主 socket。
  - C. 若使用 buildkit/containerd 等替代，依實作更新連線與權限模型。

2) 關閉 runner 對 Forgejo 的「跳過 TLS 驗證」
- 現況：runner-config.yaml 設 insecure: true。
- 建議：改為 false，延用映像中已安裝的 CA（Dockerfile 已 COPY my-ca.crt 並 update-ca-certificates）。
- 效果：避免 MITM/DNS 污染導致註冊與執行階段被導向偽站。

3) 限縮與強化 Registry
- 現況：127.0.0.1:5000 對宿主僅本機可達；容器內 runner-registry:5000 走 HTTP。
- 建議：
  - 若需跨主機或更高保護，升級 Registry TLS 並移除 dind 的 insecure-registries；或保留僅內網用途並限制來源。
  - 固定鏡像 tag 與 digest，導入簽章（cosign/notary）與掃描（Trivy/Grype）。

4) 特權 DinD 的進一步抑制
- 現況：privileged: true 搭配 rootless dind。
- 建議：
  - 驗證在 rootless 模式下移除 privileged 是否可行；若需權能，配合 seccomp/AppArmor/SELinux 與 read-only fs 逐步硬化。
  - 分離網段、最小化可達面。

5) Runner 註冊 Token 處理
- 現況：runner.sh 從環境變數讀取 FORGEJO_RUNNER_TOKEN。
- 建議：
  - 使用 Compose secrets 或只讀檔案掛載提供 token；註冊後即清除。
  - 僅在一次性註冊容器中使用，避免長駐環境殘留。

6) 建置鏈與供應鏈安全
- 建議：
  - 鎖定 base image 版本（含 digest）。
  - 對關鍵映像進行簽章與掃描；在 CI 設 Gate。

## 五、建議的最小變更（不影響現有流程）
- compose.yaml：
  - 修正 runner↔dind 連線方式（啟用容器內 2376 + TLS；或共享 unix socket）。
  - 針對 rootless dind 驗證是否可移除 privileged。
- runner-config.yaml：
  - runner.insecure: false。
- 文件/作業：
  - 標註 Registry 現行為本機用途；跨主機請改用 TLS 與存取控制。

## 六、驗收要點（成功準則）
- 連線：runner 能成功與 DinD 互通並完成 Job；未對宿主映射 2375/2376。
- Forgejo：runner 在 insecure: false 下能正常註冊與執行工作。
- Registry：
  - 本機推送：127.0.0.1:5000 可正常推送/拉取。
  - 容器內：runner-registry:5000 能供 DinD 拉取；如升級為 TLS，insecure-registries 移除後仍可用。
- 風險面：
  - 外部掃描無 2375/2376 暴露；DinD 僅內部可達。
  - 若移除 privileged，DinD/Runner 功能測試皆通過。

## 七、後續 Roadmap（可選強化）
- 導入 rootless DinD 的進一步硬化（移除 privileged、seccomp/AppArmor/SELinux、read-only fs）。
- 升級 Registry TLS 與簽章/掃描；建立 SBOM 與漏洞 Gate。
- 建立安全事件日誌收集與告警（Loki/Elastic 等）。
- 以 IaC（Terraform/Ansible）固化本評估與硬化設定。

---

評估人員：GitHub Copilot  
文件版本：003  
下次複審建議：2025-11-27 之前（或每次重大配置變更後）
