/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20200716@Parsons
	DB: DBCUST.bodb_licensee
	Description: Update-Expiry-Date-For-CB-The-Term-Between-OW-And-3rd-Party [#137726]
*/

USE bodb_licensee
GO

DECLARE @ExpiryDate DATE = '2022-06-30'

UPDATE dbo.OAS_ChargeInfo WITH (UPDLOCK,ROWLOCK)
SET ToDate = @ExpiryDate
WHERE ChargeID IN (707, 711)