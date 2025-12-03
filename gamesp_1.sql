/* 建立資料表：Games */
IF OBJECT_ID('dbo.Games','U') IS NULL
BEGIN
	CREATE TABLE dbo.Games (
		GameID       INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
		PlayerName   NVARCHAR(50)      NOT NULL,
		TargetNumber CHAR(4)           NOT NULL,
		StartTime    DATETIME          NOT NULL DEFAULT(GETDATE()),
		EndTime      DATETIME          NULL
	);
	-- 欄位註解
	EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'開局玩家', @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'Games', @level2type=N'COLUMN',@level2name=N'PlayerName';
	EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'電腦隨機產生的4位數字（不重複，首位不為0）', @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'Games', @level2type=N'COLUMN',@level2name=N'TargetNumber';
	EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'開始時間 (開局時寫入)', @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'Games', @level2type=N'COLUMN',@level2name=N'StartTime';
	EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'結束時間（猜中時寫入）', @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'Games', @level2type=N'COLUMN',@level2name=N'EndTime';
END;

/* 建立資料表：GameGuesses */
IF OBJECT_ID('dbo.GameGuesses','U') IS NULL
BEGIN
	CREATE TABLE dbo.GameGuesses (
		GuessID     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
		GameID      INT               NOT NULL,
		GuessNumber CHAR(4)           NOT NULL,
		Result      VARCHAR(10)       NOT NULL,  -- 範例：'1A 2B'
		GuessTime   DATETIME          NOT NULL DEFAULT(GETDATE())
	);
	ALTER TABLE dbo.GameGuesses
		ADD CONSTRAINT FK_GameGuesses_Games
		FOREIGN KEY (GameID) REFERENCES dbo.Games(GameID);

	-- 欄位註解
	EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'FK 到 Games.GameID', @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'GameGuesses', @level2type=N'COLUMN',@level2name=N'GameID';
	EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'玩家輸入的4位數字（不可重複）', @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'GameGuesses', @level2type=N'COLUMN',@level2name=N'GuessNumber';
	EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'幾A幾B結果，格式例如：''1A 2B''', @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'GameGuesses', @level2type=N'COLUMN',@level2name=N'Result';
	EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'猜測時間', @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'GameGuesses', @level2type=N'COLUMN',@level2name=N'GuessTime';
END;

/* 預存程序：開局 dbo.[sp.gamestart]
   輸入：@PlayerName
   回傳：GameID, StartTime（不回傳 TargetNumber）
*/
-- 1).確認預存程序：開局 dbo.[sp.gamestart]
IF OBJECT_ID('dbo.[sp.gamestart]','P') IS NOT NULL
	DROP PROCEDURE dbo.[sp.gamestart];
GO
-- 2).建立預存程序：開局 dbo.[sp.gamestart]
CREATE PROCEDURE dbo.[sp.gamestart]
	@PlayerName NVARCHAR(50)
AS
BEGIN
	SET NOCOUNT ON;

	IF @PlayerName IS NULL OR LTRIM(RTRIM(@PlayerName)) = ''
	BEGIN
		RAISERROR(N'PlayerName 不可為空', 16, 1);
		RETURN;
	END

	-- 產生不重複且首位不為0的4位數字
	DECLARE @digits TABLE (d CHAR(1));
	INSERT INTO @digits(d) VALUES ('0'),('1'),('2'),('3'),('4'),('5'),('6'),('7'),('8'),('9');

	-- 隨機打散
	DECLARE @shuffled TABLE (ord INT IDENTITY(1,1), d CHAR(1));
	INSERT INTO @shuffled(d)
	SELECT d FROM @digits
	ORDER BY NEWID();

	-- 取第一個非0作為首位
	DECLARE @first CHAR(1);
	SELECT TOP 1 @first = d FROM @shuffled WHERE d <> '0' ORDER BY ord;

	-- 取其餘三位，避免與首位重複
	DECLARE @rest TABLE (d CHAR(1));
	INSERT INTO @rest(d)
	SELECT TOP 3 d FROM @shuffled WHERE d <> @first ORDER BY ord;

	DECLARE @n CHAR(4);
	SELECT @n = @first +
		(SELECT MIN(d) FROM @rest r1) +
		(SELECT MIN(d) FROM @rest r2 WHERE d > (SELECT MIN(d) FROM @rest)) +
		(SELECT MIN(d) FROM @rest r3 WHERE d > (SELECT MIN(d) FROM @rest WHERE d > (SELECT MIN(d) FROM @rest)));

	-- 上述以排序抽取確保不重複；若出現 NULL 代表隨機資料異常
	IF @n IS NULL OR LEN(@n) <> 4
	BEGIN
		RAISERROR(N'隨機產生數字失敗', 16, 1);
		RETURN;
	END

	INSERT INTO dbo.Games(PlayerName, TargetNumber, StartTime)
	VALUES (@PlayerName, @n, GETDATE());

	DECLARE @GameID INT = SCOPE_IDENTITY();

	SELECT @GameID AS GameID, (SELECT StartTime FROM dbo.Games WHERE GameID = @GameID) AS StartTime;
END
GO

/* 預存程序：每回合 dbo.[sp.round]
   輸入：@GameID, @GuessNumber
   回傳：資料集：GameID, GuessNumber, Result(幾A幾B), GuessCount, IsFinished, StartTime, EndTime, DurationSeconds
*/
IF OBJECT_ID('dbo.[sp.round]','P') IS NOT NULL
	DROP PROCEDURE dbo.[sp.round];
GO
CREATE PROCEDURE dbo.[sp.round]
	@GameID INT,
	@GuessNumber CHAR(4)
AS
BEGIN
	SET NOCOUNT ON;

	-- 驗證遊戲存在
	IF NOT EXISTS(SELECT 1 FROM dbo.Games WHERE GameID = @GameID)
	BEGIN
		RAISERROR(N'GameID 不存在', 16, 1);
		RETURN;
	END

	-- 驗證是否已結束
	IF EXISTS(SELECT 1 FROM dbo.Games WHERE GameID = @GameID AND EndTime IS NOT NULL)
	BEGIN
		RAISERROR(N'遊戲已結束', 16, 1);
		RETURN;
	END

	-- 驗證輸入四位且皆為數字且不重複
	IF @GuessNumber IS NULL OR LEN(@GuessNumber) <> 4 OR @GuessNumber LIKE '%[^0-9]%'
	BEGIN
		RAISERROR(N'GuessNumber必須為4位數字', 16, 1);
		RETURN;
	END

	IF (SUBSTRING(@GuessNumber,1,1) = SUBSTRING(@GuessNumber,2,1))
		OR (SUBSTRING(@GuessNumber,1,1) = SUBSTRING(@GuessNumber,3,1))
		OR (SUBSTRING(@GuessNumber,1,1) = SUBSTRING(@GuessNumber,4,1))
		OR (SUBSTRING(@GuessNumber,2,1) = SUBSTRING(@GuessNumber,3,1))
		OR (SUBSTRING(@GuessNumber,2,1) = SUBSTRING(@GuessNumber,4,1))
		OR (SUBSTRING(@GuessNumber,3,1) = SUBSTRING(@GuessNumber,4,1))
	BEGIN
		RAISERROR(N'GuessNumber 每位數字不可重複', 16, 1);
		RETURN;
	END

	DECLARE @Target CHAR(4) = (SELECT TargetNumber FROM dbo.Games WHERE GameID = @GameID);

	-- 計算 A（位置與數字相同）
	DECLARE @A INT = 0, @B INT = 0;

	SET @A = (CASE WHEN SUBSTRING(@Target,1,1)=SUBSTRING(@GuessNumber,1,1) THEN 1 ELSE 0 END)
	      + (CASE WHEN SUBSTRING(@Target,2,1)=SUBSTRING(@GuessNumber,2,1) THEN 1 ELSE 0 END)
	      + (CASE WHEN SUBSTRING(@Target,3,1)=SUBSTRING(@GuessNumber,3,1) THEN 1 ELSE 0 END)
	      + (CASE WHEN SUBSTRING(@Target,4,1)=SUBSTRING(@GuessNumber,4,1) THEN 1 ELSE 0 END);

	-- 計算共同數字數量
	DECLARE @Common INT =
		(SELECT
			(CASE WHEN CHARINDEX(SUBSTRING(@GuessNumber,1,1), @Target) > 0 THEN 1 ELSE 0 END) +
			(CASE WHEN CHARINDEX(SUBSTRING(@GuessNumber,2,1), @Target) > 0 THEN 1 ELSE 0 END) +
			(CASE WHEN CHARINDEX(SUBSTRING(@GuessNumber,3,1), @Target) > 0 THEN 1 ELSE 0 END) +
			(CASE WHEN CHARINDEX(SUBSTRING(@GuessNumber,4,1), @Target) > 0 THEN 1 ELSE 0 END)
		);
	SET @B = @Common - @A;

	DECLARE @Result VARCHAR(10) = CAST(@A AS VARCHAR(10)) + 'A ' + CAST(@B AS VARCHAR(10)) + 'B';

	-- 寫入猜測
	INSERT INTO dbo.GameGuesses(GameID, GuessNumber, Result)
	VALUES (@GameID, @GuessNumber, @Result);

	-- 若猜中（4A），更新結束時間
	IF @A = 4
	BEGIN
		UPDATE dbo.Games
		SET EndTime = GETDATE()
		WHERE GameID = @GameID;
	END

	-- 輸出本回合結果與累計
	DECLARE @StartTime DATETIME = (SELECT StartTime FROM dbo.Games WHERE GameID = @GameID);
	DECLARE @EndTime   DATETIME = (SELECT EndTime   FROM dbo.Games WHERE GameID = @GameID);
	DECLARE @GuessCount INT     = (SELECT COUNT(*)  FROM dbo.GameGuesses WHERE GameID = @GameID);
	DECLARE @DurationSeconds INT = CASE WHEN @EndTime IS NOT NULL THEN DATEDIFF(SECOND, @StartTime, @EndTime) ELSE NULL END;
	DECLARE @IsFinished BIT     = CASE WHEN @EndTime IS NOT NULL THEN 1 ELSE 0 END;

	SELECT
		@GameID        AS GameID,
		@GuessNumber   AS GuessNumber,
		@Result        AS Result,
		@GuessCount    AS GuessCount,
		@IsFinished    AS IsFinished,
		@StartTime     AS StartTime,
		@EndTime       AS EndTime,
		@DurationSeconds AS DurationSeconds;
END
GO

-- 遊玩範例（示意）
-- 開局
EXEC dbo.[sp.gamestart] @PlayerName = N'Lin';

-- 每回合猜測
EXEC dbo.[sp.round] @GameID = 2, @GuessNumber = '6049';
EXEC dbo.[sp.round] @GameID = 1, @GuessNumber = '5678';
-- 當 Result 顯示 4A 0B 時即猜中，會寫入 EndTime 並回傳耗時
SELECT* FROM Games