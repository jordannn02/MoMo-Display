# MoMo Display 0.2.1

macOS 選單列亮度控制 App，優先支援 Apple Silicon MacBook Pro 的內建 Liquid Retina XDR。只保留逐螢幕亮度、XDR 額外增亮與無法使用 DDC 時的軟體調暗。

## 使用

建置後開啟 App，點選選單列太陽圖示即可操作。若要安裝，可將建置產生的 `MoMo Display.app` 複製到「應用程式」資料夾。

- 一個滑桿直接選擇亮度百分比；內建 XDR 為 5–160%，一般／軟體調暗螢幕為 5–100%。
- 100% 是一般最大亮度，超過 100% 時自動使用 XDR；回到 100% 以下會先還原 XDR 再調光。
- 提供 100%、110%、120% 快選按鈕。畫面狀態顯示實際 XDR 啟用結果；設定值不是實測 nits。
- 每次在 App 中選擇亮度都會自動記住。重新啟動、喚醒及螢幕重新連線時，會依螢幕 UUID 還原設定。
- 「登入時自動啟動」使用 macOS 的 SMAppService；可直接在面板中開關，也可由系統設定管理。
- 面板固定在選單列下方，內容可捲動；按 Escape、再按太陽圖示或點選外部可收起。

設定存在目前使用者的 `app.momo.display` UserDefaults，`displayPreferences.v1` 儲存每個螢幕的設定。正常結束時會先還原畫面效果，再保留原先的選擇，供下次啟動使用。這裡記住的是 MoMo Display 內的選擇，沒有輪詢其他調光工具的操作。

超過 100% 仍受當下 EDR headroom 限制，不代表能突破面板物理極限；HDR 影片或色準工作可調回 100%。外接 DDC 無回應時採用軟體調暗，100% 表示沒有額外調暗，並非讀到背光值。軟體調暗不降低螢幕背光耗電。

App 沒有網路連線、更新服務、帳號或追蹤功能，也不要求螢幕錄製／輔助使用權限。還原 gamma 失敗時會保留快照並提示重試，防止正常結束時丟失還原資料。強制終止或崩潰後的恢復未驗證。

## 已驗證的範圍（2026-11-02）

- macOS 27.2、Apple M5 Pro、內建 Liquid Retina XDR 與 24G1WG4。
- 內建螢幕：原生亮度 100% → 98%，讀回 `0.9799999595` → 100%，還原讀回 `1.0`。
- XDR：1.05 倍連續 12 秒，EDR 已啟用（後續 headroom 約 3.998），gamma 最大值讀回約 `1.0499997`；停止後色彩表逐點還原驗證通過，最大值約 `0.99999988`。
- v0.2 原生介面顯示 120% 並已恢復 XDR，登入啟動開關已開啟。未使用光度計，未量測 nits。
- 外接 24G1WG4：服務唯一匹配成功，但 DDC 亮度讀取沒有有效回覆，因此採用軟體調暗。未宣稱其背光寫入已驗證。
- 睡眠、斷線與 gamma 衝突的保護流程已做程式碼審查；尚未做完整長時間／所有硬體實機驗證。完整 1.6 倍上限未作持續實測。

## 從原始碼建置

需要 Xcode 與 macOS SDK；第一版提供 Apple Silicon arm64，最低建置目標 macOS 14，實機驗證僅上述系統。

```sh
./build.sh
open "build/MoMo Display.app"
```

無需下載套件。使用 Swift、AppKit、SwiftUI、Metal 和 macOS Framework。硬體亮度使用 DisplayServices、CoreDisplay、IOAVService 等非公開 API，未來 macOS 更新仍可能需要調整。這是本機 ad-hoc 簽署版本，未做 Developer ID 簽署或 Apple 公證。

`--diagnose` 是唯讀診斷。`--hardware-self-test` 與 `--effects-self-test` **會短暫改動螢幕**，只供開發者明確執行；請不要在主程式正在增亮時同時執行測試。`--window` 可將控制面板開成視窗；`--show` 顯示選單列面板；`--login-status` 只讀回登入項目狀態。

## 原始碼與授權

整體為 GPL-3.0-only，完整授權在 `LICENSE`。硬體支援改寫自 MonitorControl（MIT），XDR 方法改寫自 BrightIntosh（GPL-3.0）；各來源版本、修改摘要與版權在 `THIRD_PARTY.md`。這是獨立專案。
