/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/
/*   
	Creator: 20200626@Parsons
	Task:   Generate data of SAG for 01/06 - Now [#FeatureID 134452]
	DB:	    DBLIC-bodb_LicenseeReport
	Remark:	Re-gen data for SAG - range bettrans_bk
*/

USE bodb_LicenseeReport
GO

BEGIN
DECLARE	
		@FromDate DATE = '2020-06-01',
		@ToDate DATE = '2020-06-18' -- Current BU Date - 1 (BU = 2020-06-19)

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
						AND BetTypeId BETWEEN 3001 AND 3099 -- SAG
		
				INSERT INTO dbo.rpt_ThirdPartyWL_ExtraGMT (RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm, ProgressiveContribution, ProgressivePayout, ValidBetAmount)
				SELECT RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm, ProgressiveContribution, ProgressivePayout, ValidBetAmount
				FROM DBRPT.bodb_report.dbo.rpt_ThirdPartyWL_ExtraGMT WITH(NOLOCK)
				WHERE rptDate = @WinlostDate
						AND BetTypeId BETWEEN 3001 AND 3099 -- SAG
		
				--reset params
				SET @WinlostDate = DATEADD(DAY, 1, @WinlostDate)

				WAITFOR DELAY '00:00:00.280'
			END	
		END
END
GO