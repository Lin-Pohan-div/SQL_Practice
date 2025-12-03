---
agent: edit
---
# 目的
依照ABGame資料庫中的資料表建立一個幾A幾B的遊戲

# 遊戲玩法與流程
1.開局時電腦隨機產生一個數字
2.玩家隨機輸入數字
3.依照玩家輸入的數字進行判斷，
  若數字與位置正確為Result，
4.當玩家輸入的數字完全符合電腦隨機產生的數字，就會顯示猜對了並結束本輪遊戲

# 功能需求
-電腦開局時生成4位數字，四位數字皆不可重複，且首位不為0
-數字範圍為 0-9
-每輪遊戲開使時需記錄：TargetNumber、GameID、PlayerName、StartTime
-每輪遊戲結束後需記錄玩家猜測次數、遊戲結束時間、玩家遊戲時長(StartTime-EndTime)
-欄位需加上註解
-MVP設計
-產生預存程序遊玩範例

# 預存程序
- 開局 ==> (新建預存程序，名稱為 dbo.[sp.gamestart])
  * 檢查玩家是否存在（非空）
  * 開局（產生不重複且首位不為0的4位數字）
  * 隨機打散後取四位，並確保每位彼此不重複
  * 回傳新遊戲的GameID與開局時間；不回傳 TargetNumber 以免洩漏

- 每回合 ==> (新建預存程序，名稱為 dbo.[sp.round])
  * 傳入使用者輸入的數字(GuessNumber)後以資料集傳出猜測結果
  * 驗證遊戲存在
  * 驗證遊戲是否已結束
  * 驗證輸入為四位數字且每位數字不可重複
  * 計算幾A幾B、嘗試次數並顯示
  * 若玩家猜中，則更新結束時間並計算時長

# 資料庫建置方式
Database DML、TCL

# 預定使用資料表
- Games
  * GameID        INT               NOT NULL PRIMARY KEY
  * PlayerName    NVARCHAR(50)      NOT NULL     -- 玩家名稱
  * TargetNumber  CHAR(4)           NOT NULL     -- 電腦隨機產生的目標4位數字（不重複）
  * StartTime     DATETIME          NULL         -- 開始時間 (開局時寫入)
  * EndTime       DATETIME          NULL         -- 結束時間（猜中時寫入）

- GameGuesses
  * GuessID       INT               NOT NULL PRIMARY KEY
  * GameID        INT               NOT NULL     -- FK 到 Games.GameID
  * GuessNumber   CHAR(4)           NOT NULL     -- 玩家輸入的4位數字
  * Result        VARCHAR(10)       NOT NULL     -- 猜測結果
  * GuessTime     DATETIME          NULL         -- 猜測時間

# 範例
-- 開局
EXEC dbo.[sp.gamestart] @PlayerName = N'Player1';
-- 每回合
EXEC dbo.[sp.round] @GameID = 1, @GuessNumber = '1234';
