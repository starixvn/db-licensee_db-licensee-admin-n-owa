/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240805@Danny
	DB: DBCUST.bodb_licensee
	Description: Update GMF From Date
*/

	UPDATE LA_GroupMinFeeHeader WITH(ROWLOCK, UPDLOCK)
	SET FromDate = '2024-07-01'
	WHERE Name = 'JDYgaming group'
	AND FromDate = '2023-07-01'