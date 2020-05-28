/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/
/*   
	Creator: 20200525@Parsons
	Task:   Generate data of SXG & SG for Mar - Now [#FeatureID 132665]
	DB:	    DBLIC-bodb_LicenseeReport
	Remark:	Re-gen data for SXG & SG - range bettrans_bk
*/

USE bodb_LicenseeReport
GO

DECLARE	
		@FromDate DATE = '2020-03-06', 
		@ToDate DATE = '2020-05-14' -- Current BU Date - 1 (BU = 2020-05-15)

BEGIN
	DECLARE @ErrMsg VARCHAR(200)

	DECLARE @WinlostDate DATE
	SELECT	@WinlostDate = @FromDate

	WHILE (@Winlostdate <= @Todate)
	BEGIN
		SELECT @ErrMsg = 'WinlostDate=' + CONVERT(VARCHAR(20), @WinlostDate, 120)
		RAISERROR(@ErrMsg, 1, 0) WITH NOWAIT

		DELETE dbo.rpt_ThirdPartyWL_ExtraGMT WITH (ROWLOCK, UPDLOCK)
		WHERE RptDate = @Winlostdate
				AND (
				BetTypeId BETWEEN 4301 AND 4600 -- SG
				OR BetTypeId BETWEEN 3101 AND 3199 -- SXG
			)
		
		INSERT INTO dbo.rpt_ThirdPartyWL_ExtraGMT (RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm, ProgressiveContribution, ProgressivePayout, ValidBetAmount)
		SELECT RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm, ProgressiveContribution, ProgressivePayout, ValidBetAmount
		FROM DBRPT.bodb_report.dbo.rpt_ThirdPartyWL_ExtraGMT
		WHERE rptDate = @WinlostDate
				AND (
					BetTypeId BETWEEN 4301 AND 4600 -- SG
					OR BetTypeId BETWEEN 3101 AND 3199 -- SXG
				)
		
		--reset params
		SET @WinlostDate = DATEADD(DAY, 1, @WinlostDate)

		WAITFOR DELAY '00:00:00.280'
	END	
END
GO