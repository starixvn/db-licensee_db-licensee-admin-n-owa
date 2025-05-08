/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250502@Corbin
	DB: DBCUST.bodb_Licensee
	Task: HOTDOG - offer Promotion Prize #225057]
	Description: Insert Into LA_InvoiceItemType record: Deduct RichGaming Promotion
*/
USE bodb_Licensee
GO

DECLARE @RGRNG_Prize INT = 65

IF NOT EXISTS (SELECT TOP 1 1 FROM dbo.LA_InvoiceItemType WITH(NOLOCK) WHERE InvItemTypeId = @RGRNG_Prize)
BEGIN
	INSERT dbo.LA_InvoiceItemType (InvItemTypeId, SignDB, GroupDB, SignSOA, GroupSOA, InvItemTypeName)
	VALUES (@RGRNG_Prize, -1, 'Expense', -1, '', N'Deduct RichGaming Promotion')
END


