/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210401@Parsons
	DB: DBCUST.bodb_Licensee
	Task: LA/NAP - Change back Setting of boma365, GESAB, WKCUR, WKPHIL, VWIN66 to EUR base currency [#FeatureID 152655]
	Description: Change_Back_AMF_of_Wgaming_To_EUR
*/
USE bodb_Licensee 
GO

DECLARE @InvoiceHeaderID_EUR INT =  10139, @InvoiceHeaderID_CNY INT = 10143
PRINT 'Step 1. Delete EUR amount which has been write off'
BEGIN
	DELETE LA_InvoiceHeader WITH (ROWLOCK, UPDLOCK)
	WHERE InvoiceHeaderId = @InvoiceHeaderID_EUR

	DELETE LA_InvoiceStatement WITH (ROWLOCK, UPDLOCK)
	WHERE InvoiceHeaderId = @InvoiceHeaderID_EUR
END

PRINT 'Step 2. Delete CNY amount which has been initilize'
BEGIN
	DELETE LA_InvoiceHeader WITH (ROWLOCK, UPDLOCK)
	WHERE InvoiceHeaderId = @InvoiceHeaderID_CNY

	DELETE LA_InvoiceStatement WITH (ROWLOCK, UPDLOCK)
	WHERE InvoiceHeaderId = @InvoiceHeaderID_CNY
END