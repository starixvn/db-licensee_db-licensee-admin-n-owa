/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250218@Danny
	DB: DBCUST.bodb_Licensee
	Task: ASK - offer Promotion Prize [#217674]
	Description: Insert Into LA_InvoiceItemType record: Deduct Askmeslot Promotion
*/
USE bodb_Licensee
GO

DECLARE @ASK_Prize INT = 62

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @ASK_Prize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@ASK_Prize, -1, 'Expense', -1, '', N'Deduct ASKMESLOT Promotion')
END
