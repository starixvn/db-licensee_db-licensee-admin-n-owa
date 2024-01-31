/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20231226@Danny
	DB: DBCUST.bodb_licensee
	Description: Add new license group
*/

USE bodb_licensee
GO
	-- -- Add new group
	-- INSERT INTO OAS_Party (PartyName,	Description	,PartyType,	OldRefID,	SetupName)
	-- VALUES ('Jollysports','Jollysports', 2, NULL, NULL)

	UPDATE OAS_Party WITH(ROWLOCK, UPDLOCK)
	SET    PartyName = 'JollySports'
	WHERE PartyID = 962

	-- Add new Invoice template
	INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	VALUES ('JollySports', '')

	INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	VALUES ('Credit-JollySports', '')

	INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	VALUES ('Debit-JollySports', '')

	INSERT INTO LA_InvoiceTemplate (InvTemplateName, TemplatePath)
	VALUES ('SetupFees-JollySports', '')
