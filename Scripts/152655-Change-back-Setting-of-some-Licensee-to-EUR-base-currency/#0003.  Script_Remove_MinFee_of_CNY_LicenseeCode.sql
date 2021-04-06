/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210401@Parsons
	DB: DBCUST.bodb_Licensee
	Task: LA/NAP - Change back Setting of boma365, GESAB, WKCUR, WKPHIL, VWIN66 to EUR base currency [#FeatureID 152655]
	Description: Remove CNY MinFee
*/
USE bodb_Licensee 
GO

PRINT 'DELETE 5 CNY MinFee'

DELETE LA_MinFee WITH (ROWLOCK, UPDLOCK)
WHERE MinFeeId IN (1165, 1178, 1213, 1216, 1217)