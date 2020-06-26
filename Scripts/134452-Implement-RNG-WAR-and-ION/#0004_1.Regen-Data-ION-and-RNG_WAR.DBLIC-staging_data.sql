/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/

/*
	Created: 20200626@Parsons
	Task: Generate data of ION & RNGW for 2020-06-16 - Now [#FeatureID 134452]
	DB: DBLIC-bodb_LicenseeReport
	Remark: Re-gen data for ION & RNGW
*/

USE [bodb_LicenseeReport]
GO

DECLARE @ErrorMsg VARCHAR(8000)
EXEC Task_PrepareStaging  @datefrom =  '20200619', @dateto = '20200626', @ErrorMsg = @ErrorMsg OUT, @ProductCodes = 'ION,RNGW'

PRINT '#0006.Regen-Data-ION-and-RNG_WAR.DBLIC-staging_data: ' + @ErrorMsg
GO