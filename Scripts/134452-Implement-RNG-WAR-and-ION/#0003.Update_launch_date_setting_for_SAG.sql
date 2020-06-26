/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20200626@Mason
	DB: DBCUST.bodb_licensee
	Description: Update launched date for SA Gaming [#134452]
*/

USE bodb_licensee
GO

DECLARE @LaunchedDate DATE = '2020-06-18'

UPDATE dbo.OAS_ChargeInfo WITH (UPDLOCK,ROWLOCK)
SET FromDate = @LaunchedDate
WHERE ChargeID IN (3640,3641,3642,3643,3644,3645)