/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250219@Danny
	DB: DBCUST.bodb_licensee
	Description: Add new license group
*/

USE bodb_licensee
GO

	--DELETE FROM LA_InvoiceTemplate WITH(ROWLOCK) WHERE InvTemplateName LIKE '%Reasternhold%'
	-- Add new Invoice template
	--INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	--VALUES ('Reasternhold', '')

	--INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	--VALUES ('Credit-Reasternhold', '')

	--INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	--VALUES ('Debit-Reasternhold', '')

	--INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	--VALUES ('SetupFees-Reasternhold', '')



	UPDATE  LA_InvoiceTemplate WITH(ROWLOCK)
	SET    InvTemplateName = replace(InvTemplateName,'SabaPlay','Reasternhold')
	WHERE  InvTemplateName LIKE '%SabaPlay%'


	