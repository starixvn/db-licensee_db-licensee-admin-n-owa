/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250219@Danny
	DB: DBCUST.bodb_licensee
	Description: Add new license group
*/

USE bodb_licensee
GO
	-- -- Add new group
	 --INSERT INTO OAS_Party (PartyName,	Description	,PartyType,	OldRefID,	SetupName)
	 --VALUES ('Double S System Inc','Double S System Inc', 2, NULL, NULL)

	 UPDATE OAS_Party WITH(ROWLOCK) SET PartyName = 'Double S' WHERE PartyID = 1235


	-- Add new Invoice template
	INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	VALUES ('Double-S', '')

	INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	VALUES ('Credit-Double-S', '')

	INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	VALUES ('Debit-Double-S', '')

	INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	VALUES ('SetupFees-Double-S', '')

	