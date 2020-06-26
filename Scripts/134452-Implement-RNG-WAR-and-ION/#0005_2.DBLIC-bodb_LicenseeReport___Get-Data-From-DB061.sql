/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/
/*   
	Creator: 20200626@Parsons
	Task:   Generate data of SAG for 18/06 - Now [#FeatureID 134452]
	DB:	    DBLIC-bodb_LicenseeReport
	Remark:	Re-gen data for SAG - range bettrans_bk
*/

USE bodb_LicenseeReport
GO

BEGIN
	DECLARE @WinlostDate DATE = '2020-06-18' -- Current BU Date - 1 (BU = 2020-06-19)

	DELETE dbo.rpt_ThirdPartyWL_ExtraGMT WITH (ROWLOCK, UPDLOCK)
	WHERE RptDate = @Winlostdate
			AND BetTypeId BETWEEN 3001 AND 3099 -- SAG
		
	INSERT INTO dbo.rpt_ThirdPartyWL_ExtraGMT (RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm, ProgressiveContribution, ProgressivePayout, ValidBetAmount)
	SELECT RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm, ProgressiveContribution, ProgressivePayout, ValidBetAmount
	FROM DBRPT.bodb_report.dbo.rpt_ThirdPartyWL_ExtraGMT
	WHERE rptDate = @WinlostDate
			AND BetTypeId BETWEEN 3001 AND 3099 -- SAG
END
GO