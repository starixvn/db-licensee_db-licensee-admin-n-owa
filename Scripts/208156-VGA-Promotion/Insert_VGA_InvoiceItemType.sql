/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240723@Danny
	DB: DBCUST.bodb_Licensee
	Task: VGaming - offer Promotion Prize [#208156]
	Description: Insert Into LA_InvoiceItemType record: Deduct Vgaming Promotion
*/
USE bodb_Licensee
GO

DECLARE @VGA_Prize INT = 58

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @VGA_Prize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@VGA_Prize, -1, 'Expense', -1, '', N'Deduct Vgaming Promotion')
END



