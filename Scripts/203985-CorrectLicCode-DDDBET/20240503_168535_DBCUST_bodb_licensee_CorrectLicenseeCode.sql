/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240503@Danny
	DB: DBCUST.bodb_licensee
	Description: 
*/

UPDATE dbo.[LicenseeTransferCode] WITH(ROWLOCK) 
SET CustID = 119515181 --PHL-LSEE-DDDBET EUR
WHERE LicenseeName = 'DDDBET'