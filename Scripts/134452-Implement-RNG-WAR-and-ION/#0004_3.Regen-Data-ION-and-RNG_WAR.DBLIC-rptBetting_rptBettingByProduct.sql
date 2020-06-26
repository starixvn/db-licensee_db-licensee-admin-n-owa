/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/

/*
	Created: 20200626@Parsons
	Task: Generate data of ION & RNGW for 2020-06-16 - Now [#FeatureID 134452]
	DB:			DBLIC-bodb_LicenseeReport
	Remark:		Re-gen data for ION & RNGW
*/

USE bodb_LicenseeReport
GO

EXEC GEN_rptBetting @date = '20200616', @date2 = '20200626', @ProductCodes = 'ION,RNGW'
GO

EXEC GEN_rptBettingByProduct @date = '20200616', @date2 = '20200626', @DataSource = 'Rpt_Betting', @SeparatedProductID = 0, @ProductCodes = 'ION,RNGW'
GO

EXEC Task_PostStaging
GO