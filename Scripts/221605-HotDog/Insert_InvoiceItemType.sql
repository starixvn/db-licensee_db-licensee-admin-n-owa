/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250416@Corbin
	DB: DBCUST.bodb_Licensee
	Task: HOTDOG - offer Promotion Prize #221605]
	Description: Insert Into LA_InvoiceItemType record: Deduct HOTDOG Promotion
*/
USE bodb_Licensee
GO

DECLARE @HOT_Prize INT = 63

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @HOT_Prize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@HOT_Prize, -1, 'Expense', -1, '', N'Deduct HOTDOG Promotion')
END
