# 資安評估報告 - Forgejo Runner 服務

**評估日期**: 2025年8月26日  
**評估範圍**: runner.sh, compose.yaml, Dockerfile  
**評估版本**: gendojo-blue/services/020-runner  

## 執行摘要

本次資安評估針對 Forgejo Runner 服務的部署配置進行分析，發現多項安全風險。主要問題包括特權存取、機敏資訊暴露、權限管理不當等。建議優先處理高風險項目。

## 發現問題清單 (依優先程度排列)

### 🔴 高風險 (Critical)

#### 1. Docker Socket 完整存取權限
**檔案**: `compose.yaml:11`
```yaml
- /var/run/docker.sock:/var/run/docker.sock
```
**風險描述**: 
- Runner 容器擁有對主機 Docker daemon 的完整存取權限
- 可能導致容器逃逸 (Container Escape)
- 攻擊者可在主機上執行任意容器和命令
- 等同於 root 權限存取主機系統

**影響程度**: 極高 - 完整主機控制權
**建議修復**:
- 使用 Docker-in-Docker (DinD) 替代 Docker Socket 掛載
- 實作 Docker Socket Proxy 限制可用 API
- 考慮使用 Kaniko 或 Buildah 等無特權建置工具

#### 2. 環境變數中的機敏資訊暴露
**檔案**: `runner.sh:57`
```bash
TOKEN="${FORGEJO_RUNNER_TOKEN:-}"
```
**風險描述**:
- Runner 註冊 token 透過環境變數傳遞
- Token 可能在程序列表中可見
- 日誌檔案可能記錄環境變數資訊
- 容器重啟時 token 可能被記錄

**影響程度**: 高 - 未授權存取 Forgejo 實例
**建議修復**:
- 使用 Docker Secrets 或檔案掛載方式傳遞 token
- 實作 token 輪替機制
- 在使用後立即清除記憶體中的 token

#### 3. 以 root 權限執行容器
**檔案**: `Dockerfile:13` (註解)
```dockerfile
# USER 1000:1000
```
**風險描述**:
- USER 指令被註解，容器以 root 權限執行
- 結合 Docker Socket 存取，風險更加嚴重
- 違反最小權限原則

**影響程度**: 高
**建議修復**:
- 取消註解 USER 1000:1000 指令
- 確保所有檔案權限正確設定
- 測試非 root 使用者執行的相容性

### 🟡 中風險 (High)

#### 4. 硬編碼服務名稱和網路設定
**檔案**: `runner.sh:66`
```bash
--instance https://forgejo.localtest.me
```
**檔案**: `compose.yaml:5-7`
```yaml
networks:
  forgejo:
    name: fj101_forgejo
    external: true
```
**風險描述**:
- 硬編碼的實例 URL 和網路名稱
- 缺乏設定驗證和清理
- 可能導致連線到錯誤的實例

**影響程度**: 中等
**建議修復**:
- 使用環境變數設定實例 URL
- 實作 URL 驗證機制
- 使用設定檔替代硬編碼值

#### 5. 不安全的權限修復方式
**檔案**: `runner.sh:76-79`
```bash
fix_data_permission() {
    docker run --rm -v "$(pwd)/runner-data:/data" busybox chown -R 1000:1000 /data
}
```
**風險描述**:
- 遞迴變更整個目錄權限
- 可能覆寫重要檔案的安全權限
- 使用外部容器進行權限操作

**影響程度**: 中等
**建議修復**:
- 使用更精確的權限設定
- 僅修改必要檔案的權限
- 考慮使用 init containers

#### 6. 缺乏輸入驗證和錯誤處理
**檔案**: `runner.sh:43-47`
```bash
cp "$PKI_CA_PATH" my-ca.crt
```
**風險描述**:
- 檔案路徑未進行清理和驗證
- 缺乏適當的錯誤處理機制
- 可能導致路徑遍歷攻擊

**影響程度**: 中等
**建議修復**:
- 實作輸入驗證
- 使用絕對路徑
- 加強錯誤處理邏輯

### 🟠 低風險 (Medium)

#### 7. 容器延遲啟動機制不當
**檔案**: `compose.yaml:10`
```yaml
command: '/bin/sh -c "sleep 5; forgejo-runner daemon"'
```
**風險描述**:
- 使用固定延遲而非適當的健康檢查
- 可能導致服務啟動競爭條件
- 不可靠的相依性管理

**影響程度**: 低
**建議修復**:
- 實作適當的健康檢查機制
- 使用 depends_on 與 healthcheck
- 替代固定延遲的啟動邏輯

#### 8. 缺乏日誌和監控設定
**檔案**: 所有檔案
**風險描述**:
- 無安全事件日誌記錄
- 缺乏異常行為監控
- 難以進行事件回應

**影響程度**: 低
**建議修復**:
- 實作結構化日誌記錄
- 設定安全事件監控
- 建立日誌輪替機制

#### 9. TLS 憑證驗證設定
**檔案**: `Dockerfile:6-10`
```dockerfile
COPY my-ca.crt /usr/local/share/ca-certificates/my-ca.crt
RUN update-ca-certificates
```
**風險描述**:
- 使用自簽憑證可能降低安全性
- 缺乏憑證有效性檢查
- 憑證輪替機制不明確

**影響程度**: 低
**建議修復**:
- 實作憑證有效性檢查
- 建立憑證輪替程序
- 考慮使用受信任的 CA

## 修復優先順序

### 立即修復 (24小時內)
1. 移除或限制 Docker Socket 存取
2. 修復 root 權限執行問題
3. 實作安全的 token 管理

### 短期修復 (1週內)
4. 設定檔化硬編碼值
5. 改善權限管理機制
6. 強化輸入驗證

### 中期改善 (1個月內)
7. 實作健康檢查機制
8. 建立監控和日誌系統
9. 改善憑證管理

## 合規性建議

### CIS Docker Benchmark
- 實作非 root 使用者執行 (CIS 4.1)
- 限制容器權限 (CIS 5.12)
- 避免特權容器 (CIS 5.4)

### OWASP Container Security
- 實作最小權限原則
- 強化容器映像建置
- 機敏資料管理最佳實務

## 後續監控建議

1. **定期掃描**: 每季進行容器安全掃描
2. **權限稽核**: 月度檢查檔案和容器權限
3. **設定審查**: 季度審查安全設定
4. **威脅建模**: 年度更新威脅模型

## 結論

本次評估發現多項需要立即關注的安全風險，特別是 Docker Socket 存取和權限管理問題。建議優先處理高風險項目，並建立持續的安全監控機制。

---

**評估人員**: GitHub Copilot  
**文件版本**: 1.0  
**下次評估日期**: 2025年11月26日
