## 010-forgejo 資安評估報告（security-review-plan-001）

更新日期：2025-08-28

### 範圍與方法
- 範圍：`services/010-forgejo` 目錄內的所有程式與設定（含 `compose.yaml`、`forgejo.sh`、`forgejo.test.sh`、`forgejo-data/**`、`pki/**`）。
- 方法：靜態檢視 Docker Compose、Shell 腳本與 Forgejo/Gitea 設定檔，盤點憑證/金鑰/密碼等敏感資訊、公開服務面、備份與記錄、身分與權限控制等。

### 風險項目（由高至低，整體排序並編號）
1) 高風險：私鑰與敏感憑證被納入版控
   - 位置：
     - `pki/ca.key`、`pki/server.key`（CA 與 TLS 私鑰）
     - `forgejo-data/ssh/ssh_host_*_key`（SSH 主機私鑰）
     - `forgejo-data/gitea/jwt/private.pem`（JWT 私鑰）
     - `forgejo-data/gitea/gitea.db`、`forgejo-data/gitea/sessions/**`（包含使用者資料與工作階段）
   - 影響：任何取得原始碼倉者都可解密流量、偽造伺服器身分、脫庫並離線攻擊、重放/偽造 Session。
   - 建議：
     - 立即將上述檔案自 Git 歷史移除（含歷史重寫）並更換所有金鑰/憑證/密鑰與資料庫密碼、作廢所有既有 Session。
     - 將 `forgejo-data/`、`pki/`、備份檔案等加入 `.gitignore`，改用部署期生成與外部秘密管理（Docker Secrets、KMS、Vault）。

2) 高風險：應用層密鑰以明文寫入設定並被版控
   - 位置：`forgejo-data/gitea/conf/app.ini`
     - `[security].INTERNAL_TOKEN`
     - `[server].LFS_JWT_SECRET`
     - `[oauth2].JWT_SECRET`
   - 影響：能簽發或驗證內部/JWT/LFS token，導致全面繞過授權與資料外洩。
   - 建議：
     - 立即輪替所有密鑰，改由環境變數或 Secret 檔（不入版控）注入。
     - 將舊密鑰列入失效清單並審計存取紀錄。

3) 高風險：`REVERSE_PROXY_TRUSTED_PROXIES = *`
   - 位置：`forgejo-data/gitea/conf/app.ini` → `[security]`
   - 影響：信任任意 Proxy 轉發標頭，可能被偽造 `X-Forwarded-*` 導致來源 IP/協定混淆、存取控制繞過、產生日誌誤導。
   - 建議：限制為實際反向代理或容器網段（例如 `127.0.0.1, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16`）。

4) 高風險：OpenID 設定與註冊策略衝突
   - 位置：`forgejo-data/gitea/conf/app.ini` → `[service]` 與 `[openid]`
     - `DISABLE_REGISTRATION = true` 但 `ENABLE_OPENID_SIGNUP = true`
   - 影響：可能繞過一般註冊限制，透過 OpenID 自行註冊新帳號。
   - 建議：若需禁用自助註冊，請將 `ENABLE_OPENID_SIGNUP = false`，並改為受控的身分供應與同步。

5) 高風險：備份檔未加密、存放路徑未明確隔離
   - 位置：`forgejo.sh`（`backup_forgejo` 產生 `forgejo-backup-*.tgz`）
   - 影響：備份包含憑證、私鑰、資料庫、Session 等，若備份目錄或主機權限控管不足，將直接外洩。
   - 建議：
     - 強制備份加密（例如 age/gpg）與簽名，備份路徑預設置於受限目錄，權限 0700。
     - 在 CI/腳本層加上加密與完整性驗證步驟；明確標示與清理策略。

6) 中風險：Metrics 對外暴露風險
   - 位置：`compose.yaml` 與 `app.ini` → `[metrics].ENABLED = true`
   - 影響：若未受保護，可能暴露系統內部資訊與指標。
   - 建議：
     - 僅在內網啟用或以反向代理/驗證 Token 保護；或設定防火牆限制來源。

7) 中風險：`SECRET_KEY` 空值與金鑰管理不明
   - 位置：`forgejo-data/gitea/conf/app.ini` → `[security].SECRET_KEY` 空白
   - 影響：此金鑰用於加密；若未正確生成/持久化，將影響 Cookie/資料加解密一致性、造成潛在風險。
   - 建議：
     - 確認 Forgejo 已在資料目錄生成並持久化安全隨機金鑰；改以 Secret 管理並避免進入版控。

8) 中風險：資料殘留與文件不一致
   - 位置：`forgejo.sh` 的 `--stop` 說明宣稱會移除 volumes（`down -v`），實作僅 `docker compose down`
   - 影響：敏感資料可能保留在未預期的 volume 中；操作人員誤判資料已清除。
   - 建議：
     - 修正文案或補上 `-v` 選項並新增二次確認；補充「安全擦除」流程說明。

9) 中風險：使用 SQLite（預設）於類生產模式
   - 位置：`app.ini` → `[database].DB_TYPE = sqlite3`、`RUN_MODE = prod`
   - 影響：非純安全缺陷，但 SQLite 易受單檔存取與備份外洩風險、並發/耐久性較弱。
   - 建議：
     - 轉換為受管資料庫（PostgreSQL），權限最小化與網段隔離；加密磁碟或行層加密。

10) 低至中風險：容器強化不足
    - 位置：`compose.yaml`
    - 影響：缺少只讀根檔系統、能力削減、seccomp/profile 等硬化。
    - 建議：
      - 加上 `read_only: true`、`cap_drop: [ALL]`（按需允許）、`security_opt`、限制出站網路等。

11) 低風險：時區與本機時間掛載
    - 位置：`compose.yaml` 掛載 `/etc/timezone`、`/etc/localtime`
    - 影響：一般可接受；但需確保來源檔案完整性。
    - 建議：保留或改以容器內部時區設定，視環境政策調整。

12) 低風險：腳本操作健壯性與記錄
    - 位置：`forgejo.sh`（缺少 `set -euo pipefail`、錯誤處理與審計日誌）
    - 影響：錯誤情境下可能留下半成品狀態；不利稽核。
    - 建議：
      - 補強錯誤中止、日誌分級與審計留存；對敏感操作加二次確認。

### 立即修復（72 小時內）
- 從 Git 歷史移除並重新生成：`pki/**`、`forgejo-data/ssh/**`、`forgejo-data/gitea/jwt/private.pem`、`forgejo-data/gitea/gitea.db`、`forgejo-data/gitea/sessions/**`。
- 全面輪替密鑰：`INTERNAL_TOKEN`、`LFS_JWT_SECRET`、`[oauth2].JWT_SECRET`、JWT 私鑰、SSH 主機鍵、TLS/CA 鍵。
- 將 `forgejo-data/`、`pki/`、備份檔（如 `forgejo-backup-*.tgz`）加入 `.gitignore`，並於部署時生成或由 Secret 管理提供。
- 將 `[security].REVERSE_PROXY_TRUSTED_PROXIES` 改為受信來源清單（內網/Proxy 網段），避免 `*`。
- 關閉 `ENABLE_OPENID_SIGNUP`（若政策禁止自助註冊）。

### 中期改善（2–4 週）
- 備份加密與簽章、離線還原演練；明確備份保留/銷毀政策。
- 指標端點加保護：僅內網可達或以反向代理加認證/ACL。
- 修正 `--stop` 行為與說明一致，並提供「安全清除」模式。
- 容器強化（唯讀檔系統、能力削減、Seccomp/AppArmor、資源限制已設定但可再細化）。
- 將資料庫遷移至 PostgreSQL，權限最小化並使用 TLS/加密儲存。

### 長期治理（>1 個月）
- 導入集中式秘密管理（Vault/KMS/Docker Secrets），建立金鑰輪替與憑證生命週期管理（含自動化與稽核）。
- 建立變更審核與安全基線檢查（pre-commit、CI 機密掃描），避免敏感檔再次入庫。
- 強化記錄與監控：安全事件告警、審計日誌集中化與保存策略。

### 參考檔案（證據）
- `services/010-forgejo/compose.yaml`
- `services/010-forgejo/forgejo.sh`
- `services/010-forgejo/forgejo.test.sh`
- `services/010-forgejo/forgejo-data/gitea/conf/app.ini`
- `services/010-forgejo/forgejo-data/ssh/*`
- `services/010-forgejo/forgejo-data/gitea/jwt/private.pem`
- `services/010-forgejo/pki/*`

---
狀態：本報告針對目前倉庫狀態出具。若後續已移除敏感檔與輪替金鑰，請更新本報告並附上修復證據（提交紀錄、輪替紀錄、掃描結果）。
