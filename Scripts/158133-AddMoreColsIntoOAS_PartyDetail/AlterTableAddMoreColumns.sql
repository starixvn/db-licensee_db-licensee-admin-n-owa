/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210811@Danny
	DB: DBCUST.bodb_licensee
	Description: Add column into OAS_PartyDetail
*/

USE bodb_licensee
GO

ALTER TABLE dbo.OAS_PartyDetail ADD [CompanyName2] [nvarchar](100) NULL,
									[AttnName2] [nvarchar](125) NULL	
									

-- UPDATE WAIVE FEE CURRENCY IS NULL			
UPDATE  t
SET		t.CurrencyId = NULL
FROM	dbo.LA_MinFee t WITH(ROWLOCK,UPDLOCK) 
WHERE 	t.FeeTypeId = 2 