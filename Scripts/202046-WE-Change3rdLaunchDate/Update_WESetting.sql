/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240307@Danny
	DB: DBCUST.bodb_licensee
	Description: Change launch date WE Terms:
*/

USE bodb_licensee
GO



DECLARE @WEProductId INT = 80


UPDATE OAS_ChargeInfo WITH(ROWLOCK)
SET FromDate = '2024-03-04'
WHERE ProductID = @WEProductId AND FromParty IN ( 25,30)


UPDATE OAS_ChargeInfo WITH(ROWLOCK)
SET FromDate = '2024-03-07'
WHERE ProductID = @WEProductId AND FromParty IN ( 1,9,11,98)