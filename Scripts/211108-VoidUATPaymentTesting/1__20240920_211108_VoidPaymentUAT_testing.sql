/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240920@Danny
	DB: DBCUST.bodb_licensee
	Description: Update payment info
*/




UPDATE LA_Payment WITH(ROWLOCK, UPDLOCK) SET StatusId = -1 WHERE 
PaymentId IN
(
1933,
1934,
1935,
1936,
1937,
1938,
1939,
1940,
1941,
1942,
1943,
1944
) and Environment = 'UAT'





