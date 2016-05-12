USE [bodb_LicenseeReport]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[Task_Microgaming_CopyData]
	@Fromdate	DATE
	, @Todate	DATE
AS
/*
	Creator: 20150731@Florent
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
						FROM bodb_report.dbo.rpt_ThirdPartyWL_ExtraGMTTemp WITH (NOLOCK)						
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

		SELECT @sql = 'SELECT RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm
						FROM OPENQUERY(DBRPT, ''SELECT RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm
												FROM bodb_report.dbo.rpt_ThirdPartyWL_ExtraGMTTemp WITH (NOLOCK) 
												WHERE rptDate = ''''' + CAST(@rptDate AS VARCHAR(20)) + '''''
						OPTION (MAXDOP 1)'')'
		--SELECT @TransDate AS '@TransDate', @sql AS '@sql'
		
		IF EXISTS ( SELECT TOP 1 1 FROM dbo.rpt_ThirdPartyWL_ExtraGMT WITH (NOLOCK) WHERE RptDate = @rptDate)
		BEGIN
			DELETE dbo.rpt_ThirdPartyWL_ExtraGMT WITH (ROWLOCK, UPDLOCK)
			WHERE RptDate = @rptDate
		END
		
		INSERT INTO dbo.rpt_ThirdPartyWL_ExtraGMT(RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm)
		EXECUTE (@sql)
		
		WAITFOR DELAY '00:00:00.280'
	END	
END



GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 



