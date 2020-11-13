/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20201111@Mason
	DB: DBCUST.bodb_licensee
	Description: Update again the launch date for PG Soft [#138983]
*/

USE bodb_licensee
GO

-- Update launched date PGS (deposit)
UPDATE dbo.OAS_ChargeInfo WITH (UPDLOCK,ROWLOCK)
SET FromDate = '2020-11-12'
WHERE ChargeID IN (4559,4560,4561,4562)