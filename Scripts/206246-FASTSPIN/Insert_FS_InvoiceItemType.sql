/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240710@Danny
	DB: DBCUST.bodb_Licensee
	Task: Fast Spin - offer Promotion Prize [#206246]
	Description: Insert Into LA_InvoiceItemType record: Deduct Fast Spin Promotion
*/
USE bodb_Licensee
GO

DECLARE @FS_Prize INT = 57

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @FS_Prize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@FS_Prize, -1, 'Expense', -1, '', N'Deduct FastSpin Promotion')
END



