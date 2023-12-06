/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20231218@Danny
	DB: DBCUST.bodb_Licensee
	Task: Live22 - offer Promotion Prize [#197267]
	Description: Insert Into LA_InvoiceItemType record: Deduct Live22 Promotion
*/
USE bodb_Licensee
GO

DECLARE @L22_Prize INT = 53

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @L22_Prize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@L22_Prize, -1, 'Expense', -1, '', N'Deduct Live22 Promotion')
END
