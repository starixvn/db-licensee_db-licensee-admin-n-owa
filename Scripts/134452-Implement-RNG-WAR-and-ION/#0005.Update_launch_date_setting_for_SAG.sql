/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20200626@Mason
	DB: DBCUST
	Description: Update launch date for SA Gaming [#134452]
*/

USE bodb_licensee
GO

DECLARE @LaunchDate DATE = '2020-06-18'

UPDATE dbo.OAS_ChargeInfo
SET FromDate = @LaunchDate
WHERE ChargeID IN (3640,3641,3642,3643,3644,3645)