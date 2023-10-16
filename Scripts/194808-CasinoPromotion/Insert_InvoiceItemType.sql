/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20230608@Danny
	DB: DBCUST.bodb_Licensee
	Task: Casino promotion [#194808]
	Description: Insert Into LA_InvoiceItemType record: 
		1. Deduct Casino promotional event
*/
USE bodb_Licensee
GO

DECLARE @Casino_promotion INT = 52

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @Casino_promotion)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@Casino_promotion, -1, 'Expense', -1, '', N' Deduct Casino promotional event')
END

