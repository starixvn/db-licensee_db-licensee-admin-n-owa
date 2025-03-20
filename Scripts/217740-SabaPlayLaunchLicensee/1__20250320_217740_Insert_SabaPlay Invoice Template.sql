/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250219@Danny
	DB: DBCUST.bodb_licensee
	Description: Add new license group
*/

USE bodb_licensee
GO

	-- Add new Invoice template
	INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	VALUES ('SabaPlay', '')

	INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	VALUES ('Credit-SabaPlay', '')

	INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	VALUES ('Debit-SabaPlay', '')

	INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	VALUES ('SetupFees-SabaPlay', '')

	