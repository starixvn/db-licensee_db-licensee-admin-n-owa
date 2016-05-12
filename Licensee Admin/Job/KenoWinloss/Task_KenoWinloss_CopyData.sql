USE [bodb_LicenseeReport]
GO

/****** Object:  StoredProcedure [dbo].[Task_KenoWinloss_CopyData]    Script Date: 05/03/2015 16:13:59 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/****** Object:  Stored Procedure dbo.Task_KenoWinloss_CopyData    Script Date: 05/03/2015 15:08:26 PM ******/
CREATE PROCEDURE [dbo].[Task_KenoWinloss_CopyData]
	@Fromdate	DATE
	, @Todate	DATE
AS
/*
	Creator: 20150304@Florent
	Task: Copy data from staging table to main table
	DB: DBLIC/bodb_LicenseeReport
	Revisions: 
	Param's Explanation:

*/
BEGIN
	SET NOCOUNT ON

	IF @Fromdate IS NULL OR @Todate IS NULL
		RETURN

	DECLARE @sql VARCHAR(MAX)
	DECLARE @IndexTable TABLE (RowIndex INT IDENTITY(1,1), rptDate DATE)	
	
	INSERT INTO @IndexTable(rptDate)
	SELECT rptDate
	FROM OPENQUERY(DBARC, 'SELECT rptDate 
						FROM bodb_report.dbo.rptKenoWinlossTmp WITH (NOLOCK)						
						GROUP BY rptDate OPTION (MAXDOP 1)')
	WHERE rptDate BETWEEN @Fromdate AND @Todate

	IF NOT EXISTS (SELECT TOP 1 1 FROM @IndexTable )
		RETURN

	--CREATE TABLE #Data (RptDate DATE, SiteID INT, BetType INT, GameType INT, GameChoice INT, CurrencyID INT, StatusID INT, BetCount INT, Turnover MONEY, Winloss MONEY)
	DECLARE @rptDate DATE, @RowIndex INT
	SET @RowIndex = 1

	WHILE EXISTS (SElECT 1 FROM @IndexTable WHERE RowIndex = @RowIndex)
	BEGIN
		SELECT @rptDate = rptDate FROM @IndexTable WHERE RowIndex = @RowIndex
		SELECT @RowIndex = @RowIndex + 1, @sql = ''

		SELECT @sql = 'SELECT RptDate, SiteId, BetTypeId, KenoBetTypeId, ChoiceId, CurrencyId, StatusId, BetCount, Turnover, Winloss
						FROM OPENQUERY(DBRPT, ''SELECT RptDate, SiteId, BetTypeId, KenoBetTypeId, ChoiceId, CurrencyId, StatusId, BetCount, Turnover, Winloss
												FROM bodb_report.dbo.rptKenoWinlossTmp WITH (NOLOCK) 
												WHERE rptDate = ''''' + CAST(@rptDate AS VARCHAR(20)) + '''''
						OPTION (MAXDOP 1)'')'
		--SELECT @TransDate AS '@TransDate', @sql AS '@sql'
		
		IF EXISTS ( SELECT TOP 1 1 FROM dbo.rptKenoWinloss WITH (NOLOCK) WHERE RptDate = @rptDate)
		BEGIN
			DELETE dbo.rptKenoWinloss WITH (ROWLOCK, UPDLOCK)
			WHERE RptDate = @rptDate
		END
		
		INSERT INTO dbo.rptKenoWinloss(RptDate, SiteId, BetTypeId, KenoBetTypeId, ChoiceId, CurrencyId, StatusId, BetCount, Turnover, Winloss)
		EXECUTE (@sql)
		
		WAITFOR DELAY '00:00:00.280'
	END	
END
GO
GRANT VIEW DEFINITION ON [dbo].[Task_KenoWinloss_CopyData] TO [vnteam] 