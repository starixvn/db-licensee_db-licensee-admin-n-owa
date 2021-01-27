/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/
/*   
	Creator: 20210113@Parsons
	Task:   Generate data of Joker for 2020-11-12 -> Now [#FeatureID 148617]
	DB:	    DBLIC-bodb_LicenseeReport
	Remark:	Re-gen data for Joker - range bettrans_bk
*/

USE bodb_LicenseeReport
GO

DECLARE	
		@FromDate DATE = '2020-11-12', 
		@ToDate DATE = '2021-01-07' -- Current BU Date - 1 (BU = 2021-01-08)

BEGIN
	DECLARE @ErrMsg VARCHAR(200)

	DECLARE @WinlostDate DATE
	SELECT	@WinlostDate = @FromDate

	WHILE (@Winlostdate <= @Todate)
	BEGIN
		SELECT @ErrMsg = 'WinlostDate=' + CONVERT(VARCHAR(20), @WinlostDate, 120)
		RAISERROR(@ErrMsg, 0, 1) WITH NOWAIT

		DELETE dbo.rpt_ThirdPartyWL_ExtraGMT WITH (ROWLOCK, UPDLOCK)
		WHERE RptDate = @Winlostdate
				AND BetTypeId BETWEEN 6401 AND 6700 -- JK
		
		INSERT INTO dbo.rpt_ThirdPartyWL_ExtraGMT (RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm, AWinloss, ProgressiveContribution, ProgressivePayout, ValidBetAmount)
		SELECT RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm, AWinloss, ProgressiveContribution, ProgressivePayout, ValidBetAmount
		FROM DBRPT.bodb_report.dbo.rpt_ThirdPartyWL_ExtraGMT
		WHERE rptDate = @WinlostDate
				AND BetTypeId BETWEEN 6401 AND 6700 -- JK
		
		--reset params
		SET @WinlostDate = DATEADD(DAY, 1, @WinlostDate)

		WAITFOR DELAY '00:00:00.280'
	END	
END
GO